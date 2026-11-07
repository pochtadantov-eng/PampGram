import test from "node:test";
import assert from "node:assert/strict";
import { handleUpdate } from "../src/bot/main.js";
import { setPassword, hashPassword, verifyPassword } from "../src/bot/security.js";
import { makeBackup, listBackups } from "../src/bot/backup.js";
import { labelOf, splitLabel, normalizeUrl } from "../src/bot/buttons.js";
import { createEnv, createTelegram } from "./helpers.js";

const ADMIN = { id: 1000, first_name: "Owner", username: "owner" };
const ALICE = { id: 2001, first_name: "Alice", username: "alice" };
let seq = 0;
const msg = (from, text, extra = {}) => ({ message: { message_id: ++seq, from, chat: { id: from.id, type: "private" }, text, ...extra } });
const press = (from, data) => ({ callback_query: { id: `cb${++seq}`, from, data, message: { message_id: 50, chat: { id: from.id, type: "private" } } } });
const flat = (params) => params.reply_markup.inline_keyboard.flat();
const PW = "test-pass-7";
const lastText = (tg) => (tg.last("editMessageText") ?? tg.last("sendMessage")).text;

async function addButton(env, tg, section, name, type, content) {
	await handleUpdate(env, tg, press(ADMIN, `a:bta:${section}`));
	await handleUpdate(env, tg, msg(ADMIN, name));
	await handleUpdate(env, tg, press(ADMIN, `a:btt:${section}:${type}`));
	await handleUpdate(env, tg, msg(ADMIN, content));
	return JSON.parse(await env.SUBS.get("buttons")).custom.at(-1);
}

test("helpers: label split, override and url normalisation", () => {
	assert.deepEqual(splitLabel("🛒 Купить доступ"), { emoji: "🛒", rest: "Купить доступ" });
	assert.deepEqual(splitLabel("Просто текст"), { emoji: "", rest: "Просто текст" });
	assert.equal(labelOf("🛒 Купить доступ", { emoji: "🔥" }), "🔥 Купить доступ");
	assert.equal(labelOf("🛒 Купить доступ", { text: "Магазин" }), "🛒 Магазин");
	assert.equal(labelOf("🛒 Купить доступ", { emoji: "" }), "Купить доступ");
	assert.equal(normalizeUrl("@pampgram"), "https://t.me/pampgram");
	assert.equal(normalizeUrl("t.me/pampgram"), "https://t.me/pampgram");
	assert.equal(normalizeUrl("https://example.com/x"), "https://example.com/x");
	assert.equal(normalizeUrl("javascript:alert(1)"), null);
	assert.equal(normalizeUrl("просто слова"), null);
});

test("admin adds a link button and a page button; customers see them, the page opens", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const link = await addButton(env, tg, "menu", "🎁 Отзывы", "link", "@pampgram_reviews");
	assert.equal(link.url, "https://t.me/pampgram_reviews");
	assert.equal(link.emoji, "🎁");
	assert.equal(link.text, "Отзывы");
	const page = await addButton(env, tg, "menu", "FAQ", "page", "Ответы на частые вопросы");

	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	const buttons = flat(tg.last("sendMessage"));
	const reviews = buttons.find((b) => b.text === "🎁 Отзывы");
	assert.equal(reviews.url, "https://t.me/pampgram_reviews");
	const faq = buttons.find((b) => b.text === "FAQ");
	assert.equal(faq.callback_data, `cb:${page.id}`);

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `cb:${page.id}`));
	assert.match(tg.last("editMessageText").text, /Ответы на частые вопросы/);
});

test("custom buttons go before the admin row for the admin and also work in the tariff list", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await addButton(env, tg, "shop", "Помощь", "link", "https://example.com/help");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	const rows = tg.last("editMessageText").reply_markup.inline_keyboard;
	assert.equal(rows.at(-1)[0].callback_data, "menu", "back stays last");
	assert.equal(rows.at(-2)[0].url, "https://example.com/help");

	await addButton(env, tg, "menu", "Новая", "page", "текст");
	tg.reset();
	await handleUpdate(env, tg, msg(ADMIN, "/start"));
	const menu = tg.last("sendMessage").reply_markup.inline_keyboard;
	assert.equal(menu.at(-1)[0].callback_data, "a:home", "admin button stays last");
});

