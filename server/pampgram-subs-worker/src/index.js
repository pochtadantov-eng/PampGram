/**
 * PampGram subscription backend.
 *
 * The only part of PampGram that isn't purely local: a subscription an admin grants has to
 * be visible on the *other* person's device, and there's no way to make that true without a
 * server both copies of the app can ask. Everything else this stores is one number per
 * Telegram account id — no messages, no chat content, nothing else ever passes through here.
 *
 * Storage: a single Workers KV namespace (binding SUBS).
 *   key "sub:<id>"  -> "pro" | "standard" (permanent grant, no expiry)
 *                      | JSON { "tier": "pro"|"standard", "expiresAt": <ms since epoch> }
 *                      (time-limited grant — checked and treated as "standard" once past)
 *   key "ban:<id>"  -> JSON { "full": "<reason>"|null, "sections": { "<section>": "<reason>" } }
 *   key "key:<KEY>" -> "pro" | "standard" (permanent key)
 *                      | JSON { "tier": "pro"|"standard", "durationHours": <number> }
 *                      (time-limited key — the clock starts at redemption, not at minting)
 *                      only while the key is still unredeemed
 * Same posture throughout: a key that would only ever store the "nothing going on" value is
 * deleted instead of written, so the store only ever holds actual overrides.
 *
 * Routes:
 *   GET  /status?id=<telegram account id>
 *     -> { "tier": "standard" | "pro", "expiresAt": <ms since epoch> | null }
 *     Public — every PampGram install calls this for its OWN account id to know whether to
 *     show PRO or STANDARD (and, if the grant is time-limited, when it runs out). No auth: the
 *     response never carries anything more sensitive than "this account is on tier X until
 *     time Y", and requiring auth here would mean embedding a *readable* secret in every copy
 *     of the app for zero benefit. A tier past its `expiresAt` reads back as "standard" —
 *     nothing needs to actively revoke it.
 *
 *   GET  /ban-status?id=<telegram account id>
 *     -> { "full": "<reason>"|null, "sections": { "<section>": "<reason>" } }
 *     Public, same reasoning as /status — every install checks its own ban state before
 *     opening the hub or a section.
 *
 *   POST /grant
 *     body: { "id": <telegram account id>, "tier": "pro" | "standard", "token": "<ADMIN_TOKEN>",
 *             "durationHours": <number> (optional — omit or 0 for a permanent grant) }
 *     -> { "ok": true, "expiresAt": <ms since epoch> | null }
 *     Sets the tier for that account, permanently or until `durationHours` from now.
 *     `durationHours` counts fractional days as hours too — 3 days is `durationHours: 72`, not
 *     a separate days field, so the clock is exact regardless of how the admin screen splits
 *     it into days/hours for typing. Requires token to match the ADMIN_TOKEN secret — set
 *     with `wrangler secret put ADMIN_TOKEN`, never committed to the repo. The client only
 *     ever calls this from the admin screen, which the app itself only shows for one
 *     hardcoded Telegram account id — but that's a client-side UI gate, not a security
 *     boundary; the token is the actual boundary; it's still committed to the app binary
 *     bundled with this Worker's URL, so someone who reverse-engineers the app could recover
 *     it. That's an accepted, documented limit of a "no real backend auth" hobby project, not
 *     a defense against a determined attacker.
 *
 *   POST /ban
 *     body: { "id": <id>, "token": "<ADMIN_TOKEN>", "scope": "full" | "section",
 *             "section": "<section>" (required when scope is "section"), "reason": "<text>" }
 *     -> { "ok": true }
 *     Admin-only, same token as /grant. "full" blocks every PampGram section at once;
 *     "section" blocks just the named one. Setting one doesn't clear the other — a fully
 *     banned account can also carry section reasons from before, they just don't matter while
 *     the full ban is in effect.
 *
 *   POST /unban
 *     body: { "id": <id>, "token": "<ADMIN_TOKEN>", "scope": "full" | "section" | "all",
 *             "section": "<section>" (required when scope is "section") }
 *     -> { "ok": true }
 *     Admin-only. "all" clears the full ban and every section ban together.
 *
 *   POST /banned-list
 *     body: { "token": "<ADMIN_TOKEN>" }
 *     -> { "users": [{ "id": "<id>", "full": "<reason>"|null, "sections": {...} }, ...] }
 *     Admin-only — backs the admin panel's "Разбанить" screen. Token goes in the body rather
 *     than a query string, same reasoning as /grant: never put the secret somewhere that ends
 *     up in a server log line.
 *
 *   POST /generate-key
 *     body: { "token": "<ADMIN_TOKEN>", "tier": "pro" | "standard",
 *             "durationHours": <number> (optional — omit or 0 for a permanent key) }
 *     -> { "ok": true, "key": "<KEY>", "tier": "pro" | "standard", "durationHours": <number> | null }
 *     Admin-only. Mints one fresh, unused activation key for the given tier and stores it as
 *     its own KV entry — a key exists only for as long as it's unredeemed, same posture as the
 *     "nothing going on" fields above. Meant to be sold or given out once; whoever redeems it
 *     first (see /redeem-key) gets the tier, and the key stops existing. `durationHours` is
 *     stored on the key itself, not turned into a fixed `expiresAt` at mint time — the buyer's
 *     clock starts when *they* redeem it, however long that takes.
 *
 *   POST /redeem-key
 *     body: { "id": <telegram account id>, "key": "<KEY>" }
 *     -> { "ok": true, "tier": "pro" | "standard", "expiresAt": <ms since epoch> | null }
 *     Public, no admin token — this is the buyer-facing counterpart to /generate-key, called
 *     from any install once its owner has a key. Grants the key's tier to `id` exactly like
 *     /grant would (starting the key's own duration, if it has one, from this moment), then
 *     deletes the key so it can never be redeemed again. An unknown or already-redeemed key
 *     returns 404 — there is nothing left in the store to tell the difference between the two
 *     once a key is gone, and that's intentional: an already-used key should look exactly as
 *     invalid as one that was never real.
 */

