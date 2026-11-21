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

test("/user-detail returns profile, ban, tier and ledger totals for the admin", async () => {
	const env = createEnv();
	const now = Date.now();
	await env.SUBS.put("seen:88", String(now));
	await env.SUBS.put(
		"u:88",
		JSON.stringify({
			id: "88",
			firstSeen: now - 60_000,
			lastSeen: now,
			sessions: [now - 60_000, now],
			username: "tester",
			name: "Test User",
			appVersion: "1.5.2",
			appBuild: "252",
			bot: null,
			activatedAt: null,
			purchases: 0,
			note: "",
		})
	);
	await call(env, "POST", "/grant", { id: 88, tier: "pro", token: "admin-token", durationHours: 24 });
	await call(env, "POST", "/ban", { id: 88, token: "admin-token", scope: "full", reason: "abuse" });
	await env.SUBS.put(
		"ledgersync:88",
		JSON.stringify({
			starsBalance: 900,
			tonBalanceNanos: 2_500_000_000,
			operations: [
				{ id: 1, currency: { value: "stars" }, kind: { value: "topUp" }, amount: 1000, date: 100, title: "Пополнение" },
				{ id: 2, currency: { value: "stars" }, kind: { value: "purchase" }, amount: -100, date: 200, title: "Покупка" },
				{ id: 3, currency: { value: "ton" }, kind: { value: "credit" }, amount: 3_000_000_000, date: 300, title: "Зачисление" },
				{ id: 4, currency: { value: "ton" }, kind: { value: "debit" }, amount: -500_000_000, date: 400, title: "Списание" },
				{ id: 5, currency: { value: "stars" }, kind: { value: "topUp" }, amount: 25, date: 500, title: "Подарок мне", details: "Lol Pop #42", giftId: 777 },
				{ id: 6, currency: { value: "stars" }, kind: { value: "purchase" }, amount: -250, date: 600, title: "Покупка подарка", details: "Delicious Cake", giftId: 778 },
				{ id: 7, currency: { value: "stars" }, kind: { value: "sale" }, amount: 180, date: 700, title: "Продажа подарка", details: "Delicious Cake", giftId: 778 },
			],
		})
	);

	const denied = await call(env, "POST", "/user-detail", { token: "wrong", id: 88 });
	assert.equal(denied.status, 401);

	const { status, json } = await call(env, "POST", "/user-detail", { token: "admin-token", id: 88 });
	assert.equal(status, 200);
	assert.equal(json.id, "88");
	assert.equal(json.username, "tester");
	assert.equal(json.appVersion, "1.5.2");
	assert.equal(json.tier, "pro");
	assert.equal(json.full.reason, "abuse");
	assert.equal(json.sessions.length, 2);
	assert.equal(json.ledger.starsBalance, 900);
	assert.equal(json.ledger.starsReceived, 1205);
	assert.equal(json.ledger.starsSpent, 350);
	assert.equal(json.ledger.tonReceivedNanos, 3_000_000_000);
	assert.equal(json.ledger.tonSpentNanos, 500_000_000);
	assert.equal(json.ledger.nftReceived, 1);
	assert.equal(json.ledger.nftBought, 1);
	assert.equal(json.ledger.nftSold, 1);
	assert.equal(json.ledger.nfts[0].name, "Delicious Cake");
	assert.equal(json.ledger.operations[0].title, "Продажа подарка");
	assert.equal(json.ledger.operations[0].isGift, true);
	assert.equal(json.ledger.operations[0].giftId, 778);
	assert.equal(json.real, null);

	await call(env, "POST", "/unban", { id: 88, token: "admin-token", scope: "all" });
	const syncReal = await call(env, "POST", "/sync-real-ledger", {
		id: 88,
		payload: JSON.stringify({
			starsBalance: 420,
			tonBalanceNanos: 0,
			updatedAt: now,
			transactions: [
				{ id: "tx1", currency: "stars", amount: -50, date: 800, title: "Gift", description: "to friend", peer: "@friend", giftTitle: "Lol Pop", flags: ["gift"] },
				{ id: "tx2", currency: "stars", amount: 100, date: 900, title: "Top up", description: "", peer: "App Store", giftTitle: "", flags: [] },
			],
		}),
	});
	assert.equal(syncReal.status, 200);
	const afterReal = (await call(env, "POST", "/user-detail", { token: "admin-token", id: 88 })).json;
	assert.equal(afterReal.real.starsBalance, 420);
	assert.equal(afterReal.real.starsSpent, 50);
	assert.equal(afterReal.real.starsReceived, 100);
	assert.equal(afterReal.real.giftOps, 1);
	assert.equal(afterReal.real.transactions[0].title, "Top up");
	assert.equal(afterReal.real.transactions.find((tx) => tx.id === "tx1").giftTitle, "Lol Pop");

	const list = (await call(env, "POST", "/users-list", { token: "admin-token" })).json;
	const row = list.users.find((user) => user.id === "88");
	assert.equal(row.username, "tester");
	assert.equal(row.sessionsCount, 2);
	assert.equal(row.tier, "pro");
});

test("admin can force and clear fullscreen video for one user and for all", async () => {
	const env = createEnv({ ADMIN_TOKEN: "admin-token" });
	const forced = await call(env, "POST", "/force-video", {
		token: "admin-token",
		id: 42,
		url: "https://example.com/clip.mp4",
		loop: true,
		dismissible: false,
	});
	assert.equal(forced.status, 200);
	assert.ok(forced.json.video.id);
	assert.equal(forced.json.video.url, "https://example.com/clip.mp4");

	const getOne = await call(env, "GET", "/force-video?id=42");
	assert.equal(getOne.json.video.url, "https://example.com/clip.mp4");

	const getOther = await call(env, "GET", "/force-video?id=99");
	assert.equal(getOther.json.video, null);

	await call(env, "POST", "/force-video", {
		token: "admin-token",
		id: "all",
		url: "https://cdn.example.com/all.m3u8",
	});
	const getGlobal = await call(env, "GET", "/force-video?id=99");
	assert.equal(getGlobal.json.video.url, "https://cdn.example.com/all.m3u8");
	// User-specific still wins over global.
	const getPreferred = await call(env, "GET", "/force-video?id=42");
	assert.equal(getPreferred.json.video.url, "https://example.com/clip.mp4");

	assert.equal((await call(env, "POST", "/force-video", { token: "wrong", id: "all", url: "https://x.com/a.mp4" })).status, 401);
	assert.equal((await call(env, "POST", "/force-video", { token: "admin-token", id: 1, url: "http://insecure.mp4" })).status, 400);

	await call(env, "POST", "/clear-force-video", { token: "admin-token", id: 42 });
	assert.equal((await call(env, "GET", "/force-video?id=42")).json.video.url, "https://cdn.example.com/all.m3u8");
	await call(env, "POST", "/clear-force-video", { token: "admin-token", id: "all" });
	assert.equal((await call(env, "GET", "/force-video?id=42")).json.video, null);
});
