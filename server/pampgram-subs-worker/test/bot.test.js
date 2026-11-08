import test from "node:test";
import assert from "node:assert/strict";
import { handleUpdate } from "../src/bot/main.js";
import { handleWebhook, runScheduled } from "../src/bot/webhook.js";
import { expireChecks } from "../src/bot/admin.js";
import { recordAppSeen, importLegacyUsers } from "../src/users.js";
import { readSubscription, readBanRecord } from "../src/core.js";
import { createEnv, createTelegram } from "./helpers.js";
import { setPassword } from "../src/bot/security.js";

const callsTo = (tg, id) => tg.calls.filter((c) => String(c.params.chat_id) === String(id));
const ADMIN = { id: 1000, first_name: "Owner", username: "owner" };
const ALICE = { id: 2001, first_name: "Alice", username: "alice", language_code: "ru" };
const BOB = { id: 2002, first_name: "Bob", username: "bob" };

let seq = 0;
function setup() {
	return { env: createEnv(), tg: createTelegram() };
}
const msg = (from, text, extra = {}) => ({ message: { message_id: ++seq, from, chat: { id: from.id, type: "private" }, text, ...extra } });
const press = (from, data) => ({ callback_query: { id: `cb${++seq}`, from, data, message: { message_id: 50, chat: { id: from.id, type: "private" } } } });
const preCheckout = (from, payload, amount, currency = "XTR") => ({ pre_checkout_query: { id: `pc${++seq}`, from, invoice_payload: payload, total_amount: amount, currency } });
const payment = (from, payload, amount, charge) => ({
	message: { message_id: ++seq, from, chat: { id: from.id, type: "private" }, successful_payment: { currency: "XTR", total_amount: amount, invoice_payload: payload, telegram_payment_charge_id: charge } },
});

async function buy(env, tg, user, code) {
	tg.reset();
	await handleUpdate(env, tg, press(user, `buy:${code}`));
	const invoice = tg.last("sendInvoice");
	assert.ok(invoice, "an invoice was sent");
	return invoice;
}

async function pay(env, tg, user, invoice, charge) {
	await handleUpdate(env, tg, preCheckout(user, invoice.payload, invoice.prices[0].amount));
	assert.equal(tg.last("answerPreCheckoutQuery").ok, true);
	tg.reset();
	await handleUpdate(env, tg, payment(user, invoice.payload, invoice.prices[0].amount, charge));
}

async function addBundle(env) {
	await env.SUBS.put(
		"bundle",
		JSON.stringify([
			{ id: "f1", kind: "file", title: "PampGram.ipa", fileId: "FILE_IPA", tiers: ["standard", "pro"] },
			{ id: "f2", kind: "file", title: "Сертификат", fileId: "FILE_CERT", tiers: ["pro"] },
			{ id: "l1", kind: "link", title: "Установщик", url: "https://example.test/installer", tiers: ["standard", "pro"] },
			{ id: "t1", kind: "text", title: "Пароль сертификата", text: "hunter2", tiers: ["pro"] },
		])
	);
}

test("/start shows the menu and records the bot user's profile", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	const sent = tg.last("sendMessage");
	assert.match(sent.text, /PampGram/);
	const buttons = sent.reply_markup.inline_keyboard.flat().map((b) => b.callback_data);
	assert.ok(buttons.includes("shop") && buttons.includes("my") && buttons.includes("dl"));
	assert.ok(!buttons.includes("a:home"), "no admin button for a customer");
	const profile = JSON.parse(await env.SUBS.get("u:2001"));
	assert.equal(profile.username, "alice");
	assert.ok(profile.bot.startedAt);
});

test("tariffs: the upgrade tariff is hidden until Standard is owned", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	let labels = tg.last("editMessageText").reply_markup.inline_keyboard.flat().map((b) => b.text).join("|");
	assert.match(labels, /Standard/);
	assert.doesNotMatch(labels, /Доплата/);

	const invoice = await buy(env, tg, ALICE, "std");
	await pay(env, tg, ALICE, invoice, "charge-std");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	labels = tg.last("editMessageText").reply_markup.inline_keyboard.flat().map((b) => b.text).join("|");
	assert.match(labels, /Доплата/);
});

