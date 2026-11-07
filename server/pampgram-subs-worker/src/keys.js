/**
 * Activation keys: minting one and redeeming it for an account. Shared by the HTTP routes
 * (/generate-key, /redeem-key) and the bot (which mints a key per purchase and can redeem it
 * straight onto the buyer's own account). Same storage rules as documented in index.js:
 * a key is "key:<KEY>" -> tier | JSON { tier, durationHours }, and it is gone once redeemed.
 */

import { ALLOWED_TIERS, generateActivationKey, writeSubscription } from "./core.js";
import { updateUser } from "./users.js";

/** Mints a key for `tier`. Returns the key string, or null if no unused key could be found. */
export async function issueKey(env, tier, durationHours) {
	if (!ALLOWED_TIERS.has(tier)) {
		return null;
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
		return null;
	}
	const hasDuration = typeof durationHours === "number" && durationHours > 0;
	await env.SUBS.put(`key:${key}`, hasDuration ? JSON.stringify({ tier, durationHours }) : tier);
	return key;
}

/**
 * Redeems `key` for the account `idString`. Returns { ok: true, tier, expiresAt } or
 * { ok: false } for an unknown or already used key.
 */
export async function redeemKeyForAccount(env, idString, key) {
	const normalizedKey = String(key).trim().toUpperCase();
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
			// tier stays null, falls through to the failure below
		}
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