test("admin renames a built-in button, changes its emoji (plain and animated) and hides another", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:btn:menu:shop"));
	await handleUpdate(env, tg, msg(ADMIN, "Магазин"));
	await handleUpdate(env, tg, press(ADMIN, "a:btm:menu:shop"));
	await handleUpdate(env, tg, msg(ADMIN, "🔥"));
	await handleUpdate(env, tg, press(ADMIN, "a:btv:menu:privacy"));
	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	let buttons = flat(tg.last("sendMessage"));
	assert.ok(buttons.some((b) => b.callback_data === "shop" && b.text === "🔥 Магазин"));
	assert.ok(!buttons.some((b) => b.callback_data === "privacy"), "hidden");

	// animated emoji on that button
	await handleUpdate(env, tg, press(ADMIN, "a:btm:menu:shop"));
	await handleUpdate(env, tg, msg(ADMIN, "💥", { entities: [{ type: "custom_emoji", offset: 0, length: 2, custom_emoji_id: "777" }] }));
	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	buttons = flat(tg.last("sendMessage"));
	const shop = buttons.find((b) => b.callback_data === "shop");
	assert.equal(shop.icon_custom_emoji_id, "777");
	assert.equal(shop.text, "Магазин");
	assert.ok(buttons.every((b) => !("_icon" in b)), "private marker never reaches Telegram");

	// Telegram refuses -> plain retry keeps the emoji in the text
	tg.reset();
	tg.failNext("sendMessage", "Bad Request: custom emoji can't be used", 400);
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	const retry = tg.sent("sendMessage")[1];
	const plain = flat(retry).find((b) => b.callback_data === "shop");
	assert.equal(plain.text, "💥 Магазин");
	assert.ok(!plain.icon_custom_emoji_id);
});

test("moving and editing a custom button; invalid link is refused", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const a = await addButton(env, tg, "menu", "A", "page", "a");
	const b = await addButton(env, tg, "menu", "B", "page", "b");
	await handleUpdate(env, tg, press(ADMIN, `a:btu:menu:${b.id}`));
	assert.deepEqual(JSON.parse(await env.SUBS.get("buttons")).custom.map((x) => x.text), ["B", "A"]);
	await handleUpdate(env, tg, press(ADMIN, `a:btc:menu:${a.id}`));
	await handleUpdate(env, tg, msg(ADMIN, "новый текст"));
	assert.equal(JSON.parse(await env.SUBS.get("buttons")).custom.find((x) => x.id === a.id).page, "новый текст");

	await handleUpdate(env, tg, press(ADMIN, "a:bta:menu"));
	await handleUpdate(env, tg, msg(ADMIN, "Ссылка"));
	await handleUpdate(env, tg, press(ADMIN, "a:btt:menu:link"));
	tg.reset();
	await handleUpdate(env, tg, msg(ADMIN, "не ссылка"));
	assert.match(tg.last("sendMessage").text, /Это не ссылка/);
});

test("deleting a custom button needs the password; a wrong one does nothing", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await setPassword(env, PW);
	const item = await addButton(env, tg, "menu", "Удалить меня", "page", "x");
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, `a:btx:menu:${item.id}`));
	assert.match(lastText(tg), /Введите пароль/);
	assert.equal(JSON.parse(await env.SUBS.get("buttons")).custom.length, 1, "not deleted yet");

	const wrong = msg(ADMIN, "0000");
	await handleUpdate(env, tg, wrong);
	assert.equal(tg.last("deleteMessage").message_id, wrong.message.message_id, "the password message is erased");
	assert.match(tg.last("sendMessage").text, /Неверный пароль/);
	assert.equal(JSON.parse(await env.SUBS.get("buttons")).custom.length, 1);

	await handleUpdate(env, tg, msg(ADMIN, PW));
	assert.equal(JSON.parse(await env.SUBS.get("buttons")).custom.length, 0, "deleted after the right password");
});

test("a non-admin can never trigger a guarded action", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await setPassword(env, PW);
	await env.SUBS.put("emoji", JSON.stringify({ "⭐": "1" }));
	await handleUpdate(env, tg, press(ALICE, "a:emr"));
	await handleUpdate(env, tg, msg(ALICE, PW));
	assert.deepEqual(JSON.parse(await env.SUBS.get("emoji")), { "⭐": "1" });
});