test("buying creates a Stars invoice for the tariff price", async () => {
	const { env, tg } = setup();
	const invoice = await buy(env, tg, ALICE, "pro30");
	assert.equal(invoice.currency, "XTR");
	assert.equal(invoice.prices[0].amount, 500);
	assert.match(invoice.payload, /^o:[a-z0-9]{10}$/);
	const order = JSON.parse(await env.SUBS.get(`order:${invoice.payload.slice(2)}`));
	assert.equal(order.status, "pending");
	assert.equal(order.userId, "2001");
});

test("pre-checkout rejects a wrong amount, a foreign order and a banned buyer", async () => {
	const { env, tg } = setup();
	const invoice = await buy(env, tg, ALICE, "pro30");
	await handleUpdate(env, tg, preCheckout(ALICE, invoice.payload, 1));
	assert.equal(tg.last("answerPreCheckoutQuery").ok, false);
	await handleUpdate(env, tg, preCheckout(BOB, invoice.payload, 500));
	assert.equal(tg.last("answerPreCheckoutQuery").ok, false);
	await env.SUBS.put("ban:2001", JSON.stringify({ full: { reason: "abuse", at: 1 }, sections: {} }));
	await handleUpdate(env, tg, preCheckout(ALICE, invoice.payload, 500));
	assert.equal(tg.last("answerPreCheckoutQuery").ok, false);
});

test("a paid order delivers the key and the tier's files, and tells the admin", async () => {
	const { env, tg } = setup();
	await addBundle(env);
	const invoice = await buy(env, tg, ALICE, "pro30");
	await pay(env, tg, ALICE, invoice, "charge-1");

	const toAlice = callsTo(tg, 2001);
	const text = toAlice.filter((c) => c.method === "sendMessage").map((c) => c.params.text).join("\n");
	const key = text.match(/PMP-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}/)?.[0];
	assert.ok(key, "the key is in the confirmation");
	const docs = toAlice.filter((c) => c.method === "sendDocument").map((c) => c.params.document);
	assert.deepEqual(docs, ["FILE_IPA", "FILE_CERT"], "premium gets both files");
	assert.match(text, /Установщик/);
	assert.match(text, /hunter2/);
	assert.match(text, /Как установить/);

	assert.deepEqual(JSON.parse(await env.SUBS.get(`key:${key}`)), { tier: "pro", durationHours: 720 });
	const order = JSON.parse(await env.SUBS.get(`order:${invoice.payload.slice(2)}`));
	assert.equal(order.status, "delivered");
	assert.equal(order.key, key);
	assert.equal(JSON.parse(await env.SUBS.get("u:2001")).purchases, 1);
	const adminText = callsTo(tg, 1000).map((c) => c.params.text).join("\n");
	assert.match(adminText, /Новая оплата/);
});

test("a standard order does not receive premium-only files", async () => {
	const { env, tg } = setup();
	await addBundle(env);
	const invoice = await buy(env, tg, ALICE, "std");
	await pay(env, tg, ALICE, invoice, "charge-s");
	const docs = tg.calls.filter((c) => c.method === "sendDocument").map((c) => c.params.document);
	assert.deepEqual(docs, ["FILE_IPA"]);
});

test("the same payment notification delivered twice produces one key", async () => {
	const { env, tg } = setup();
	const invoice = await buy(env, tg, ALICE, "pro30");
	await pay(env, tg, ALICE, invoice, "charge-dup");
	const keysBefore = [...env.SUBS.map.keys()].filter((k) => k.startsWith("key:")).length;
	tg.reset();
	await handleUpdate(env, tg, payment(ALICE, invoice.payload, 500, "charge-dup"));
	const keysAfter = [...env.SUBS.map.keys()].filter((k) => k.startsWith("key:")).length;
	assert.equal(keysAfter, keysBefore);
	assert.equal(tg.calls.length, 0);
});

test("a payment with a mismatching amount is not delivered and the admin is warned", async () => {
	const { env, tg } = setup();
	const invoice = await buy(env, tg, ALICE, "pro30");
	tg.reset();
	await handleUpdate(env, tg, payment(ALICE, invoice.payload, 1, "charge-bad"));
	assert.equal([...env.SUBS.map.keys()].filter((k) => k.startsWith("key:")).length, 0);
	assert.match(callsTo(tg, 1000).map((c) => c.params.text).join(), /не совпала/);
});

