/**
 * Activation keys: minting one and redeeming it for an account. Shared by the HTTP routes
 * (/generate-key, /redeem-key) and the bot (which mints a key per purchase and can redeem it
 * straight onto the buyer's own account). Same storage rules as documented in index.js:
 * a key is "key:<KEY>" -> tier | JSON { tier, durationHours }, and it is gone once redeemed.
 */

import { ALLOWED_TIERS, generateActivationKey, readBanRecord, writeSubscription } from "./core.js";
import { recordTamper, clearTamper } from "./access.js";
import { updateUser } from "./users.js";

async function mintUnusedKey(env) {
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
	return key;
}

/** Mints a key for `tier`. Returns the key string, or null if no unused key could be found. */
export async function issueKey(env, tier, durationHours) {
	if (!ALLOWED_TIERS.has(tier)) {
		return null;
	}
	const key = await mintUnusedKey(env);
	if (!key) {
		return null;
	}
	const hasDuration = typeof durationHours === "number" && durationHours > 0;
	await env.SUBS.put(`key:${key}`, hasDuration ? JSON.stringify({ tier, durationHours }) : tier);
	return key;
}

/**
 * One-shot unban key. Redeeming it is the only self-serve way out of a full ban (admins can
 * still clear bans from /unban / the users list). Stored as JSON { kind: "unban" }.
 */
export async function issueUnbanKey(env) {
	const key = await mintUnusedKey(env);
	if (!key) {
		return null;
	}
	await env.SUBS.put(`key:${key}`, JSON.stringify({ kind: "unban" }));
	return key;
}

/**
 * Redeems `key` for the account `idString`. Returns
 *   { ok: true, tier, expiresAt } for a normal licence key,
 *   { ok: true, unbanned: true, tier } for an unban key (clears the ban; tier is whatever
 *     subscription remains after the ban),
 *   { ok: false } for unknown/used keys,
 *   { ok: false, banned: true } when a fully banned account tries a normal (non-unban) key —
 *     the key is left untouched and the attempt counts as tamper (see access.js).
 */
export async function redeemKeyForAccount(env, idString, key) {
	const normalizedKey = String(key).trim().toUpperCase();
	const stored = await env.SUBS.get(`key:${normalizedKey}`);

	let isUnbanKey = false;
	let tier = null;
	let durationHours = null;
	if (ALLOWED_TIERS.has(stored)) {
		tier = stored;
	} else if (stored) {
		try {
			const parsed = JSON.parse(stored);
			if (parsed.kind === "unban") {
				isUnbanKey = true;
			} else if (ALLOWED_TIERS.has(parsed.tier)) {
				tier = parsed.tier;
				durationHours = typeof parsed.durationHours === "number" ? parsed.durationHours : null;
			}
		} catch {
			// falls through
		}
	}

	if (isUnbanKey) {
		// Consumed even if the account wasn't banned — still one-shot, so a leaked key dies.
		await env.SUBS.delete(`key:${normalizedKey}`);
		await env.SUBS.delete(`ban:${idString}`);
		await clearTamper(env, idString);
		const license = await env.SUBS.get(`sub:${idString}`);
		let remainingTier = "standard";
		if (license === "pro") {
			remainingTier = "pro";
		} else if (license) {
			try {
				const parsed = JSON.parse(license);
				if (parsed.tier === "pro") {
					remainingTier = "pro";
				}
			} catch {
				remainingTier = "standard";
			}
		}
		return { ok: true, unbanned: true, tier: remainingTier, expiresAt: null };
	}

	const ban = await readBanRecord(env, idString);
	if (ban.full) {
		await recordTamper(env, idString, "redeem_while_banned");
		return { ok: false, banned: true };
	}
	if (!tier) {
		return { ok: false };
	}

	// One-time: gone the moment it's redeemed, so a second attempt with the same string —
	// whether it's the same buyer trying again or someone else who saw it — fails the same
	// way an unknown key would.
	await env.SUBS.delete(`key:${normalizedKey}`);
	const now = Date.now();
	if (tier === "pro") {
		await env.SUBS.put(`tier_changed:${idString}`, String(now));
	}
	const expiresAt = await writeSubscription(env, idString, tier, durationHours);
	await updateUser(env, idString, (user) => {
		user.tier = tier;
		user.tierChangedAt = now;
		user.activatedAt = user.activatedAt ?? now;
	}, now);
	return { ok: true, tier, expiresAt };
}
