import test from "node:test";
import assert from "node:assert/strict";
import { handleUpdate } from "../src/bot/main.js";
import { applyEmoji, customEmojiIds, EMOJI_SLOTS } from "../src/bot/emoji.js";
import { fixTitle } from "../src/bot/ui.js";
import { createEnv, createTelegram } from "./helpers.js";
import { setPassword } from "../src/bot/security.js";

const ADMIN = { id: 1000, first_name: "Owner", username: "owner" };
const ALICE = { id: 2001, first_name: "Alice", username: "alice" };
let seq = 0;
const msg = (from, text, extra = {}) => ({ message: { message_id: ++seq, from, chat: { id: from.id, type: "private" }, text, ...extra } });
const press = (from, data) => ({ callback_query: { id: `cb${++seq}`, from, data, message: { message_id: 50, chat: { id: from.id, type: "private" } } } });
const buttons = (params) => params.reply_markup.inline_keyboard.flat();

test("fixTitle: 'навсегда' instead of '0 дней', real durations untouched", () => {
	assert.equal(fixTitle("Premium · 0 дней", 0), "Premium · навсегда");
	assert.equal(fixTitle("Premium · 0 дн.", 0), "Premium · навсегда");
	assert.equal(fixTitle("Premium · 0 часов", 0), "Premium · навсегда");
	assert.equal(fixTitle("Premium · 30 дней", 720), "Premium · 30 дней");
	assert.equal(fixTitle("Premium · 30 дней", 0), "Premium · 30 дней");
	assert.equal(fixTitle("Premium · 10 дней", 0), "Premium · 10 дней");
	assert.equal(fixTitle("Standard", 0), "Standard");
});

test("customers see 'навсегда' for a tariff stored with '0 дней' in its title", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("tariffs", JSON.stringify([
		{ code: "a", title: "Premium · 1 день", tier: "pro", stars: 500, hours: 24, active: true, requires: "" },
		{ code: "b", title: "Premium · 0 дней", tier: "pro", stars: 3000, hours: 0, active: true, requires: "" },
	]));
	await handleUpdate(env, tg, press(ALICE, "shop"));
	const labels = buttons(tg.last("editMessageText")).map((b) => b.text);
	assert.ok(labels.includes("Premium · навсегда — 3000 ⭐"), labels.join("|"));
	assert.ok(labels.includes("Premium · 1 день — 500 ⭐"));
	assert.ok(!labels.some((l) => /0 дн/.test(l)));
});

test("applyEmoji: text and leading button emoji are replaced, everything else is untouched", () => {
	const map = { "🛒": "111", "⭐": "222" };
	const params = { text: "Цена ⭐ <b>x</b> 🛒️", parse_mode: "HTML", reply_markup: { inline_keyboard: [[{ text: "🛒 Купить", callback_data: "shop" }, { text: "Назад", callback_data: "menu" }]] } };
	const out = applyEmoji("sendMessage", params, map);
	assert.match(out.text, /<tg-emoji emoji-id="222">⭐<\/tg-emoji> <b>x<\/b> <tg-emoji emoji-id="111">🛒/);
	assert.deepEqual(out.reply_markup.inline_keyboard[0][0], { text: "Купить", callback_data: "shop", icon_custom_emoji_id: "111" });
	assert.deepEqual(out.reply_markup.inline_keyboard[0][1], { text: "Назад", callback_data: "menu" });
	assert.equal(applyEmoji("sendMessage", params, {}), params, "no mapping -> same object");
	assert.equal(applyEmoji("sendMessage", { text: "⭐" }, map).text, "⭐", "plain text mode is left alone");
	assert.deepEqual(customEmojiIds({ entities: [{ type: "custom_emoji", offset: 3, length: 2, custom_emoji_id: "B" }, { type: "bold", offset: 0, length: 1 }, { type: "custom_emoji", offset: 0, length: 2, custom_emoji_id: "A" }] }), ["A", "B"]);
});

test("admin assigns animated emoji (several at once, in order); the bot then uses them", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:em:0"));
	assert.match(tg.last("editMessageText").text, /⭐/);
	await handleUpdate(env, tg, msg(ADMIN, "🔥🔥", { entities: [{ type: "custom_emoji", offset: 0, length: 2, custom_emoji_id: "900" }, { type: "custom_emoji", offset: 2, length: 2, custom_emoji_id: "901" }] }));
	const stored = JSON.parse(await env.SUBS.get("emoji"));
	assert.equal(stored[EMOJI_SLOTS[0]], "900");
	assert.equal(stored[EMOJI_SLOTS[1]], "901");

	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	const sent = tg.last("sendMessage");
	const shop = buttons(sent).find((b) => b.callback_data === "shop");
	assert.equal(shop.icon_custom_emoji_id, "901", "🛒 is slot 1");
	assert.ok(!shop.text.startsWith("🛒"));
});