test("binding the key to the buyer's own account activates it once", async () => {
	const { env, tg } = setup();
	const invoice = await buy(env, tg, ALICE, "pro");
	await pay(env, tg, ALICE, invoice, "charge-b");
	const orderId = invoice.payload.slice(2);
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `bind:${orderId}`));
	assert.equal((await readSubscription(env, "2001")).tier, "pro");
	assert.ok(JSON.parse(await env.SUBS.get("u:2001")).activatedAt);
	await handleUpdate(env, tg, press(ALICE, `bind:${orderId}`));
	assert.match(tg.last("answerCallbackQuery").text, /Уже привязан/);
	await handleUpdate(env, tg, press(BOB, `bind:${orderId}`));
	assert.match(tg.last("answerCallbackQuery").text, /не найден/);
});

test("a banned user cannot open tariffs or buy", async () => {
	const { env, tg } = setup();
	await env.SUBS.put("ban:2001", JSON.stringify({ full: { reason: "abuse", at: 1 }, sections: {} }));
	await handleUpdate(env, tg, press(ALICE, "shop"));
	assert.match(tg.last("editMessageText").text, /Доступ ограничен/);
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "buy:std"));
	assert.equal(tg.sent("sendInvoice").length, 0);
});

test("my purchases lists the key; download resends the files", async () => {
	const { env, tg } = setup();
	await addBundle(env);
	const invoice = await buy(env, tg, ALICE, "pro30");
	await pay(env, tg, ALICE, invoice, "charge-m");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "my"));
	assert.match(tg.last("editMessageText").text, /PMP-/);
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "dl"));
	assert.deepEqual(tg.sent("sendDocument").map((d) => d.document), ["FILE_IPA", "FILE_CERT"]);
	tg.reset();
	await handleUpdate(env, tg, press(BOB, "dl"));
	assert.equal(tg.sent("sendDocument").length, 0, "a stranger gets nothing");
});

test("admin panel is for admins only", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, msg(ALICE, "/admin"));
	assert.doesNotMatch(tg.texts().join(), /Админ-панель/);
	await handleUpdate(env, tg, press(ALICE, "a:stats"));
	assert.equal(tg.sent("editMessageText").length, 0);
	tg.reset();
	await handleUpdate(env, tg, msg(ADMIN, "/admin"));
	assert.match(tg.texts().join(), /Админ-панель/);
});

test("admin sees users with version, sessions and online state; stats add up", async () => {
	const { env, tg } = setup();
	const now = Date.now();
	await recordAppSeen(env, "2001", { version: "2.3.1", build: "241", username: "alice", name: "Alice A" }, now - 120000);
	await recordAppSeen(env, "2002", { version: "2.2.0", username: "bob" }, now - 3 * 24 * 3600000);
	await handleUpdate(env, tg, press(ADMIN, "a:stats"));
	let text = tg.last("editMessageText").text;
	assert.match(text, /Пользователей: <b>2/);
	assert.match(text, /2\.3\.1 — 1/);
	assert.match(text, /2\.2\.0 — 1/);

	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, "a:ul:all:0"));
	const rows = tg.last("editMessageText").reply_markup.inline_keyboard.flat().map((b) => b.text);
	assert.ok(rows.some((label) => label.startsWith("🟢") && label.includes("@alice") && label.includes("v2.3.1")), rows.join(" | "));
	assert.ok(rows.some((label) => label.startsWith("⚪") && label.includes("@bob")));

	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, "a:u:2001"));
	text = tg.last("editMessageText").text;
	assert.match(text, /@alice/);
	assert.match(text, /Версия: 2\.3\.1 \(241\)/);
	assert.match(text, /Заходы \(1\)/);
});

