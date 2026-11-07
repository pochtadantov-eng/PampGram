import test from "node:test";
import assert from "node:assert/strict";
import { handleUpdate } from "../src/bot/main.js";
import { readSubscription } from "../src/core.js";
import { renderDetails, manualAmount, formatAmount, totalsText } from "../src/bot/pay.js";
import { parseRate } from "../src/bot/payadmin.js";
import { createEnv, createTelegram } from "./helpers.js";
import { setPassword } from "../src/bot/security.js";

const ADMIN = { id: 1000, first_name: "Owner", username: "owner" };
const ALICE = { id: 2001, first_name: "Alice", username: "alice" };
let seq = 0;
const msg = (from, text, extra = {}) => ({ message: { message_id: ++seq, from, chat: { id: from.id, type: "private" }, text, ...extra } });
const press = (from, data) => ({ callback_query: { id: `cb${++seq}`, from, data, message: { message_id: 50, chat: { id: from.id, type: "private" } } } });
const labels = (tg, method = "editMessageText") => tg.last(method).reply_markup.inline_keyboard.flat();

async function addMethodViaAdmin(env, tg) {
	await handleUpdate(env, tg, press(ADMIN, "a:pa"));
	await handleUpdate(env, tg, msg(ADMIN, "Карта Сбербанк"));
	await handleUpdate(env, tg, msg(ADMIN, "Карта: 2202 2000 0000 0000\nПолучатель: Иван И.\nПишите после оплаты"));
	await handleUpdate(env, tg, msg(ADMIN, "1,8 ₽"));
	const methods = JSON.parse(await env.SUBS.get("pay"));
	return methods.find((method) => method.kind === "manual");
}

test("helpers: rate parsing, amounts and requisite rendering", () => {
	assert.deepEqual(parseRate("1,8 ₽"), { rate: 1.8, currency: "₽" });
	assert.deepEqual(parseRate("0.02 USDT"), { rate: 0.02, currency: "USDT" });
	assert.equal(parseRate("дорого"), null);
	assert.equal(parseRate("0 ₽"), null);
	assert.equal(formatAmount(manualAmount({ rate: 1.8 }, { stars: 200 }), "₽"), "360 ₽");
	assert.equal(formatAmount(manualAmount({ rate: 0.0333 }, { stars: 3 }), "USDT"), "0.1 USDT");
	const html = renderDetails("Карта: 2202 <b>\nТекст без двоеточия");
	assert.match(html, /Карта: <code>2202 &lt;b&gt;<\/code>/);
	assert.match(html, /\nТекст без двоеточия$/);
	assert.equal(totalsText([{ stars: 200 }, { currency: "₽", amount: 360 }, { currency: "₽", amount: 90.5 }]), "200 ⭐ + 450.5 ₽");
});

test("admin adds a payment method in three steps and sees it on the card", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const method = await addMethodViaAdmin(env, tg);
	assert.equal(method.title, "Карта Сбербанк");
	assert.equal(method.rate, 1.8);
	assert.equal(method.currency, "₽");
	assert.match(method.details, /2202/);
	assert.equal(method.active, true);
	const card = tg.last("sendMessage").text;
	assert.match(card, /1 ⭐ = 1.8 ₽/);
	assert.match(card, /<code>2202 2000 0000 0000<\/code>/);
});

test("customer sees Stars and the manual method with a converted price", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const method = await addMethodViaAdmin(env, tg);
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "t:std"));
	const buttons = labels(tg);
	assert.ok(buttons.some((b) => b.callback_data === "buy:std"));
	const manual = buttons.find((b) => b.callback_data === `pay:std:${method.id}`);
	assert.ok(manual);
	assert.match(manual.text, /Карта Сбербанк — 360 ₽/);
});

test("manual purchase: requisites, 'I paid', receipt reaches the admin, confirm delivers the key", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("bundle", JSON.stringify([{ id: "l1", kind: "link", title: "Установщик", url: "https://example.test/i", tiers: ["standard", "pro"] }]));
	const method = await addMethodViaAdmin(env, tg);

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `pay:std:${method.id}`));
	const shown = tg.last("editMessageText");
	assert.match(shown.text, /К оплате: <b>360 ₽<\/b>/);
	assert.match(shown.text, /<code>2202 2000 0000 0000<\/code>/);
	const orderKey = [...env.SUBS.map.keys()].find((key) => key.startsWith("order:"));
	const orderId = orderKey.slice(6);
	assert.equal(JSON.parse(env.SUBS.map.get(orderKey).value).status, "awaiting");
	assert.equal((await readSubscription(env, "2001")).tier, "standard");

	// "I paid" -> admin gets a claim with confirm / reject buttons
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `pd:${orderId}`));
	const claim = tg.sent("sendMessage").find((m) => String(m.chat_id) === "1000");
	assert.match(claim.text, /Заявка на оплату/);
	const claimButtons = claim.reply_markup.inline_keyboard.flat().map((b) => b.callback_data);
	assert.ok(claimButtons.includes(`a:pc:${orderId}`) && claimButtons.includes(`a:pr:${orderId}`));
	assert.equal(JSON.parse(env.SUBS.map.get(orderKey).value).status, "review");

	// pressing "I paid" twice does not notify again
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `pd:${orderId}`));
	assert.equal(tg.sent("sendMessage").length, 0);

	// the buyer's screenshot is copied to the admin with the same buttons
	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "", { photo: [{ file_id: "P1" }], text: undefined }));
	const copy = tg.last("copyMessage");
	assert.equal(String(copy.chat_id), "1000");
	assert.ok(copy.reply_markup.inline_keyboard.flat().some((b) => b.callback_data === `a:pc:${orderId}`));

	// the key is NOT issued before the admin confirms
	assert.equal([...env.SUBS.map.keys()].some((key) => key.startsWith("key:")), false);

	// a non-admin cannot confirm
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `a:pc:${orderId}`));
	assert.equal(JSON.parse(env.SUBS.map.get(orderKey).value).status, "review");

	// the admin confirms -> the buyer gets key + files
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, `a:pc:${orderId}`));
	const toBuyer = tg.sent("sendMessage").filter((m) => String(m.chat_id) === "2001").map((m) => m.text).join("\n");
	assert.match(toBuyer, /Оплата получена/);
	assert.match(toBuyer, /360 ₽/);
	assert.match(toBuyer, /PMP-/);
	assert.match(toBuyer, /Установщик/);
	const order = JSON.parse(env.SUBS.map.get(orderKey).value);
	assert.equal(order.status, "delivered");
	assert.equal(order.confirmedBy, "1000");

	// confirming again does nothing and does not issue a second key
	const keysBefore = [...env.SUBS.map.keys()].filter((key) => key.startsWith("key:")).length;
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, `a:pc:${orderId}`));
	assert.equal([...env.SUBS.map.keys()].filter((key) => key.startsWith("key:")).length, keysBefore);
	assert.equal(tg.sent("sendMessage").filter((m) => String(m.chat_id) === "2001").length, 0);

	// the buyer can bind the key; stats and profile count the money per currency
	await handleUpdate(env, tg, press(ALICE, `bind:${orderId}`));
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, "a:stats"));
	assert.match(tg.last("editMessageText").text, /360 ₽/);
});

