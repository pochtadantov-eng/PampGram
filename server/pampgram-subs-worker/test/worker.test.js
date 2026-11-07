import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import { createEnv, createCtx } from "./helpers.js";

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

test("/status defaults to standard and signs the answer", async () => {
	const env = createEnv();
	const { status, json } = await call(env, "GET", "/status?id=42");
	assert.equal(status, 200);
	assert.equal(json.tier, "standard");
	assert.equal(json.expiresAt, null);
	assert.match(json.sig, /^[0-9a-f]{64}$/);
	assert.ok(await env.SUBS.get("seen:42"));
});

test("/status records version, build, nick and sessions; a new session starts after a long gap", async () => {
	const env = createEnv();
	await call(env, "GET", "/status?id=42&v=2.3.1&b=241&u=%40nick&n=Ivan");
	let user = JSON.parse(await env.SUBS.get("u:42"));
	assert.equal(user.appVersion, "2.3.1");
	assert.equal(user.appBuild, "241");
	assert.equal(user.username, "nick");
	assert.equal(user.name, "Ivan");
	assert.equal(user.sessions.length, 1);

	await call(env, "GET", "/status?id=42&v=2.3.1");
	user = JSON.parse(await env.SUBS.get("u:42"));
	assert.equal(user.sessions.length, 1, "a second call right away is the same visit");

	user.lastSeen -= 60 * 60 * 1000;
	await env.SUBS.put("u:42", JSON.stringify(user));
	await call(env, "GET", "/status?id=42&v=2.4.0");
	user = JSON.parse(await env.SUBS.get("u:42"));
	assert.equal(user.sessions.length, 2);
	assert.equal(user.appVersion, "2.4.0");
});

test("/status rejects a bad id and ignores garbage in the optional fields", async () => {
	const env = createEnv();
	assert.equal((await call(env, "GET", "/status?id=abc")).status, 400);
	const long = "x".repeat(500);
	await call(env, "GET", `/status?id=7&v=${long}&n=%00%01bad`);
	const user = JSON.parse(await env.SUBS.get("u:7"));
	assert.equal(user.appVersion.length, 16);
	assert.equal(user.name, "bad");
});

test("/grant needs the admin token, sets the tier and the profile follows", async () => {
	const env = createEnv();
	assert.equal((await call(env, "POST", "/grant", { id: 5, tier: "pro", token: "nope" })).status, 401);
	const ok = await call(env, "POST", "/grant", { id: 5, tier: "pro", token: "admin-token", durationHours: 24 });
	assert.equal(ok.status, 200);
	assert.ok(ok.json.expiresAt > Date.now());
	assert.equal((await call(env, "GET", "/status?id=5")).json.tier, "pro");
	assert.equal(JSON.parse(await env.SUBS.get("u:5")).tier, "pro");
});

test("activation keys: generate, redeem once, then it is gone", async () => {
	const env = createEnv();
	const made = await call(env, "POST", "/generate-key", { token: "admin-token", tier: "pro" });
	assert.equal(made.status, 200);
	assert.match(made.json.key, /^PMP-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$/);

	const first = await call(env, "POST", "/redeem-key", { id: 9, key: made.json.key.toLowerCase() });
	assert.deepEqual({ ok: first.json.ok, tier: first.json.tier }, { ok: true, tier: "pro" });
	assert.equal((await call(env, "GET", "/status?id=9")).json.tier, "pro");
	const profile = JSON.parse(await env.SUBS.get("u:9"));
	assert.ok(profile.activatedAt);

	const second = await call(env, "POST", "/redeem-key", { id: 10, key: made.json.key });
	assert.equal(second.status, 404);
});

test("time-limited key starts its clock at redemption", async () => {
	const env = createEnv();
	const made = await call(env, "POST", "/generate-key", { token: "admin-token", tier: "pro", durationHours: 2 });
	assert.equal(made.json.durationHours, 2);
	const redeemed = await call(env, "POST", "/redeem-key", { id: 11, key: made.json.key });
	const hours = (redeemed.json.expiresAt - Date.now()) / 3600000;
	assert.ok(hours > 1.9 && hours <= 2);
});

test("ban and unban keep the existing record shape", async () => {
	const env = createEnv();
	await call(env, "POST", "/ban", { id: 3, token: "admin-token", scope: "full", reason: "spam" });
	let status = (await call(env, "GET", "/ban-status?id=3")).json;
	assert.equal(status.full, "spam");
	await call(env, "POST", "/unban", { id: 3, token: "admin-token", scope: "all" });
	status = (await call(env, "GET", "/ban-status?id=3")).json;
	assert.equal(status.full, null);
});

test("/users-list still reports users that only have the legacy seen: key", async () => {
	const env = createEnv();
	await env.SUBS.put("seen:77", String(Date.now()));
	const { json } = await call(env, "POST", "/users-list", { token: "admin-token" });
	assert.equal(json.total, 1);
	assert.equal(json.users[0].id, "77");
});