test("admin can find a user by @nick and by id", async () => {
	const { env, tg } = setup();
	await recordAppSeen(env, "2001", { username: "alice" });
	await handleUpdate(env, tg, press(ADMIN, "a:find"));
	tg.reset();
	await handleUpdate(env, tg, msg(ADMIN, "@Alice"));
	assert.match(tg.last("sendMessage").text, /id: <code>2001<\/code>/);
	await handleUpdate(env, tg, press(ADMIN, "a:find"));
	tg.reset();
	await handleUpdate(env, tg, msg(ADMIN, "9999999"));
	assert.match(tg.last("sendMessage").text, /id: <code>9999999<\/code>/);
	await handleUpdate(env, tg, press(ADMIN, "a:find"));
	tg.reset();
	await handleUpdate(env, tg, msg(ADMIN, "nobody"));
	assert.match(tg.last("sendMessage").text, /Никого не нашёл/);
});

test("ban asks for a reason, writes the shared ban record and tells the user; unban reverses it", async () => {
	const { env, tg } = setup();
	await recordAppSeen(env, "2001", { username: "alice" });
	await handleUpdate(env, tg, press(ADMIN, "a:ban:2001"));
	tg.reset();
	await handleUpdate(env, tg, msg(ADMIN, "накрутка"));
	assert.equal((await readBanRecord(env, "2001")).full.reason, "накрутка");
	assert.match(callsTo(tg, 2001)[0].params.text, /накрутка/);
	assert.match(tg.last("sendMessage").text, /Заблокирован/);

	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, "a:unban:2001"));
	assert.equal((await readBanRecord(env, "2001")).full, null);
});

test("verification: request reaches the user, answer notifies the admin, silence expires", async () => {
	const { env, tg } = setup();
	await recordAppSeen(env, "2001", { username: "alice" });
	await handleUpdate(env, tg, press(ADMIN, "a:chk:2001"));
	const dm = callsTo(tg, 2001).find((c) => c.method === "sendMessage");
	assert.match(dm.params.text, /Проверка аккаунта/);
	assert.equal(dm.params.reply_markup.inline_keyboard[0][0].callback_data, "ck:ok");
	assert.equal(JSON.parse(await env.SUBS.get("check:2001")).status, "pending");

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "ck:ok"));
	assert.equal(JSON.parse(await env.SUBS.get("check:2001")).status, "ok");
	assert.match(callsTo(tg, 1000)[0].params.text, /прошёл проверку/);

	// a second request that nobody answers
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, "a:chk:2001"));
	const check = JSON.parse(await env.SUBS.get("check:2001"));
	assert.equal(check.status, "pending");
	check.expiresAt = Date.now() - 1000;
	await env.SUBS.put("check:2001", JSON.stringify(check));
	tg.reset();
	await expireChecks(env, tg, Date.now());
	assert.equal(JSON.parse(await env.SUBS.get("check:2001")).status, "expired");
	assert.match(callsTo(tg, 1000)[0].params.text, /не ответил/);
});

test("verification to a user who never started the bot reports it and saves nothing", async () => {
	const { env, tg } = setup();
	tg.failNext("sendMessage", "Forbidden: bot can't initiate conversation with a user");
	await handleUpdate(env, tg, press(ADMIN, "a:chk:777"));
	assert.equal(await env.SUBS.get("check:777"), null);
	assert.match(tg.last("answerCallbackQuery").text, /Не удалось/);
});

test("grant changes the real subscription the app reads", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, press(ADMIN, "a:g:2001:p30"));
	const subscription = await readSubscription(env, "2001");
	assert.equal(subscription.tier, "pro");
	assert.ok(subscription.expiresAt > Date.now());
	assert.equal(JSON.parse(await env.SUBS.get("u:2001")).tier, "pro");
	await handleUpdate(env, tg, press(ADMIN, "a:g:2001:std"));
	assert.equal((await readSubscription(env, "2001")).tier, "standard");
});

test("admin can message a user through the bot", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, press(ADMIN, "a:dm:2001"));
	tg.reset();
	await handleUpdate(env, tg, msg(ADMIN, "Привет, напиши мне"));
	assert.equal(callsTo(tg, 2001)[0].params.text, "Привет, напиши мне");
});