test("rejecting a claim notifies the buyer and issues nothing", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const method = await addMethodViaAdmin(env, tg);
	await handleUpdate(env, tg, press(ALICE, `pay:pro30:${method.id}`));
	const orderKey = [...env.SUBS.map.keys()].find((key) => key.startsWith("order:"));
	const orderId = orderKey.slice(6);
	await handleUpdate(env, tg, press(ALICE, `pd:${orderId}`));
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, `a:pr:${orderId}`));
	assert.match(tg.sent("sendMessage").find((m) => String(m.chat_id) === "2001").text, /не подтверждена/);
	assert.equal(JSON.parse(env.SUBS.map.get(orderKey).value).status, "rejected");
	assert.equal([...env.SUBS.map.keys()].some((key) => key.startsWith("key:")), false);
	// further messages from the buyer are no longer treated as receipts
	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "привет"));
	assert.equal(tg.sent("copyMessage").length, 0);
});

test("buyer can cancel an unpaid order; disabled or deleted methods are refused", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const method = await addMethodViaAdmin(env, tg);
	await handleUpdate(env, tg, press(ALICE, `pay:std:${method.id}`));
	const orderKey = [...env.SUBS.map.keys()].find((key) => key.startsWith("order:"));
	await handleUpdate(env, tg, press(ALICE, `px:${orderKey.slice(6)}`));
	assert.equal(JSON.parse(env.SUBS.map.get(orderKey).value).status, "cancelled");

	await handleUpdate(env, tg, press(ADMIN, `a:pt:${method.id}`));
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `pay:std:${method.id}`));
	assert.match(tg.last("answerCallbackQuery").text, /недоступен/);
	await handleUpdate(env, tg, press(ALICE, "t:std"));
	assert.ok(!labels(tg).some((b) => String(b.callback_data).startsWith("pay:")));

	await setPassword(env, "test-pass-7");
	await handleUpdate(env, tg, press(ADMIN, `a:pdel:${method.id}`));
	await handleUpdate(env, tg, msg(ADMIN, "test-pass-7"));
	const methods = JSON.parse(await env.SUBS.get("pay"));
	assert.ok(!methods.some((m) => m.id === method.id));
});

test("Stars can be switched off; with no active method the tariff says so", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:pt:stars"));
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "t:std"));
	assert.match(tg.last("editMessageText").text, /не настроены/);
	await handleUpdate(env, tg, press(ALICE, "buy:std"));
	assert.equal(tg.sent("sendInvoice").length, 0);
});

test("editing a method's requisites and rate updates what the buyer sees", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const method = await addMethodViaAdmin(env, tg);
	await handleUpdate(env, tg, press(ADMIN, `a:pe:${method.id}:details`));
	await handleUpdate(env, tg, msg(ADMIN, "USDT TRC20: TXyzAbc123"));
	await handleUpdate(env, tg, press(ADMIN, `a:pe:${method.id}:rate`));
	await handleUpdate(env, tg, msg(ADMIN, "0.02 USDT"));
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `pay:std:${method.id}`));
	const text = tg.last("editMessageText").text;
	assert.match(text, /К оплате: <b>4 USDT<\/b>/);
	assert.match(text, /<code>TXyzAbc123<\/code>/);
	assert.doesNotMatch(text, /2202/);
});

test("admin queue lists claims awaiting review", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const method = await addMethodViaAdmin(env, tg);
	await handleUpdate(env, tg, press(ALICE, `pay:std:${method.id}`));
	const orderId = [...env.SUBS.map.keys()].find((key) => key.startsWith("order:")).slice(6);
	await handleUpdate(env, tg, press(ALICE, `pd:${orderId}`));
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, "a:home"));
	assert.ok(labels(tg).some((b) => /Заявки на оплату \(1\)/.test(b.text)));
	await handleUpdate(env, tg, press(ADMIN, "a:pq"));
	assert.ok(labels(tg).some((b) => b.callback_data === `a:po:${orderId}`));
});
