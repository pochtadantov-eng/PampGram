/**
 * PampGram subscription backend.
 *
 * The only part of PampGram that isn't purely local: a subscription an admin grants has to
 * be visible on the *other* person's device, and there's no way to make that true without a
 * server both copies of the app can ask. Everything else this stores is one number per
 * Telegram account id — no messages, no chat content, nothing else ever passes through here.
 *
 * Storage: a single Workers KV namespace (binding SUBS).
 *   key "sub:<id>"  -> "pro" | "standard"
 *   key "ban:<id>"  -> JSON { "full": "<reason>"|null, "sections": { "<section>": "<reason>" } }
 * Same posture throughout: a key that would only ever store the "nothing going on" value is
 * deleted instead of written, so the store only ever holds actual overrides.
 *
 * Routes:
 *   GET  /status?id=<telegram account id>
 *     -> { "tier": "standard" | "pro" }
 *     Public — every PampGram install calls this for its OWN account id to know whether to
 *     show PRO or STANDARD. No auth: the response never carries anything more sensitive than
 *     "this account is on tier X", and requiring auth here would mean embedding a *readable*
 *     secret in every copy of the app for zero benefit.
 *
 *   GET  /ban-status?id=<telegram account id>
 *     -> { "full": "<reason>"|null, "sections": { "<section>": "<reason>" } }
 *     Public, same reasoning as /status — every install checks its own ban state before
 *     opening the hub or a section.
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
 *   POST /banned-list
 *     body: { "token": "<ADMIN_TOKEN>" }
 *     -> { "users": [{ "id": "<id>", "full": "<reason>"|null, "sections": {...} }, ...] }
 *     Admin-only — backs the admin panel's "Разбанить" screen. Token goes in the body rather
 *     than a query string, same reasoning as /grant: never put the secret somewhere that ends
 *     up in a server log line.
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

async function handleStatus(request, env) {
	const url = new URL(request.url);
	const id = url.searchParams.get("id");
	if (!isValidAccountId(id)) {
		return jsonResponse({ error: "invalid id" }, 400);
	}
	const stored = await env.SUBS.get(`sub:${id}`);
	const tier = ALLOWED_TIERS.has(stored) ? stored : "standard";
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

	return jsonResponse({ ok: true });
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
		return jsonResponse({ error: "not found" }, 404);
	},
};
