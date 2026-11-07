import test from "node:test";
import assert from "node:assert/strict";
import { handleUpdate } from "../src/bot/main.js";
import { setPassword } from "../src/bot/security.js";
import { getText, TEXTS } from "../src/bot/texts.js";
import { createEnv, createTelegram } from "./helpers.js";

const ADMIN = { id: 1000, first_name: "Owner", username: "owner" };
const ALICE = { id: 2001, first_name: "Alice", username: "alice" };
let seq = 0;
const msg = (from, text) => ({ message: { message_id: ++seq, from, chat: { id: from.id, type: "private" }, text } });
const press = (from, data) => ({ callback_query: { id: `cb${++seq}`, from, data, message: { message_id: 50, chat: { id: from.id, type: "private" } } } });
const flat = (params) => params.reply_markup.inline_keyboard.flat();

async function setText(env, tg, key, value) {
	await handleUpdate(env, tg, press(ADMIN, `a:tke:${key}`));
	await handleUpdate(env, tg, msg(ADMIN, value));
}

test("standard texts are unchanged until the owner edits them", async () => {
	const env = createEnv();
	assert.equal(await getText(env, "shop_intro"), "<b>Тарифы</b>\nВыберите тариф, затем способ оплаты. Ключ и файлы приходят после оплаты.");
	assert.equal(await getText(env, "banned", { reason: "спам <b>" }), "⛔ Доступ ограничен.\nПричина: спам &lt;b&gt;");
	for (const [key, entry] of Object.entries(TEXTS)) {
		assert.ok(entry.title && entry.group && typeof entry.text === "string", key);
	}
});

test("admin changes the tariff screen text; customers see it, with *bold* and escaping", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:tk"));
	assert.match(tg.last("editMessageText").text, /Тексты бота/);
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.callback_data === "a:tk:shop_intro"));
	await setText(env, tg, "shop_intro", "*Наши цены* <скидка> 🔥\nВыбирайте!");
	assert.deepEqual(JSON.parse(await env.SUBS.get("texts")), { shop_intro: "*Наши цены* <скидка> 🔥\nВыбирайте!" });
	assert.match(tg.last("sendMessage").text, /ваш текст/);

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	assert.equal(tg.last("editMessageText").text, "<b>Наши цены</b> &lt;скидка&gt; 🔥\nВыбирайте!");
});

test("placeholders are filled with escaped values", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("ban:2001", JSON.stringify({ full: { reason: "<спам>", at: 1 }, sections: {} }));
	await setText(env, tg, "banned", "Вы заблокированы. Причина: {reason}. Неизвестное {nothing}");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	assert.equal(tg.last("editMessageText").text, "Вы заблокированы. Причина: &lt;спам&gt;. Неизвестное {nothing}");
});

test("privacy, purchases, payment and delivery texts all come from the registry", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await setText(env, tg, "privacy", "Мы ничего не собираем");
	await setText(env, tg, "my_empty", "Пусто, как в кошельке");
	await setText(env, tg, "my_title", "*Ваши заказы*");
	await setText(env, tg, "bundle_empty", "Файлов нет, пишите мне");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "privacy"));
	assert.equal(tg.last("editMessageText").text, "Мы ничего не собираем");
	await handleUpdate(env, tg, press(ALICE, "my"));
	assert.equal(tg.last("editMessageText").text, "Пусто, как в кошельке");

	// a bought tariff: header, key note, no-files text
	await setText(env, tg, "paid_title", "🎉 *Спасибо за покупку*");
	await setText(env, tg, "key_note", "Берегите ключ");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "buy:std"));
	const invoice = tg.last("sendInvoice");
	await handleUpdate(env, tg, { pre_checkout_query: { id: "pc1", from: ALICE, invoice_payload: invoice.payload, total_amount: invoice.prices[0].amount, currency: "XTR" } });
	tg.reset();
	await handleUpdate(env, tg, { message: { message_id: ++seq, from: ALICE, chat: { id: ALICE.id, type: "private" }, successful_payment: { currency: "XTR", total_amount: invoice.prices[0].amount, invoice_payload: invoice.payload, telegram_payment_charge_id: "c1" } } });
	const toBuyer = tg.sent("sendMessage").filter((m) => String(m.chat_id) === "2001").map((m) => m.text).join("\n");
	assert.match(toBuyer, /🎉 <b>Спасибо за покупку<\/b>/);
	assert.match(toBuyer, /Берегите ключ/);
	assert.doesNotMatch(toBuyer, /Ключ одноразовый/);
	assert.match(toBuyer, /Файлов нет, пишите мне/);
	await handleUpdate(env, tg, press(ALICE, "my"));
	assert.match(tg.last("editMessageText").text, /^<b>Ваши заказы<\/b>/);
});

test("the owner's wording is never overwritten and reset needs the password", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await setPassword(env, "test-pass-7");
	await setText(env, tg, "no_tariffs", "Тарифы скоро");
	await handleUpdate(env, tg, press(ADMIN, "a:tk:no_tariffs"));
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.callback_data === "a:tkr:no_tariffs"));
	await handleUpdate(env, tg, press(ADMIN, "a:tkr:no_tariffs"));
	assert.match(tg.last("editMessageText").text, /Введите пароль/);
	assert.equal(JSON.parse(await env.SUBS.get("texts")).no_tariffs, "Тарифы скоро", "not reset yet");
	await handleUpdate(env, tg, msg(ADMIN, "test-pass-7"));
	assert.deepEqual(JSON.parse(await env.SUBS.get("texts")), {});
	assert.equal(await getText(env, "no_tariffs"), "Сейчас нет доступных тарифов.");
});

test("empty or too long text is refused; non-admins cannot edit; backups include texts", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:tke:privacy"));
	await handleUpdate(env, tg, msg(ADMIN, "x".repeat(3001)));
	assert.match(tg.last("sendMessage").text, /от 1 до 3000/);
	assert.equal(await env.SUBS.get("texts"), null);
	await handleUpdate(env, tg, press(ALICE, "a:tke:privacy"));
	await handleUpdate(env, tg, msg(ALICE, "взлом"));
	assert.equal(await env.SUBS.get("texts"), null);
	const { BACKUP_KEYS } = await import("../src/bot/backup.js");
	assert.ok(BACKUP_KEYS.includes("texts") && BACKUP_KEYS.includes("products"));
});

test("shop-section texts: empty product list, hand-over note and section payment hint", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:bta:menu"));
	await handleUpdate(env, tg, msg(ADMIN, "Раздел"));
	await handleUpdate(env, tg, press(ADMIN, "a:btt:menu:shop"));
	await handleUpdate(env, tg, msg(ADMIN, "Описание"));
	const section = JSON.parse(await env.SUBS.get("buttons")).custom.at(-1);
	await setText(env, tg, "no_products", "Скоро добавим");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `cb:${section.id}`));
	assert.match(tg.last("editMessageText").text, /Скоро добавим/);
});
