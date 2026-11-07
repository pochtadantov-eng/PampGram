/**
 * User profiles: everything the admin sees about one Telegram account.
 *
 *   key "u:<id>" -> JSON profile, with a short summary in the KV *metadata* of the same key so
 *   a list() call returns "who, which version, when last seen" for every user without reading
 *   each profile (KV list() returns metadata for free; metadata must stay under 1 KB).
 *
 * Two sources feed a profile, and they share the Telegram account id:
 *   - the app, through /status (version, build, own username/name, last seen, sessions);
 *   - the bot, through any update (username/name as Telegram reports them, whether the user
 *     ever started the bot, purchases).
 * What the app reports about itself is unauthenticated (the route is public by design, see
 * index.js), so version/username from the app are informational, never a basis for access.
 */

import { readSubscription, listAllKeys } from "./core.js";

// A new "visit" starts when the app is seen after being quiet this long.
export const SESSION_GAP_MS = 30 * 60 * 1000;
const MAX_SESSIONS = 40;

export function newUser(id, now) {
	return {
		id: String(id),
		firstSeen: now,
		lastSeen: 0,
		sessions: [],
		username: "",
		name: "",
		appVersion: "",
		appBuild: "",
		bot: null,
		activatedAt: null,
		purchases: 0,
		note: "",
	};
}

export async function getUser(env, id) {
	const raw = await env.SUBS.get(`u:${id}`);
	if (!raw) {
		return null;
	}
	try {
		return { ...newUser(id, Date.now()), ...JSON.parse(raw) };
	} catch {
		return null;
	}
}

function clip(value, length) {
	return typeof value === "string" ? value.slice(0, length) : "";
}

export function summaryOf(user) {
	return {
		ls: user.lastSeen || 0,
		v: clip(user.appVersion, 16),
		un: clip(user.username, 40).toLowerCase(),
		nm: clip(user.name, 40),
		t: user.tier === "pro" ? "pro" : "standard",
		b: user.bot ? 1 : 0,
		a: user.activatedAt ? 1 : 0,
	};
}

export async function saveUser(env, user) {
	await env.SUBS.put(`u:${user.id}`, JSON.stringify(user), { metadata: summaryOf(user) });
}

export async function updateUser(env, id, mutate, now = Date.now()) {
	const user = (await getUser(env, id)) ?? newUser(id, now);
	mutate(user);
	await saveUser(env, user);
	return user;
}

function cleanText(value, length) {
	if (typeof value !== "string") {
		return "";
	}
	// Control characters never belong in a name; the rest is escaped at render time.
	return value.replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, length);
}

/**
 * Called on every /status. `info` is whatever the app chose to send: { version, build,
 * username, name }, each optional.
 */
export async function recordAppSeen(env, id, info, now = Date.now()) {
	return updateUser(
		env,
		id,
		(user) => {
			const previous = user.lastSeen || 0;
			if (previous === 0 || now - previous > SESSION_GAP_MS) {
				user.sessions = [...(user.sessions ?? []), now].slice(-MAX_SESSIONS);
			}
			user.lastSeen = now;
			const version = cleanText(info?.version, 16);
			if (version) {
				user.appVersion = version;
			}
			const build = cleanText(info?.build, 16);
			if (build) {
				user.appBuild = build;
			}
			const username = cleanText(info?.username, 40).replace(/^@/, "");
			if (username) {
				user.username = username;
			}
			const name = cleanText(info?.name, 80);
			if (name) {
				user.name = name;
			}
		},
		now
	);
}

/** Called for every bot update that has a sender. */
export async function recordBotSeen(env, from, now = Date.now()) {
	const id = String(from.id);
	return updateUser(
		env,
		id,
		(user) => {
			user.bot = { ...(user.bot ?? { startedAt: now }), lastAt: now, blocked: false, lang: cleanText(from.language_code, 8) };
			const username = cleanText(from.username, 40);
			if (username) {
				user.username = username;
			}
			const name = cleanText([from.first_name, from.last_name].filter(Boolean).join(" "), 80);
			if (name) {
				user.name = name;
			}
		},
		now
	);
}

export async function noteTier(env, id, tier, now = Date.now()) {
	await updateUser(env, id, (user) => {
		user.tier = tier === "pro" ? "pro" : "standard";
		user.tierChangedAt = now;
	}, now);
}

export function displayName(user) {
	const handle = user.username ? `@${user.username}` : "";
	return [handle, user.name].filter(Boolean).join(" · ") || `id ${user.id}`;
}

/** Every known user as { id, ...summary }, newest activity first. Reads no profile bodies. */
export async function listUserSummaries(env) {
	const keys = await listAllKeys(env, "u:");
	const users = keys.map((key) => ({ id: key.name.slice(2), ...(key.metadata ?? {}) }));
	users.sort((a, b) => (b.ls || 0) - (a.ls || 0));
	return users;
}

/**
 * Users the app has seen before profiles existed (only "seen:<id>" keys) get a profile on first
 * need. Safe to run repeatedly.
 */
export async function importLegacyUsers(env) {
	const [seenKeys, subKeys] = await Promise.all([listAllKeys(env, "seen:"), listAllKeys(env, "sub:")]);
	const existing = new Set((await listAllKeys(env, "u:")).map((key) => key.name.slice(2)));
	let imported = 0;
	const ids = new Set([...seenKeys.map((k) => k.name.slice(5)), ...subKeys.map((k) => k.name.slice(4))]);
	for (const id of ids) {
		if (existing.has(id)) {
			continue;
		}
		const lastSeen = parseInt(await env.SUBS.get(`seen:${id}`), 10);
		const subscription = await readSubscription(env, id);
		const user = newUser(id, Number.isInteger(lastSeen) ? lastSeen : Date.now());
		user.lastSeen = Number.isInteger(lastSeen) ? lastSeen : 0;
		user.tier = subscription.tier;
		if (user.lastSeen) {
			user.sessions = [user.lastSeen];
		}
		await saveUser(env, user);
		imported++;
	}
	return imported;
}