test("five wrong passwords lock the prompt; even the right one is then refused until it expires", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await setPassword(env, PW);
	await env.SUBS.put("emoji", JSON.stringify({ "⭐": "1" }));
	await handleUpdate(env, tg, press(ADMIN, "a:emr"));
	for (let i = 0; i < 5; i++) {
		await handleUpdate(env, tg, msg(ADMIN, `bad${i}`));
	}
	assert.match(tg.last("sendMessage").text, /заблокирован/);
	await handleUpdate(env, tg, msg(ADMIN, PW));
	assert.match(tg.last("sendMessage").text, /Слишком много/);
	assert.deepEqual(JSON.parse(await env.SUBS.get("emoji")), { "⭐": "1" });
	assert.equal(await verifyPassword(env, PW, Date.now() + 11 * 60 * 1000), true, "unlocked after 10 minutes");
});

test("without a password set, deletion is refused and the admin is told how to set one", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("emoji", JSON.stringify({ "⭐": "1" }));
	await handleUpdate(env, tg, press(ADMIN, "a:emr"));
	assert.match(lastText(tg), /Пароль .* не задан/);
	assert.deepEqual(JSON.parse(await env.SUBS.get("emoji")), { "⭐": "1" });
});

test("password can be set and changed from the panel; only a salted hash is stored", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:pw"));
	await handleUpdate(env, tg, msg(ADMIN, "abc"));
	assert.match(tg.last("sendMessage").text, /от 4/);
	await handleUpdate(env, tg, msg(ADMIN, "first-pass"));
	const stored = JSON.parse(await env.SUBS.get("pw"));
	assert.ok(stored.salt && stored.hash && !JSON.stringify(stored).includes("first-pass"));
	assert.equal(await verifyPassword(env, "first-pass"), true);

	await handleUpdate(env, tg, press(ADMIN, "a:pw"));
	await handleUpdate(env, tg, msg(ADMIN, "nope"));
	await handleUpdate(env, tg, msg(ADMIN, "second-pass"));
	assert.equal(await verifyPassword(env, "second-pass"), false, "old password was wrong, nothing changed");
	await handleUpdate(env, tg, msg(ADMIN, "first-pass"));
	await handleUpdate(env, tg, msg(ADMIN, "second-pass"));
	assert.equal(await verifyPassword(env, "second-pass"), true);
	assert.deepEqual(await hashPassword("x", "s"), await hashPassword("x", "s"));
});

test("every confirmed deletion first takes a backup, and the backup can be restored with the password", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await setPassword(env, PW);
	await env.SUBS.put("tariffs", JSON.stringify([{ code: "keep", title: "Keep", tier: "pro", stars: 9, hours: 0, active: true, requires: "" }]));
	await env.SUBS.put("emoji", JSON.stringify({ "⭐": "1" }));
	await handleUpdate(env, tg, press(ADMIN, "a:emr"));
	await handleUpdate(env, tg, msg(ADMIN, PW));
	assert.deepEqual(JSON.parse(await env.SUBS.get("emoji")), {});
	const backups = await listBackups(env);
	assert.equal(backups.length, 1);
	assert.match(backups[0].reason, /emr/);

	await handleUpdate(env, tg, press(ADMIN, `a:bkr:${backups[0].at}`));
	await handleUpdate(env, tg, msg(ADMIN, PW));
	assert.deepEqual(JSON.parse(await env.SUBS.get("emoji")), { "⭐": "1" }, "restored");
	assert.equal(JSON.parse(await env.SUBS.get("tariffs"))[0].code, "keep");
});

test("backups keep only the newest twelve and a manual one can be made", async () => {
	const env = createEnv();
	const tg = createTelegram();
	for (let i = 0; i < 15; i++) {
		await makeBackup(env, `r${i}`, 1000 + i);
	}
	assert.equal((await listBackups(env)).length, 12);
	await handleUpdate(env, tg, press(ADMIN, "a:bkn"));
	assert.equal((await listBackups(env)).length, 12);
	await handleUpdate(env, tg, press(ADMIN, "a:bk"));
	assert.match(tg.last("editMessageText").text, /Копии настроек/);
});

test("admin home lists the new sections", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:home"));
	const data = flat(tg.last("editMessageText")).map((b) => b.callback_data);
	for (const expected of ["a:bt", "a:bk", "a:pw", "a:em", "a:im", "a:p"]) {
		assert.ok(data.includes(expected), expected);
	}
});