test("tariff editor: add with validation, change price, switch off, delete", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, press(ADMIN, "a:ta"));
	await handleUpdate(env, tg, msg(ADMIN, "bad line"));
	assert.match(tg.last("sendMessage").text, /Нужно 5-6 полей/);
	await handleUpdate(env, tg, msg(ADMIN, "pro90 | Premium 90 | pro | 1200 | 2160"));
	let tariffs = JSON.parse(await env.SUBS.get("tariffs"));
	assert.equal(tariffs.length, 5);
	assert.deepEqual(tariffs.at(-1), { code: "pro90", title: "Premium 90", tier: "pro", stars: 1200, hours: 2160, desc: "", active: true, requires: "" });

	await handleUpdate(env, tg, press(ADMIN, "a:tp:pro90"));
	await handleUpdate(env, tg, msg(ADMIN, "abc"));
	assert.match(tg.last("sendMessage").text, /целое число/);
	await handleUpdate(env, tg, msg(ADMIN, "999"));
	tariffs = JSON.parse(await env.SUBS.get("tariffs"));
	assert.equal(tariffs.find((t) => t.code === "pro90").stars, 999);

	await handleUpdate(env, tg, press(ADMIN, "a:tt:pro90"));
	assert.equal(JSON.parse(await env.SUBS.get("tariffs")).find((t) => t.code === "pro90").active, false);
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	assert.doesNotMatch(JSON.stringify(tg.last("editMessageText")), /Premium 90/);

	await setPassword(env, "test-pass-7");
	await handleUpdate(env, tg, press(ADMIN, "a:tx:pro90"));
	await handleUpdate(env, tg, msg(ADMIN, "test-pass-7"));
	assert.equal(JSON.parse(await env.SUBS.get("tariffs")).some((t) => t.code === "pro90"), false);
});

test("delivery set: add a file by sending it, toggle tiers, rename, delete", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, press(ADMIN, "a:baf"));
	await handleUpdate(env, tg, msg(ADMIN, "", { document: { file_id: "BIGFILE", file_name: "PampGram.ipa" } }));
	let items = JSON.parse(await env.SUBS.get("bundle"));
	assert.equal(items.length, 1);
	assert.equal(items[0].fileId, "BIGFILE");
	assert.equal(items[0].title, "PampGram.ipa");
	assert.deepEqual(items[0].tiers, ["standard", "pro"]);

	await handleUpdate(env, tg, press(ADMIN, `a:bg:${items[0].id}:standard`));
	items = JSON.parse(await env.SUBS.get("bundle"));
	assert.deepEqual(items[0].tiers, ["pro"]);

	await handleUpdate(env, tg, press(ADMIN, "a:bal"));
	await handleUpdate(env, tg, msg(ADMIN, "Установщик | https://example.test/i"));
	await handleUpdate(env, tg, press(ADMIN, "a:bat"));
	await handleUpdate(env, tg, msg(ADMIN, "Пароль | a|b|c"));
	items = JSON.parse(await env.SUBS.get("bundle"));
	assert.equal(items.length, 3);
	assert.equal(items[2].text, "a|b|c");

	await setPassword(env, "test-pass-7");
	await handleUpdate(env, tg, press(ADMIN, `a:bd:${items[0].id}`));
	await handleUpdate(env, tg, msg(ADMIN, "test-pass-7"));
	assert.equal(JSON.parse(await env.SUBS.get("bundle")).length, 2);

	await handleUpdate(env, tg, press(ADMIN, "a:bal"));
	await handleUpdate(env, tg, msg(ADMIN, "Плохая | not-a-url"));
	assert.match(tg.last("sendMessage").text, /Формат/);
});

test("settings: change support handle and reject an unknown timezone", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, press(ADMIN, "a:cf:support"));
	await handleUpdate(env, tg, msg(ADMIN, "@helper"));
	assert.equal(JSON.parse(await env.SUBS.get("cfg")).support, "@helper");
	await handleUpdate(env, tg, press(ADMIN, "a:cf:tz"));
	await handleUpdate(env, tg, msg(ADMIN, "Mars/Olympus"));
	assert.match(tg.last("sendMessage").text, /Не знаю такого пояса/);
	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	assert.match(JSON.stringify(tg.last("sendMessage")), /t\.me\/helper/);
});

test("import brings in users known only from the legacy seen: keys", async () => {
	const { env, tg } = setup();
	await env.SUBS.put("seen:555", String(Date.now() - 60000));
	await env.SUBS.put("sub:556", "pro");
	assert.equal(await importLegacyUsers(env), 2);
	assert.equal(await importLegacyUsers(env), 0);
	await handleUpdate(env, tg, press(ADMIN, "a:ul:pro:0"));
	assert.match(JSON.stringify(tg.last("editMessageText").reply_markup), /id 556/);
});

