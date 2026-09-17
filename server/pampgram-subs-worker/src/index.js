/**
 * PampGram subscription backend.
 *
 * The only part of PampGram that isn't purely local: a subscription an admin grants has to
 * be visible on the *other* person's device, and there's no way to make that true without a
 * server both copies of the app can ask. Everything else this stores is one number per
 * Telegram account id — no messages, no chat content, nothing else ever passes through here.
 *
 * Storage: a single Workers KV namespace (binding SUBS).
 *   key "sub:<id>"          -> "pro" | "standard"
 *   key "tier_changed:<id>" -> "<ms of the most recent /grant or pro-key /keys/redeem for this
 *                             account>" — written every time /grant runs, even when it sets
 *                             "standard" (that's still a real change worth dating), and every
 *                             time a pro key is redeemed.
 *   key "ban:<id>"          -> JSON { "full": {"reason":"<text>","at":<ms>}|null,
 *                             "sections": { "<section>": {"reason":"<text>","at":<ms>} } }.
 *                             An older record can still hold a plain string instead of an
 *                             {reason,at} object for "full"/a section — every reader normalizes
 *                             that to {reason, at: null} on the way in, so nothing ever has to
 *                             backfill the old rows.
 *   key "min_version"       -> "<integer>" (single global value, not per-account)
 *   key "key:<KEY>"         -> JSON { "tier": "standard"|"pro", "usedBy": "<id>"|null, "usedAt": <ms>|null, "createdAt": <ms> }
 *   key "licensed:<id>"     -> "1" (present at all means licensed — same "absent means the
 *                             nothing-going-on default" posture as the other keys)
 *   key "seen:<id>"         -> "<ms of the most recent /status call from this account>" — the
 *                             only key that's an actual log rather than an override: written
 *                             every time (there's no "nothing going on" value for "have they
 *                             ever opened the app" to fall back to), so /users-list can answer
 *                             "how many accounts exist at all", not just "how many are
 *                             non-default".
 * Every other key follows the same posture: a key that would only ever store the "nothing going
 * on" value is deleted instead of written, so the store only ever holds actual overrides.
 *
 * Activation keys exist because a *file* sale (send the .ipa/mod once, no further contact) has
 * no way to stop the buyer forwarding that same file to someone else for free — unlike `/grant`,
 * which the admin re-runs by hand per buyer and so never actually needed a key. A key minted by
 * `/keys/generate` is good for exactly one `/keys/redeem` (first Telegram account id to submit
 * it wins); every PampGram install refuses to do anything beyond showing the "enter your key"
 * screen until its own account redeems one, so a copy of the file without a key redeemed for
 * *that specific account* stays inert no matter how many people end up with it.
 *
 * Routes:
 *   GET  /status?id=<telegram account id>
 *     -> { "tier": "standard" | "pro" }
 *     Public — every PampGram install calls this for its OWN account id to know whether to
 *     show PRO or STANDARD. No auth: the response never carries anything more sensitive than
 *     "this account is on tier X", and requiring auth here would mean embedding a *readable*
 *     secret in every copy of the app for zero benefit. Also records "seen:<id>" (fire-and-
 *     forget via ctx.waitUntil, never delays or can fail this response) — this is the one call
 *     every install makes on every open, so it's the natural place to count "how many accounts
 *     actually use this" without adding a dedicated ping route.
 *
 *   GET  /ban-status?id=<telegram account id>
 *     -> { "full": "<reason>"|null, "sections": { "<section>": "<reason>" } }
 *     Public, same reasoning as /status — every install checks its own ban state before
 *     opening the hub or a section. Deliberately still plain reason strings, not the
 *     {reason,at} shape "ban:<id>" is actually stored as — every install's ban-enforcement
 *     code depends on this exact shape, so /users-list (the only place "at" is exposed) reads
 *     the richer stored form itself instead of this route changing underneath every install.
 *
 *   GET  /min-version
 *     -> { "minVersion": <integer> }
 *     Public, same reasoning as /status. Every install compares this against its own
 *     hardcoded build number (`PampGramSubscriptionAPI.currentBuildVersion`) before opening
 *     PampGram; a build below this number shows "update required" instead of the real
 *     content. Absent key reads as 0, meaning "no minimum set" — every build passes.
 *
 *   POST /set-min-version
 *     body: { "minVersion": <integer>, "token": "<ADMIN_TOKEN>" }
 *     -> { "ok": true }
 *     Admin-only, same token as /grant. Raising this past an already-shipped build's number
 *     is what actually retires that build — existing installs of it start showing "update
 *     required" the next time they check, with no client-side change needed on their end.
 *
 *   POST /grant
 *     body: { "id": <telegram account id>, "tier": "pro" | "standard", "token": "<ADMIN_TOKEN>" }
 *     -> { "ok": true }
 *     Sets the tier for that account. Requires token to match the ADMIN_TOKEN secret — set
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
 *   GET  /license-status?id=<telegram account id>
 *     -> { "licensed": true|false }
 *     Public, same posture as /status — every install checks its own account on opening the
 *     PampGram tab (and after a reinstall, since that wipes the local on-device copy of this
 *     flag) to know whether to show the hub or the "enter your key" screen.
 *
 *   POST /keys/generate
 *     body: { "token": "<ADMIN_TOKEN>", "tier": "standard" | "pro" (optional, default "standard") }
 *     -> { "key": "PMP-XXXXX-XXXXX-XXXXX-XXXXX", "tier": "standard" | "pro" }
 *     Admin-only. Mints one new, unused key and returns it — the admin copies it out and sends
 *     it to whoever just bought the mod. Never returns an already-issued key twice.
 *
 *   POST /keys/redeem
 *     body: { "key": "<key>", "id": <telegram account id> }
 *     -> { "ok": true, "tier": "standard" | "pro" } | { "error": "invalid key" | "already used" }
 *     Public — called by the buyer's own app, not the admin. First account id to redeem a given
 *     key wins it permanently (`key:<KEY>.usedBy`); every later attempt with the same key, from
 *     any other account, is rejected with "already used". Redeeming again from the *same*
 *     account that already holds the key is a harmless no-op success (covers a retried request
 *     after a dropped response) rather than an error. Sets "licensed:<id>" so /license-status
 *     reports true from then on, and additionally grants the "sub:<id>" tier if the key was
 *     minted as "pro".
 *
 *   POST /users-list
 *     body: { "token": "<ADMIN_TOKEN>" }
 *     -> { "users": [{
 *            "id": "<id>", "tier": "standard"|"pro", "tierChangedAt": <ms>|null, "lastSeen": <ms>,
 *            "full": {"reason":"<text>","at":<ms>}|null,
 *            "sections": { "<section>": {"reason":"<text>","at":<ms>} }
 *          }, ...], "total": <count> }
 *     Admin-only — backs the admin panel's "Пользователи" screen (which replaced the old,
 *     separate "Разбанить" screen and its now-removed /banned-list route: one merged list of
 *     every account PampGram knows about, banned or not, with tier and ban detail together).
 *     The account set is every id with a "seen:<id>" OR a "ban:<id>" entry — union, not just
 *     "seen:", so an account banned before it ever opened the app (or one that's never called
 *     /status for any other reason) still shows up instead of silently vanishing from this
 *     list; such an account reports `lastSeen: 0`. `total` is just `users.length`, sent
 *     separately so the client can show a count without counting the array itself.
 */

