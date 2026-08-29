/**
 * PampGram subscription backend.
 *
 * The only part of PampGram that isn't purely local: a subscription an admin grants has to
 * be visible on the *other* person's device, and there's no way to make that true without a
 * server both copies of the app can ask. Everything else this stores is one number per
 * Telegram account id — no messages, no chat content, nothing else ever passes through here.
 *
 * Storage: a single Workers KV namespace (binding SUBS), key = Telegram account id as a
 * string, value = "pro" | "standard".
 *
 * Routes:
 *   GET  /status?id=<telegram account id>
 *     -> { "tier": "standard" | "pro" }
 *     Public — every PampGram install calls this for its OWN account id to know whether to
 *     show PRO or STANDARD. No auth: the response never carries anything more sensitive than
 *     "this account is on tier X", and requiring auth here would mean embedding a *readable*
 *     secret in every copy of the app for zero benefit.
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
 */

const ALLOWED_TIERS = new Set(["standard", "pro"]);

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

export default {
	async fetch(request, env) {
		const url = new URL(request.url);

		if (request.method === "GET" && url.pathname === "/status") {
			return handleStatus(request, env);
		}
		if (request.method === "POST" && url.pathname === "/grant") {
			return handleGrant(request, env);
		}
		return jsonResponse({ error: "not found" }, 404);
	},
};