test("webhook: wrong secret is refused, right secret runs the update, errors still answer 200", async () => {
	const { env, tg } = setup();
	const post = (secret, body) => new Request("https://x.test/tg", { method: "POST", headers: { "x-telegram-bot-api-secret-token": secret, "content-type": "application/json" }, body: JSON.stringify(body) });
	assert.equal((await handleWebhook(post("wrong", msg(ALICE, "/start")), env, tg)).status, 403);
	assert.equal(tg.calls.length, 0);
	assert.equal((await handleWebhook(post("hook-secret", msg(ALICE, "/start")), env, tg)).status, 200);
	assert.ok(tg.sent("sendMessage").length > 0);
	const broken = { call: async () => { throw new Error("boom"); } };
	assert.equal((await handleWebhook(post("hook-secret", msg(ALICE, "/start")), env, broken)).status, 200);
	assert.equal((await handleWebhook(post("hook-secret", msg(ALICE, "/start")), createEnv({ BOT_TOKEN: "" }), tg)).status, 503);
});

test("the bot ignores group chats and other bots", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, { message: { message_id: 1, from: ALICE, chat: { id: -100, type: "supergroup" }, text: "/start" } });
	await handleUpdate(env, tg, msg({ id: 3, is_bot: true, first_name: "b" }, "/start"));
	assert.equal(tg.calls.length, 0);
});

test("blocking the bot is recorded on the profile", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	await handleUpdate(env, tg, { my_chat_member: { from: ALICE, chat: { id: 2001, type: "private" }, new_chat_member: { status: "kicked" } } });
	assert.equal(JSON.parse(await env.SUBS.get("u:2001")).bot.blocked, true);
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	assert.equal(JSON.parse(await env.SUBS.get("u:2001")).bot.blocked, false);
});

test("admin panel mints keys for 1–5 minutes, a day, a month and forever", async () => {
	const { env, tg } = setup();
	await handleUpdate(env, tg, press(ADMIN, "a:k"));
	const menu = JSON.stringify(tg.calls.map((c) => c.params));
	for (const label of ["1 минута", "5 минут", "1 день", "1 месяц", "Навсегда"]) {
		assert.ok(menu.includes(label), `menu offers ${label}`);
	}
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, "a:kg:m2"));
	const text = JSON.stringify(tg.calls.map((c) => c.params));
	const key = text.match(/PMP-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}/)?.[0];
	assert.ok(key, "the key is shown to the admin");
	const stored = JSON.parse(await env.SUBS.get(`key:${key}`));
	assert.equal(stored.tier, "pro");
	assert.ok(Math.abs(stored.durationHours - 2 / 60) < 1e-9);

	await handleUpdate(env, tg, press(ADMIN, "a:kg:pf"));
	const forever = JSON.stringify(tg.calls.map((c) => c.params)).match(/PMP-[A-Z0-9-]+/g).pop();
	assert.equal(await env.SUBS.get(`key:${forever}`), "pro", "a permanent key is stored as the plain tier");
});

test("admin panel grants Premium for a few minutes or a day", async () => {
	const { env, tg } = setup();
	const before = Date.now();
	await handleUpdate(env, tg, press(ADMIN, "a:g:2001:m5"));
	const short = await readSubscription(env, "2001");
	assert.equal(short.tier, "pro");
	assert.ok(short.expiresAt >= before + 299_000 && short.expiresAt <= Date.now() + 301_000);
	await handleUpdate(env, tg, press(ADMIN, "a:g:2001:d1"));
	const day = await readSubscription(env, "2001");
	assert.ok(day.expiresAt >= before + 24 * 3600_000 - 1000);
});

// ---------- TON straight to the owner's wallet ----------

import { savePayMethods, getPayMethods as readPayMethods, getOrder as readOrder } from "../src/bot/store.js";

const TON_ADDRESS = "UQ" + "A".repeat(46);

async function withFetch(impl, fn) {
	const original = globalThis.fetch;
	globalThis.fetch = impl;
	try {
		return await fn();
	} finally {
		globalThis.fetch = original;
	}
}

