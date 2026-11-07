import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import { accessMessage } from "../src/access.js";
import { createEnv, createCtx } from "./helpers.js";

const NONCE = "abcdef0123456789abcdef";

async function makeKeys() {
	const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
	const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
	let binary = "";
	for (const byte of pkcs8) {
		binary += String.fromCharCode(byte);
	}
	return { publicKey: pair.publicKey, privateB64: btoa(binary) };
}

async function setup() {
	const keys = await makeKeys();
	const env = createEnv({ ACCESS_SIGNING_KEY: keys.privateB64, BOT_TOKEN: undefined });
	return { env, keys };
}

async function call(env, method, path, body) {
	const ctx = createCtx();
	const request = new Request(`https://example.test${path}`, {
		method,
		headers: { "content-type": "application/json" },
		body: body === undefined ? undefined : JSON.stringify(body),
	});
	const response = await worker.fetch(request, env, ctx);
	await ctx.settle();
	return { status: response.status, json: await response.json() };
}

async function verified(keys, id, json, nonce = NONCE) {
	const message = accessMessage({ id, state: json.state, expiresAt: json.expiresAt, now: json.now, ttl: json.ttl, nonce });
	const sig = Uint8Array.from(atob(json.sig), (c) => c.charCodeAt(0));
	return crypto.subtle.verify({ name: "Ed25519" }, keys.publicKey, sig, new TextEncoder().encode(message));
}

test("/access: a fresh account is locked ('none'), signed with the private key, nonce echoed", async () => {
	const { env, keys } = await setup();
	const { status, json } = await call(env, "GET", `/access?id=42&nonce=${NONCE}`);
	assert.equal(status, 200);
	assert.equal(json.state, "none");
	assert.equal(json.ttl, 0);
	assert.equal(json.nonce, NONCE);
	assert.ok(await verified(keys, "42", json));
	assert.ok(await env.SUBS.get("seen:42"));
});

test("/access: a signature for one nonce does not verify for another (no replay)", async () => {
	const { env, keys } = await setup();
	const { json } = await call(env, "GET", `/access?id=42&nonce=${NONCE}`);
	assert.equal(await verified(keys, "42", json, "ffffffffffffffffffffff"), false);
	assert.equal(await verified(keys, "43", json), false, "and not for another account");
});

test("/access: refuses without a nonce, with a bad id, and when signing isn't configured", async () => {
	const { env } = await setup();
	assert.equal((await call(env, "GET", "/access?id=42")).status, 400);
	assert.equal((await call(env, "GET", `/access?id=abc&nonce=${NONCE}`)).status, 400);
	assert.equal((await call(env, "GET", "/access?id=42&nonce=short")).status, 400);
	const unsigned = createEnv({ BOT_TOKEN: undefined });
	assert.equal((await call(unsigned, "GET", `/access?id=42&nonce=${NONCE}`)).status, 503);
});

test("/access: a key activates the account; a pro key with duration expires into 'expired'", async () => {
	const { env, keys } = await setup();
	const minted = await call(env, "POST", "/generate-key", { tier: "pro", durationHours: 24 * 30, token: "admin-token" });
	assert.equal(minted.status, 200);
	const redeemed = await call(env, "POST", "/redeem-key", { id: 42, key: minted.json.key });
	assert.equal(redeemed.status, 200);

	let { json } = await call(env, "GET", `/access?id=42&nonce=${NONCE}`);
	assert.equal(json.state, "active");
	assert.ok(json.expiresAt > Date.now());
	assert.ok(json.ttl > 0 && json.ttl <= 48 * 60 * 60 * 1000);
	assert.ok(await verified(keys, "42", json));

	// A month later: stored expiry in the past.
	await env.SUBS.put("sub:42", JSON.stringify({ tier: "pro", expiresAt: Date.now() - 1000 }));
	({ json } = await call(env, "GET", `/access?id=42&nonce=${NONCE}`));
	assert.equal(json.state, "expired");
	assert.equal(json.ttl, 0);
});

test("/access: a permanent pro grant is active; a standard grant is not a licence", async () => {
	const { env } = await setup();
	await call(env, "POST", "/grant", { id: 7, tier: "pro", token: "admin-token" });
	assert.equal((await call(env, "GET", `/access?id=7&nonce=${NONCE}`)).json.state, "active");
	await call(env, "POST", "/grant", { id: 8, tier: "standard", token: "admin-token" });
	assert.equal((await call(env, "GET", `/access?id=8&nonce=${NONCE}`)).json.state, "none");
});

