/**
 * Shared KV logic for the subscription backend: tiers, activation keys, bans, subscriptions.
 * Used by the HTTP routes in index.js and by the Telegram bot in bot/. Moved here verbatim from
 * index.js (see the storage layout documented at the top of that file) so there is exactly one
 * implementation of "what a key is" and "what a ban is".
 */

export const ALLOWED_TIERS = new Set(["standard", "pro"]);
export const ALLOWED_SECTIONS = new Set(["gifts", "messages", "ghost"]);
// No 0/O/1/I/L — the whole point of a key is that a human reads it off a chat message and
// (occasionally) types it by hand, so ambiguous-looking characters aren't worth the entropy.
export const KEY_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

export function generateActivationKey() {
	const groups = [];
	for (let g = 0; g < 4; g++) {
		const random = new Uint8Array(5);
		crypto.getRandomValues(random);
		let group = "";
		for (let i = 0; i < 5; i++) {
			group += KEY_ALPHABET[random[i] % KEY_ALPHABET.length];
		}
		groups.push(group);
	}
	return `PMP-${groups.join("-")}`;
}

export function isValidAccountId(value) {
	return typeof value === "string" && /^-?\d{1,20}$/.test(value);
}

// Reads "sub:<id>", resolving the legacy bare-string form and the JSON
// { tier, expiresAt } form alike, and treating a past expiresAt as "standard, no expiry" —
// nothing needs to actively sweep an expired entry for correctness, `/status` already reports
// it right. `durationHours` may be fractional (an admin who mixes days and hours contributes a
// float number of hours); `expiresAt` is always the exact resulting millisecond, never rounded.
export async function readSubscription(env, idString) {
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
export async function writeSubscription(env, idString, tier, durationHours) {
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
	// Rounded to a whole millisecond: durationHours can be fractional, and the client signs
	// /status's response as a plain integer string — a fractional value here would make the
	// two sides' canonical strings disagree and every legitimate response fail verification.
	const expiresAt = Math.round(Date.now() + durationHours * 60 * 60 * 1000);
	await env.SUBS.put(`sub:${idString}`, JSON.stringify({ tier, expiresAt }));
	return expiresAt;
}

// A stored entry is either an old plain reason string or a {reason, at} object — see the
// storage doc at the top of this file. Reading always normalizes to the latter so every caller
// only ever deals with one shape; nothing ever rewrites an old row just for having read it.
export function normalizeBanEntry(value) {
	if (typeof value === "string") {
		return { reason: value, at: null };
	}
	if (value && typeof value === "object" && typeof value.reason === "string") {
		return { reason: value.reason, at: Number.isInteger(value.at) ? value.at : null };
	}
	return null;
}

export async function readBanRecord(env, idString) {
	const stored = await env.SUBS.get(`ban:${idString}`);
	if (!stored) {
		return { full: null, sections: {} };
	}
	try {
		const parsed = JSON.parse(stored);
		const full = normalizeBanEntry(parsed.full);
		const sections = {};
		if (parsed.sections && typeof parsed.sections === "object") {
			for (const [section, value] of Object.entries(parsed.sections)) {
				const entry = normalizeBanEntry(value);
				if (entry) {
					sections[section] = entry;
				}
			}
		}
		return { full, sections };
	} catch {
		return { full: null, sections: {} };
	}
}

export async function writeBanRecord(env, idString, record) {
	if (!record.full && Object.keys(record.sections).length === 0) {
		await env.SUBS.delete(`ban:${idString}`);
	} else {
		await env.SUBS.put(`ban:${idString}`, JSON.stringify(record));
	}
}

// KV's list() caps at 1000 keys per call — silently truncating a prefix scan would understate
// exactly the count /users-list exists to report, so every full-prefix scan in this file loops
// on the cursor instead of trusting a single call.
export async function listAllKeys(env, prefix) {
	const keys = [];
	let cursor;
	for (;;) {
		const page = await env.SUBS.list({ prefix, cursor });
		keys.push(...page.keys);
		if (page.list_complete) {
			return keys;
		}
		cursor = page.cursor;
	}
}