function toncenter(txs) {
	return async () => new Response(JSON.stringify({ ok: true, result: txs }));
}

async function tonSetup() {
	const { env, tg } = setup();
	const methods = await readPayMethods(env);
	await savePayMethods(env, [...methods, { id: "tonm", kind: "manual", title: "TON", details: "", rate: 0.01, currency: "TON", active: true, tonAddress: TON_ADDRESS }]);
	return { env, tg };
}

async function startTonOrder(env, tg) {
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "pay:pro30:tonm"));
	const text = JSON.stringify(tg.calls.map((c) => c.params));
	assert.ok(text.includes(TON_ADDRESS), "address shown");
	assert.ok(text.includes("app.tonkeeper.com/transfer"), "tonkeeper link");
	const id = text.match(/PMP-([A-Za-z0-9]+)/)[1];
	return readOrder(env, id);
}

test("TON: admin sets the wallet for auto-check", async () => {
	const { env, tg } = setup();
	const methods = await readPayMethods(env);
	await savePayMethods(env, [...methods, { id: "m1", kind: "manual", title: "TON", details: "x", rate: 0.01, currency: "TON", active: true }]);
	await handleUpdate(env, tg, press(ADMIN, "a:pe:m1:ton"));
	await handleUpdate(env, tg, msg(ADMIN, "not an address"));
	assert.equal((await readPayMethods(env)).find((m) => m.id === "m1").tonAddress, undefined);
	await handleUpdate(env, tg, press(ADMIN, "a:pe:m1:ton"));
	await handleUpdate(env, tg, msg(ADMIN, TON_ADDRESS));
	assert.equal((await readPayMethods(env)).find((m) => m.id === "m1").tonAddress, TON_ADDRESS);
});

test("TON: payment is found on-chain and the key is delivered; a tx pays only once", async () => {
	const { env, tg } = await tonSetup();
	const order = await startTonOrder(env, tg);
	assert.equal(order.amount, 5);
	assert.ok(await env.SUBS.get(`tonwait:${order.id}`));

	await withFetch(toncenter([]), () => handleUpdate(env, tg, press(ALICE, `pd:${order.id}`)));
	assert.equal((await readOrder(env, order.id)).status, "awaiting", "nothing on-chain yet");

	const tx = { utime: Math.floor(Date.now() / 1000), transaction_id: { hash: "h1", lt: "1" }, in_msg: { source: "UQbuyer", value: "5000000000", message: `PMP-${order.id}` } };
	const short = { ...tx, transaction_id: { hash: "h0" }, in_msg: { ...tx.in_msg, value: "4000000000" } };
	tg.reset();
	await withFetch(toncenter([short, tx]), () => handleUpdate(env, tg, press(ALICE, `pd:${order.id}`)));
	const paid = await readOrder(env, order.id);
	assert.ok(["paid", "delivered"].includes(paid.status), paid.status);
	assert.equal(paid.tonTx, "h1");
	assert.ok(JSON.stringify(tg.calls).includes("PMP-"), "a key went out");
	assert.equal(await env.SUBS.get("tontx:h1"), order.id);
	assert.equal(await env.SUBS.get(`tonwait:${order.id}`), null);

	// Same transaction can't pay a second order even with a copied comment.
	const second = await startTonOrder(env, tg);
	const reused = { ...tx, in_msg: { ...tx.in_msg, message: `PMP-${second.id}` } };
	await withFetch(toncenter([reused]), () => handleUpdate(env, tg, press(ALICE, `pd:${second.id}`)));
	assert.equal((await readOrder(env, second.id)).status, "awaiting");
});

test("TON: the cron finds a payment nobody pressed the button for", async () => {
	const { env, tg } = await tonSetup();
	const order = await startTonOrder(env, tg);
	const tx = { utime: Math.floor(Date.now() / 1000), transaction_id: { hash: "c1" }, in_msg: { source: "UQbuyer", value: "6000000000", message: `PMP-${order.id}` } };
	await withFetch(toncenter([tx]), () => runScheduled(env, tg));
	assert.ok(["paid", "delivered"].includes((await readOrder(env, order.id)).status));
});