test("/access: a full ban beats an active subscription and carries the reason", async () => {
	const { env } = await setup();
	await call(env, "POST", "/grant", { id: 7, tier: "pro", token: "admin-token" });
	await call(env, "POST", "/ban", { id: 7, scope: "full", reason: "нарушение правил", token: "admin-token" });
	const { json } = await call(env, "GET", `/access?id=7&nonce=${NONCE}`);
	assert.equal(json.state, "banned");
	assert.equal(json.reason, "нарушение правил");
	assert.equal(json.ttl, 0);
	// Section bans alone don't lock the app.
	await call(env, "POST", "/unban", { id: 7, scope: "all", token: "admin-token" });
	await call(env, "POST", "/ban", { id: 7, scope: "section", section: "ghost", reason: "x", token: "admin-token" });
	assert.equal((await call(env, "GET", `/access?id=7&nonce=${NONCE}`)).json.state, "active");
});

test("a banned account cannot redeem a key: the key survives and the attempt is tamper", async () => {
	const { env } = await setup();
	await call(env, "POST", "/ban", { id: 9, scope: "full", reason: "r", token: "admin-token" });
	const minted = await call(env, "POST", "/generate-key", { tier: "pro", durationHours: 24, token: "admin-token" });
	const attempt = await call(env, "POST", "/redeem-key", { id: 9, key: minted.json.key });
	assert.equal(attempt.status, 403);
	assert.ok(await env.SUBS.get(`key:${minted.json.key}`), "key is not consumed");
	assert.equal(JSON.parse(await env.SUBS.get("tamper:9")).kinds[0], "redeem_while_banned");
	assert.equal((await call(env, "GET", `/access?id=9&nonce=${NONCE}`)).json.state, "banned");
	// Still usable by someone else.
	assert.equal((await call(env, "POST", "/redeem-key", { id: 10, key: minted.json.key })).status, 200);
});

test("/report-tamper on a banned account wipes subscription and ledger, flags it, survives key attempts", async () => {
	const { env } = await setup();
	await call(env, "POST", "/grant", { id: 11, tier: "pro", token: "admin-token" });
	await env.SUBS.put("ledgersync:11", "{\"stars\":999}");
	await env.SUBS.put("gifttransfer:11:a", "blob");
	await call(env, "POST", "/ban", { id: 11, scope: "full", reason: "r", token: "admin-token" });

	const report = await call(env, "POST", "/report-tamper", { id: 11, kind: "balance_edit" });
	assert.equal(report.json.escalated, true);
	assert.equal(await env.SUBS.get("sub:11"), null);
	assert.equal(await env.SUBS.get("ledgersync:11"), null);
	assert.equal(await env.SUBS.get("gifttransfer:11:a"), null);
	const access = await call(env, "GET", `/access?id=11&nonce=${NONCE}`);
	assert.equal(access.json.state, "banned");
	assert.equal(access.json.tamper, true);

	// Unbanning is the admin's explicit decision and clears the flag.
	await call(env, "POST", "/unban", { id: 11, scope: "all", token: "admin-token" });
	assert.equal(await env.SUBS.get("tamper:11"), null);
});

test("/report-tamper can't get a non-banned account banned (public route)", async () => {
	const { env } = await setup();
	await call(env, "POST", "/grant", { id: 12, tier: "pro", token: "admin-token" });
	const report = await call(env, "POST", "/report-tamper", { id: 12, kind: "balance_edit" });
	assert.equal(report.json.escalated, false);
	assert.equal((await call(env, "GET", `/access?id=12&nonce=${NONCE}`)).json.state, "active");
	assert.ok(await env.SUBS.get("sub:12"), "subscription untouched");
});

test("a banned account's ledger can't be written or restored", async () => {
	const { env } = await setup();
	await call(env, "POST", "/ban", { id: 13, scope: "full", reason: "r", token: "admin-token" });
	const write = await call(env, "POST", "/sync-ledger", { id: 13, payload: "{\"stars\":1000000}" });
	assert.equal(write.status, 403);
	assert.equal(await env.SUBS.get("ledgersync:13"), null);
	await env.SUBS.put("ledgersync:13", "{\"stars\":5}");
	assert.equal((await call(env, "GET", "/fetch-ledger-sync?id=13")).json.payload, null);
});

test("admin accounts (ADMIN_TG_IDS) are always active", async () => {
	const { env } = await setup();
	await call(env, "POST", "/ban", { id: 1000, scope: "full", reason: "r", token: "admin-token" });
	assert.equal((await call(env, "GET", `/access?id=1000&nonce=${NONCE}`)).json.state, "active");
});
