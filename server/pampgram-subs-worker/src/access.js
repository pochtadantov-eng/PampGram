/**
 * Access gate: the single answer to "may this account use the app right now?".
 *
 * The app is locked behind a licence. An account is in exactly one of four states:
 *
 *   "active"  – has a pro subscription (permanent or not yet expired) and is not banned.
 *   "none"    – never activated a key.
 *   "expired" – had a time-limited subscription and it ran out.
 *   "banned"  – has a full ban ("ban:<id>" with `full`). A ban beats an active subscription.
 *
 * The app shows a full-screen lock for everything except "active" (see
 * mod/components/PampGramCore/Sources/PampGramAccessGate.swift).
 *
 * Why Ed25519 and not the HMAC the older routes use: an HMAC key has to be baked into the app,
 * so anyone who pulls it out of the binary can sign "active" for themselves. Here the app holds
 * only the PUBLIC key; the private key (ACCESS_SIGNING_KEY secret) never leaves this Worker, so
 * a forged "active" answer is impossible without patching the app itself.
 *
 * Replay protection: the app sends a fresh random `nonce` with each request and the signature
 * covers it, so a recorded "active" answer can't be played back later (e.g. after a ban).
 * `ttl` (signed too) says how long the app may keep trusting the answer if it can't reach the
 * server again; past that it locks.
 *
 * Tamper log: "tamper:<id>" -> JSON { first, at, count, kinds: [...] }. Written when the app
 * reports activity on an account that is locked (balance edits, a removed lock overlay, a
 * rolled-back clock, a key redeemed while banned...). For a BANNED account that is escalated:
 * the subscription and the synced ledger are wiped, the ban becomes permanent for the bot/
 * admin tools (only /unban clears it), and the admins get a Telegram message.
 */

import { isValidAccountId, readBanRecord } from "./core.js";
import { recordAppSeen, getUser } from "./users.js";
import { createTelegram, trySend } from "./bot/telegram.js";

/** How long an "active" answer may be trusted offline: 48 hours. */
export const ACCESS_TTL_MS = 48 * 60 * 60 * 1000;
const MAX_TAMPER_KINDS = 12;
const NONCE_PATTERN = /^[A-Za-z0-9]{16,64}$/;
const KIND_PATTERN = /^[a-z0-9_.-]{1,40}$/;

function adminIds(env) {
	return String(env.ADMIN_TG_IDS ?? "")
		.split(",")
		.map((part) => part.trim())
		.filter(Boolean);
}

/** The licence part only (ignores bans): "active" | "none" | "expired". */
export async function readLicense(env, idString, now = Date.now()) {
	if (adminIds(env).includes(idString)) {
		return { state: "active", expiresAt: null };
	}
	const stored = await env.SUBS.get(`sub:${idString}`);
	if (!stored) {
		return { state: "none", expiresAt: null };
	}
	if (stored === "pro") {
		return { state: "active", expiresAt: null };
	}
	if (stored === "standard") {
		return { state: "none", expiresAt: null };
	}
	try {
		const parsed = JSON.parse(stored);
		if (parsed.tier !== "pro") {
			return { state: "none", expiresAt: null };
		}
		const expiresAt = typeof parsed.expiresAt === "number" ? parsed.expiresAt : null;
		if (expiresAt !== null && expiresAt <= now) {
			return { state: "expired", expiresAt };
		}
		return { state: "active", expiresAt };
	} catch {
		return { state: "none", expiresAt: null };
	}
}

/** Full picture: ban first, then the licence. */
export async function computeAccess(env, idString, now = Date.now()) {
	if (adminIds(env).includes(idString)) {
		return { state: "active", expiresAt: null, reason: null, tamper: false };
	}
	const ban = await readBanRecord(env, idString);
	if (ban.full) {
		const tamper = await env.SUBS.get(`tamper:${idString}`);
		return { state: "banned", expiresAt: null, reason: ban.full.reason, tamper: Boolean(tamper) };
	}
	const license = await readLicense(env, idString, now);
	return { state: license.state, expiresAt: license.expiresAt, reason: null, tamper: false };
}

function base64ToBytes(value) {
	const binary = atob(value);
	const bytes = new Uint8Array(binary.length);
	for (let i = 0; i < binary.length; i++) {
		bytes[i] = binary.charCodeAt(i);
	}
	return bytes;
}

function bytesToBase64(bytes) {
	let binary = "";
	for (const byte of bytes) {
		binary += String.fromCharCode(byte);
	}
	return btoa(binary);
}

let cachedKey = null;
let cachedKeySource = null;

async function importSigningKey(env) {
	const source = env.ACCESS_SIGNING_KEY;
	if (typeof source !== "string" || source.length === 0) {
		return null;
	}
	if (cachedKey && cachedKeySource === source) {
		return cachedKey;
	}
	const key = await crypto.subtle.importKey("pkcs8", base64ToBytes(source), { name: "Ed25519" }, false, ["sign"]);
	cachedKey = key;
	cachedKeySource = source;
	return key;
}

/** The exact string both sides sign / verify. Keep in sync with PampGramAccessGate.swift. */
export function accessMessage({ id, state, expiresAt, now, ttl, nonce }) {
	return `access1|${id}|${state}|${expiresAt ?? "null"}|${now}|${ttl}|${nonce}`;
}

export async function signAccessMessage(env, message) {
	const key = await importSigningKey(env);
	if (!key) {
		return null;
	}
	const signature = await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(message));
	return bytesToBase64(new Uint8Array(signature));
}

function json(body, status = 200) {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
	});
}

/**
 * How often an app's "last seen" is written. The app asks /access every minute; writing on every
 * request used up Cloudflare's free daily KV write quota (1000/day) within hours, after which
 * every other write — keys, orders, the bot's own state — failed for the rest of the day.
 */