test("a message that is not an animated emoji is refused politely", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:em:3"));
	tg.reset();
	await handleUpdate(env, tg, msg(ADMIN, "просто текст"));
	assert.match(tg.last("sendMessage").text, /не анимированный/);
	assert.equal(await env.SUBS.get("emoji"), null);
});

test("if Telegram refuses custom emoji the message is re-sent plain and the refusal is shown to the admin", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("emoji", JSON.stringify({ "🛒": "901" }));
	tg.failNext("sendMessage", "Bad Request: DOCUMENT_INVALID custom emoji", 400);
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	const attempts = tg.sent("sendMessage");
	assert.equal(attempts.length, 2);
	assert.ok(buttons(attempts[0]).some((b) => b.icon_custom_emoji_id));
	assert.ok(buttons(attempts[1]).every((b) => !b.icon_custom_emoji_id), "retry is plain");
	assert.ok(buttons(attempts[1]).some((b) => b.text.startsWith("🛒")));
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, "a:em"));
	assert.match(tg.last("editMessageText").text, /Последний отказ Telegram/);
});

test("admin can reset and remove emoji", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await setPassword(env, "test-pass-7");
	await env.SUBS.put("emoji", JSON.stringify({ "⭐": "1", "🛒": "2" }));
	await setPassword(env, "test-pass-7");
	await handleUpdate(env, tg, press(ADMIN, "a:emd:0"));
	await handleUpdate(env, tg, msg(ADMIN, "test-pass-7"));
	assert.deepEqual(JSON.parse(await env.SUBS.get("emoji")), { "🛒": "2" });
	await handleUpdate(env, tg, press(ADMIN, "a:emr"));
	await handleUpdate(env, tg, msg(ADMIN, "test-pass-7"));
	assert.deepEqual(JSON.parse(await env.SUBS.get("emoji")), {});
});

test("banner: admin uploads a photo; the menu then goes out as a photo with the text as caption", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:ims:menu"));
	await handleUpdate(env, tg, msg(ADMIN, undefined, { text: undefined, photo: [{ file_id: "small" }, { file_id: "BIG" }] }));
	assert.deepEqual(JSON.parse(await env.SUBS.get("banners")).menu, { type: "photo", fileId: "BIG" });

	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	const photo = tg.last("sendPhoto");
	assert.equal(photo.photo, "BIG");
	assert.match(photo.caption, /PampGram/);
	assert.ok(buttons(photo).some((b) => b.callback_data === "shop"));
	assert.equal(tg.sent("sendMessage").length, 0);
});

test("banner on a button press replaces the old message; the next text screen replaces the banner message", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("banners", JSON.stringify({ menu: { type: "animation", fileId: "GIF" } }));
	await handleUpdate(env, tg, press(ALICE, "menu"));
	assert.equal(tg.last("sendAnimation").animation, "GIF");
	assert.equal(tg.last("deleteMessage").message_id, 50);

	// editing a photo message fails in Telegram: the screen must still appear
	tg.reset();
	tg.failNext("editMessageText", "Bad Request: there is no text in the message to edit", 400);
	await handleUpdate(env, tg, press(ALICE, "privacy"));
	assert.equal(tg.last("deleteMessage").message_id, 50);
	assert.match(tg.last("sendMessage").text, /Какие данные собираются/);
});

test("a banner Telegram refuses falls back to the plain text screen; a long text goes out as a separate message", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("banners", JSON.stringify({ menu: { type: "photo", fileId: "BAD" } }));
	tg.failNext("sendPhoto", "Bad Request: wrong file identifier", 400);
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	assert.match(tg.last("sendMessage").text, /PampGram/);

	tg.reset();
	await env.SUBS.put("cfg", JSON.stringify({ welcome: "Длинный текст ".repeat(100) }));
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	assert.equal(tg.sent("sendPhoto").length, 1);
	assert.equal(tg.last("sendPhoto").caption, undefined);
	assert.match(tg.last("sendMessage").text, /Длинный текст/);
});

test("banner can be removed; non-photo files are refused", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await setPassword(env, "test-pass-7");
	await env.SUBS.put("banners", JSON.stringify({ shop: { type: "photo", fileId: "X" } }));
	await handleUpdate(env, tg, press(ADMIN, "a:ims:menu"));
	await handleUpdate(env, tg, msg(ADMIN, "привет"));
	assert.match(tg.last("sendMessage").text, /Это не картинка/);
	await handleUpdate(env, tg, press(ADMIN, "a:imd:shop"));
	await handleUpdate(env, tg, msg(ADMIN, "test-pass-7"));
	assert.deepEqual(JSON.parse(await env.SUBS.get("banners")), {});
});