const ALLOWED_TIERS = new Set(["standard", "pro"]);
const ALLOWED_SECTIONS = new Set(["gifts", "messages", "ghost"]);
// No 0/O/1/I/L — the whole point of a key is that a human reads it off a chat message and
// (occasionally) types it by hand, so ambiguous-looking characters aren't worth the entropy.
const KEY_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

function generateActivationKey() {
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

function jsonResponse(body, status = 200) {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "content-type": "application/json; charset=utf-8" },
	});
}

function isValidAccountId(value) {
	return typeof value === "string" && /^-?\d{1,20}$/.test(value);
}

async function handleStatus(request, env, ctx) {
	const url = new URL(request.url);
	const id = url.searchParams.get("id");
	if (!isValidAccountId(id)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	const stored = await env.SUBS.get(`sub:${id}`);
	const tier = ALLOWED_TIERS.has(stored) ? stored : "standard";
	// Fire-and-forget: never awaited, so a KV write here can't slow down or fail this response.
	ctx.waitUntil(env.SUBS.put(`seen:${id}`, String(Date.now())));
	return jsonResponse({ tier });
}

async function handleGrant(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	const { id, tier, token } = payload ?? {};

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

	if (tier === "standard") {
		// Standard is the default for anything not in KV — deleting keeps the store from
		// growing with entries that carry no information beyond "not overridden".
		await env.SUBS.delete(`sub:${idString}`);
	} else {
		await env.SUBS.put(`sub:${idString}`, tier);
	}
	// Every /grant is a real change worth dating, even one that sets "standard".
	await env.SUBS.put(`tier_changed:${idString}`, String(Date.now()));

	return jsonResponse({ ok: true });
}

function isAuthorized(token, env) {
	return typeof token === "string" && token.length > 0 && token === env.ADMIN_TOKEN;
}

// A stored entry is either an old plain reason string or a {reason, at} object — see the
// storage doc at the top of this file. Reading always normalizes to the latter so every caller
// only ever deals with one shape; nothing ever rewrites an old row just for having read it.
function normalizeBanEntry(value) {
	if (typeof value === "string") {
		return { reason: value, at: null };
	}
	if (value && typeof value === "object" && typeof value.reason === "string") {
		return { reason: value.reason, at: Number.isInteger(value.at) ? value.at : null };
	}
	return null;
}

async function readBanRecord(env, idString) {
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
	const record = await readBanRecord(env, id);
	// Plain reason strings only — see this route's own doc for why it never exposes "at".
	return jsonResponse({
		full: record.full ? record.full.reason : null,
		sections: Object.fromEntries(Object.entries(record.sections).map(([section, entry]) => [section, entry.reason])),
	});
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
	const entry = { reason: reason.trim(), at: Date.now() };
	if (scope === "full") {
		record.full = entry;
	} else {
		record.sections[section] = entry;
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

async function handleMinVersion(request, env) {
	const stored = await env.SUBS.get("min_version");
	const parsed = stored === null ? 0 : parseInt(stored, 10);
	const minVersion = Number.isInteger(parsed) && parsed >= 0 ? parsed : 0;
	return jsonResponse({ minVersion });
}

async function handleSetMinVersion(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	const { minVersion, token } = payload ?? {};

	if (!isAuthorized(token, env)) {
		return jsonResponse({ error: "unauthorized" }, 401);
	}
	if (!Number.isInteger(minVersion) || minVersion < 0) {
		return jsonResponse({ error: "invalid minVersion" }, 400);
	}

	if (minVersion === 0) {
		await env.SUBS.delete("min_version");
	} else {
		await env.SUBS.put("min_version", String(minVersion));
	}

	return jsonResponse({ ok: true });
}

// KV's list() caps at 1000 keys per call — silently truncating a prefix scan would understate
// exactly the count /users-list exists to report, so every full-prefix scan in this file loops
// on the cursor instead of trusting a single call.
async function listAllKeys(env, prefix) {
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

async function handleUsersList(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	if (!isAuthorized(payload?.token, env)) {
		return jsonResponse({ error: "unauthorized" }, 401);
	}

	// Union of "seen:" and "ban:" ids: an account banned before it ever opened the app (or
	// that never calls /status for any other reason) has no "seen:" entry, but still belongs
	// on this list rather than silently disappearing from admin view.
	const [seenKeys, banKeys] = await Promise.all([listAllKeys(env, "seen:"), listAllKeys(env, "ban:")]);
	const ids = new Set();
	for (const key of seenKeys) {
		ids.add(key.name.slice("seen:".length));
	}
	for (const key of banKeys) {
		ids.add(key.name.slice("ban:".length));
	}

	const users = await Promise.all(
		Array.from(ids).map(async (idString) => {
			const [lastSeenRaw, tierRaw, tierChangedRaw, banRecord] = await Promise.all([
				env.SUBS.get(`seen:${idString}`),
				env.SUBS.get(`sub:${idString}`),
				env.SUBS.get(`tier_changed:${idString}`),
				readBanRecord(env, idString),
			]);
			const lastSeen = parseInt(lastSeenRaw, 10);
			const tierChangedAt = parseInt(tierChangedRaw, 10);
			return {
				id: idString,
				tier: ALLOWED_TIERS.has(tierRaw) ? tierRaw : "standard",
				tierChangedAt: Number.isInteger(tierChangedAt) ? tierChangedAt : null,
				lastSeen: Number.isInteger(lastSeen) ? lastSeen : 0,
				full: banRecord.full,
				sections: banRecord.sections,
			};
		})
	);
	users.sort((a, b) => b.lastSeen - a.lastSeen);

	return jsonResponse({ users, total: users.length });
}

async function handleLicenseStatus(request, env) {
	const url = new URL(request.url);
	const id = url.searchParams.get("id");
	if (!isValidAccountId(id)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	const stored = await env.SUBS.get(`licensed:${id}`);
	return jsonResponse({ licensed: stored === "1" });
}

async function handleGenerateKey(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	const { token, tier } = payload ?? {};
	if (!isAuthorized(token, env)) {
		return jsonResponse({ error: "unauthorized" }, 401);
	}
	const keyTier = tier === "pro" ? "pro" : "standard";

	// Collision odds are negligible (33^20 keyspace) — checked anyway, since a generated key
	// is only useful if nothing else could already be holding it.
	let key = null;
	for (let attempt = 0; attempt < 5 && key === null; attempt++) {
		const candidate = generateActivationKey();
		const existing = await env.SUBS.get(`key:${candidate}`);
		if (!existing) {
			key = candidate;
		}
	}
	if (key === null) {
		return jsonResponse({ error: "failed to generate a unique key" }, 500);
	}

	await env.SUBS.put(`key:${key}`, JSON.stringify({ tier: keyTier, usedBy: null, usedAt: null, createdAt: Date.now() }));
	return jsonResponse({ key, tier: keyTier });
}

async function handleRedeemKey(request, env) {
	let payload;
	try {
		payload = await request.json();
	} catch {
		return jsonResponse({ error: "invalid json" }, 400);
	}

	const { key, id } = payload ?? {};
	const idString = typeof id === "number" ? String(id) : id;
	if (!isValidAccountId(idString)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	if (typeof key !== "string" || key.trim().length === 0) {
		return jsonResponse({ error: "invalid key" }, 400);
	}
	const normalizedKey = key.trim().toUpperCase();

	const stored = await env.SUBS.get(`key:${normalizedKey}`);
	if (!stored) {
		return jsonResponse({ error: "invalid key" }, 404);
	}
	let record;
	try {
		record = JSON.parse(stored);
	} catch {
		return jsonResponse({ error: "invalid key" }, 404);
	}

	if (record.usedBy) {
		if (record.usedBy === idString) {
			// Retrying a request that already succeeded (e.g. a dropped response) — confirm
			// rather than error, and make sure the license flag actually got set.
			await env.SUBS.put(`licensed:${idString}`, "1");
			return jsonResponse({ ok: true, tier: record.tier });
		}
		return jsonResponse({ error: "already used" }, 409);
	}

	record.usedBy = idString;
	record.usedAt = Date.now();
	await env.SUBS.put(`key:${normalizedKey}`, JSON.stringify(record));
	await env.SUBS.put(`licensed:${idString}`, "1");
	if (record.tier === "pro") {
		await env.SUBS.put(`sub:${idString}`, "pro");
		await env.SUBS.put(`tier_changed:${idString}`, String(Date.now()));
	}

	return jsonResponse({ ok: true, tier: record.tier });
}

export default {
	async fetch(request, env, ctx) {
		const url = new URL(request.url);

		if (request.method === "GET" && url.pathname === "/status") {
			return handleStatus(request, env, ctx);
		}
		if (request.method === "GET" && url.pathname === "/ban-status") {
			return handleBanStatus(request, env);
		}
		if (request.method === "GET" && url.pathname === "/min-version") {
			return handleMinVersion(request, env);
		}
		if (request.method === "POST" && url.pathname === "/set-min-version") {
			return handleSetMinVersion(request, env);
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
		if (request.method === "GET" && url.pathname === "/license-status") {
			return handleLicenseStatus(request, env);
		}
		if (request.method === "POST" && url.pathname === "/keys/generate") {
			return handleGenerateKey(request, env);
		}
		if (request.method === "POST" && url.pathname === "/keys/redeem") {
			return handleRedeemKey(request, env);
		}
		if (request.method === "POST" && url.pathname === "/users-list") {
			return handleUsersList(request, env);
		}
		return jsonResponse({ error: "not found" }, 404);
	},
};