export const SEEN_WRITE_INTERVAL_MS = 60 * 60 * 1000;

/** Records that the app was seen, at most once per SEEN_WRITE_INTERVAL_MS per account. */
export async function noteAppSeen(env, id, info, now = Date.now()) {
	const last = Number(await env.SUBS.get(`seen:${id}`)) || 0;
	if (now - last < SEEN_WRITE_INTERVAL_MS) {
		// Still write right away when something the admin sees changed (new app version, new
		// username/name) — that's rare, unlike the once-a-minute polls.
		const user = await getUser(env, id);
		const same = (value, stored, length) => {
			const text = String(value ?? "").trim().replace(/^@/, "").slice(0, length);
			return text === "" || text === String(stored ?? "");
		};
		if (user && same(info?.version, user.appVersion, 16) && same(info?.build, user.appBuild, 16) && same(info?.username, user.username, 40) && same(info?.name, user.name, 80)) {
			return false;
		}
	}
	await env.SUBS.put(`seen:${id}`, String(now));
	await recordAppSeen(env, id, info, now).catch(() => {});
	return true;
}

/** GET /access?id=<id>&nonce=<16-64 alnum>[&v&b&u&n telemetry as on /status] */
export async function handleAccess(request, env, ctx) {
	const url = new URL(request.url);
	const id = url.searchParams.get("id");
	const nonce = url.searchParams.get("nonce");
	if (!isValidAccountId(id)) {
		return json({ error: "invalid id" }, 400);
	}
	if (typeof nonce !== "string" || !NONCE_PATTERN.test(nonce)) {
		return json({ error: "invalid nonce" }, 400);
	}
	if (!env.ACCESS_SIGNING_KEY) {
		return json({ error: "access signing is not configured" }, 503);
	}

	const now = Date.now();
	const access = await computeAccess(env, id, now);
	let ttl = 0;
	if (access.state === "active") {
		ttl = access.expiresAt === null ? ACCESS_TTL_MS : Math.max(0, Math.min(ACCESS_TTL_MS, access.expiresAt - now));
	}
	const message = accessMessage({ id, state: access.state, expiresAt: access.expiresAt, now, ttl, nonce });
	const sig = await signAccessMessage(env, message);

	ctx.waitUntil(
		noteAppSeen(env, id, { version: url.searchParams.get("v"), build: url.searchParams.get("b"), username: url.searchParams.get("u"), name: url.searchParams.get("n") }, now).catch(() => {})
	);

	return json({ state: access.state, expiresAt: access.expiresAt, now, ttl, nonce, reason: access.reason, tamper: access.tamper, sig });
}

async function notifyAdmins(env, text) {
	if (!env.BOT_TOKEN) {
		return;
	}
	try {
		const tg = createTelegram(env);
		for (const adminId of adminIds(env)) {
			await trySend(tg, adminId, text);
		}
	} catch {
		// Best effort only: a Telegram outage must never break the tamper bookkeeping.
	}
}

/**
 * Records one piece of suspicious activity on `idString`. Only a BANNED account is escalated;
 * for anyone else it is just counted (the route is public, so escalating a non-banned account
 * would let a third party get someone banned by reporting their id).
 * Returns { escalated: boolean }.
 */
export async function recordTamper(env, idString, kind, now = Date.now()) {
	if (adminIds(env).includes(idString)) {
		return { escalated: false };
	}
	const safeKind = typeof kind === "string" && KIND_PATTERN.test(kind) ? kind : "unknown";
	let record = { first: now, at: now, count: 0, kinds: [] };
	const stored = await env.SUBS.get(`tamper:${idString}`);
	if (stored) {
		try {
			record = { ...record, ...JSON.parse(stored) };
		} catch {
			// keep the fresh record
		}
	}
	record.count = (Number.isInteger(record.count) ? record.count : 0) + 1;
	record.at = now;
	record.kinds = [...(Array.isArray(record.kinds) ? record.kinds : []), safeKind].slice(-MAX_TAMPER_KINDS);

	const ban = await readBanRecord(env, idString);
	if (!ban.full) {
		// Not banned: log it for the admin's eyes, change nothing about the account.
		await env.SUBS.put(`tamper:${idString}`, JSON.stringify(record));
		return { escalated: false };
	}

	await env.SUBS.put(`tamper:${idString}`, JSON.stringify(record));
	// Wipe everything the account could still hold: its subscription, its synced balances and
	// any gift transfers still queued for it.
	await env.SUBS.delete(`sub:${idString}`);
	await env.SUBS.delete(`ledgersync:${idString}`);
	const queued = await env.SUBS.list({ prefix: `gifttransfer:${idString}:`, limit: 20 });
	await Promise.all(queued.keys.map((entry) => env.SUBS.delete(entry.name)));

	if (record.count === 1) {
		await notifyAdmins(env, `⚠️ Активность на заблокированном аккаунте <code>${idString}</code>: ${safeKind}. Подписка и баланс обнулены, блокировка окончательная (снимается только через «Разбанить»).`);
	}
	return { escalated: true };
}

/** POST /report-tamper  { id, kind } — sent by the app when it sees activity on a locked account. */
export async function handleReportTamper(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return json({ error: "invalid json" }, 400);
	}
	const { id, kind } = payload ?? {};
	const idString = typeof id === "number" ? String(id) : id;
	if (!isValidAccountId(idString)) {
		return json({ error: "invalid id" }, 400);
	}
	const result = await recordTamper(env, idString, kind);
	return json({ ok: true, escalated: result.escalated });
}

/** Deleted by /unban (full or all): an admin's explicit decision clears the tamper flag too. */
export async function clearTamper(env, idString) {
	await env.SUBS.delete(`tamper:${idString}`);
}