const ALLOWED_TIERS = new Set(["standard", "pro"]);
const ALLOWED_SECTIONS = new Set(["gifts", "messages", "ghost"]);

function jsonResponse(body, status = 200) {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "content-type": "application/json; charset=utf-8" },
	});
}

function isValidAccountId(value) {
	return typeof value === "string" && /^-?\d{1,20}$/.test(value);
}

// Reads "sub:<id>", resolving the legacy bare-string form and the JSON
// { tier, expiresAt } form alike, and treating a past expiresAt as "standard, no expiry" —
// nothing needs to actively sweep an expired entry for correctness, `/status` already reports
// it right. `durationHours` may be fractional (an admin who mixes days and hours contributes a
// float number of hours); `expiresAt` is always the exact resulting millisecond, never rounded.
async function readSubscription(env, idString) {
	const stored = await env.SUBS.get(`sub:${idString}`);
	if (!stored) {
		return { tier: "standard", expiresAt: null };
	}
	if (ALLOWED_TIERS.has(stored)) {
		return { tier: stored, expiresAt: null };
	}
	try {
		const parsed = JSON.parse(stored);
		if (ALLOWED_TIERS.has(parsed.tier)) {
			const expiresAt = typeof parsed.expiresAt === "number" ? parsed.expiresAt : null;
			if (expiresAt !== null && expiresAt <= Date.now()) {
				return { tier: "standard", expiresAt: null };
			}
			return { tier: parsed.tier, expiresAt };
		}
	} catch {
		// Falls through to the "standard" default below — an unparseable value is treated the
		// same as no value at all, never as an error surfaced to the caller.
	}
	return { tier: "standard", expiresAt: null };
}

// Writes "sub:<id>" for a grant starting now. `durationHours` of `null`/`0` is a permanent
// grant (stored as the plain legacy string, so an old client reading it directly still works);
// anything positive is stored with its own resolved `expiresAt`.
async function writeSubscription(env, idString, tier, durationHours) {
	if (tier === "standard") {
		// Standard is the default for anything not in KV — deleting keeps the store from
		// growing with entries that carry no information beyond "not overridden".
		await env.SUBS.delete(`sub:${idString}`);
		return null;
	}
	if (!durationHours || durationHours <= 0) {
		await env.SUBS.put(`sub:${idString}`, tier);
		return null;
	}
	const expiresAt = Date.now() + durationHours * 60 * 60 * 1000;
	await env.SUBS.put(`sub:${idString}`, JSON.stringify({ tier, expiresAt }));
	return expiresAt;
}

async function handleStatus(request, env) {
	const url = new URL(request.url);
	const id = url.searchParams.get("id");
	if (!isValidAccountId(id)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	const { tier, expiresAt } = await readSubscription(env, id);
	return jsonResponse({ tier, expiresAt });
}

async function handleGrant(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	const { id, tier, token, durationHours } = payload ?? {};

	if (typeof token !== "string" || token.length === 0 || token !== env.ADMIN_TOKEN) {
		return jsonResponse({ error: "unauthorized" }, 401);
	}
	const idString = typeof id === "number" ? String(id) : id;
	if (!isValidAccountId(idString)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	if (!ALLOWED_TIERS.has(tier)) {
		return jsonResponse({ error: "invalid tier" }, 400);
	}
	if (durationHours !== undefined && (typeof durationHours !== "number" || !(durationHours >= 0))) {
		return jsonResponse({ error: "invalid durationHours" }, 400);
	}

	const expiresAt = await writeSubscription(env, idString, tier, durationHours);

	return jsonResponse({ ok: true, expiresAt });
}

function isAuthorized(token, env) {
	return typeof token === "string" && token.length > 0 && token === env.ADMIN_TOKEN;
}

async function readBanRecord(env, idString) {
	const stored = await env.SUBS.get(`ban:${idString}`);
	if (!stored) {
		return { full: null, sections: {} };
	}
	try {
		const parsed = JSON.parse(stored);
		return {
			full: typeof parsed.full === "string" ? parsed.full : null,
			sections: parsed.sections && typeof parsed.sections === "object" ? parsed.sections : {},
		};
	} catch {
		return { full: null, sections: {} };
	}
}

async function writeBanRecord(env, idString, record) {
	if (!record.full && Object.keys(record.sections).length === 0) {
		await env.SUBS.delete(`ban:${idString}`);
	} else {
		await env.SUBS.put(`ban:${idString}`, JSON.stringify(record));
	}
}

async function handleBanStatus(request, env) {
	const url = new URL(request.url);
	const id = url.searchParams.get("id");
	if (!isValidAccountId(id)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	return jsonResponse(await readBanRecord(env, id));
}

async function handleBan(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	const { id, token, scope, section, reason } = payload ?? {};

	if (!isAuthorized(token, env)) {
		return jsonResponse({ error: "unauthorized" }, 401);
	}
	const idString = typeof id === "number" ? String(id) : id;
	if (!isValidAccountId(idString)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	if (scope !== "full" && scope !== "section") {
		return jsonResponse({ error: "invalid scope" }, 400);
	}
	if (scope === "section" && !ALLOWED_SECTIONS.has(section)) {
		return jsonResponse({ error: "invalid section" }, 400);
	}
	if (typeof reason !== "string" || reason.trim().length === 0) {
		return jsonResponse({ error: "invalid reason" }, 400);
	}

	const record = await readBanRecord(env, idString);
	if (scope === "full") {
		record.full = reason.trim();
	} else {
		record.sections[section] = reason.trim();
	}
	await writeBanRecord(env, idString, record);

	return jsonResponse({ ok: true });
}

async function handleUnban(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	const { id, token, scope, section } = payload ?? {};

	if (!isAuthorized(token, env)) {
		return jsonResponse({ error: "unauthorized" }, 401);
	}
	const idString = typeof id === "number" ? String(id) : id;
	if (!isValidAccountId(idString)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	if (scope !== "full" && scope !== "section" && scope !== "all") {
		return jsonResponse({ error: "invalid scope" }, 400);
	}
	if (scope === "section" && !ALLOWED_SECTIONS.has(section)) {
		return jsonResponse({ error: "invalid section" }, 400);
	}

	if (scope === "all") {
		await env.SUBS.delete(`ban:${idString}`);
		return jsonResponse({ ok: true });
	}

	const record = await readBanRecord(env, idString);
	if (scope === "full") {
		record.full = null;
	} else {
		delete record.sections[section];
	}
	await writeBanRecord(env, idString, record);

	return jsonResponse({ ok: true });
}

async function handleBannedList(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	if (!isAuthorized(payload?.token, env)) {
		return jsonResponse({ error: "unauthorized" }, 401);
	}

	const { keys } = await env.SUBS.list({ prefix: "ban:" });
	const users = [];
	for (const key of keys) {
		const idString = key.name.slice("ban:".length);
		const record = await readBanRecord(env, idString);
		users.push({ id: idString, full: record.full, sections: record.sections });
	}

	return jsonResponse({ users });
}

const KEY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I/L — hard to tell apart when read off a screen

function generateActivationKey() {
	const groups = [];
	for (let g = 0; g < 4; g++) {
		const randomBytes = new Uint8Array(4);
		crypto.getRandomValues(randomBytes);
		let group = "";
		for (let i = 0; i < 4; i++) {
			group += KEY_ALPHABET[randomBytes[i] % KEY_ALPHABET.length];
		}
		groups.push(group);
	}
	return groups.join("-");
}

async function handleGenerateKey(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	const { token, tier, durationHours } = payload ?? {};

	if (!isAuthorized(token, env)) {
		return jsonResponse({ error: "unauthorized" }, 401);
	}
	if (!ALLOWED_TIERS.has(tier)) {
		return jsonResponse({ error: "invalid tier" }, 400);
	}
	if (durationHours !== undefined && (typeof durationHours !== "number" || !(durationHours >= 0))) {
		return jsonResponse({ error: "invalid durationHours" }, 400);
	}

	let key = null;
	// Practically never collides (32^16 possibilities), but a fresh KV lookup is cheap enough
	// to just check rather than trust the math.
	for (let attempt = 0; attempt < 5 && !key; attempt++) {
		const candidate = generateActivationKey();
		const existing = await env.SUBS.get(`key:${candidate}`);
		if (!existing) {
			key = candidate;
		}
	}
	if (!key) {
		return jsonResponse({ error: "could not generate key" }, 500);
	}

	const hasDuration = typeof durationHours === "number" && durationHours > 0;
	await env.SUBS.put(`key:${key}`, hasDuration ? JSON.stringify({ tier, durationHours }) : tier);
	return jsonResponse({ ok: true, key, tier, durationHours: hasDuration ? durationHours : null });
}

async function handleRedeemKey(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	const { id, key } = payload ?? {};
	const idString = typeof id === "number" ? String(id) : id;
	if (!isValidAccountId(idString)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	if (typeof key !== "string" || key.trim().length === 0) {
		return jsonResponse({ error: "invalid key" }, 400);
	}

	const normalizedKey = key.trim().toUpperCase();
	const stored = await env.SUBS.get(`key:${normalizedKey}`);
	let tier = null;
	let durationHours = null;
	if (ALLOWED_TIERS.has(stored)) {
		tier = stored;
	} else if (stored) {
		try {
			const parsed = JSON.parse(stored);
			if (ALLOWED_TIERS.has(parsed.tier)) {
				tier = parsed.tier;
				durationHours = typeof parsed.durationHours === "number" ? parsed.durationHours : null;
			}
		} catch {
			// tier stays null, falls through to the 404 below
		}
	}
	if (!tier) {
		return jsonResponse({ error: "key not found or already used" }, 404);
	}

	// One-time: gone the moment it's redeemed, so a second attempt with the same string —
	// whether it's the same buyer trying again or someone else who saw it — fails the same
	// way an unknown key would.
	await env.SUBS.delete(`key:${normalizedKey}`);
	const expiresAt = await writeSubscription(env, idString, tier, durationHours);

	return jsonResponse({ ok: true, tier, expiresAt });
}

export default {
	async fetch(request, env) {
		const url = new URL(request.url);

		if (request.method === "GET" && url.pathname === "/status") {
			return handleStatus(request, env);
		}
		if (request.method === "GET" && url.pathname === "/ban-status") {
			return handleBanStatus(request, env);
		}
		if (request.method === "POST" && url.pathname === "/grant") {
			return handleGrant(request, env);
		}
		if (request.method === "POST" && url.pathname === "/ban") {
			return handleBan(request, env);
		}
		if (request.method === "POST" && url.pathname === "/unban") {
			return handleUnban(request, env);
		}
		if (request.method === "POST" && url.pathname === "/banned-list") {
			return handleBannedList(request, env);
		}
		if (request.method === "POST" && url.pathname === "/generate-key") {
			return handleGenerateKey(request, env);
		}
		if (request.method === "POST" && url.pathname === "/redeem-key") {
			return handleRedeemKey(request, env);
		}
		return jsonResponse({ error: "not found" }, 404);
	},
};
