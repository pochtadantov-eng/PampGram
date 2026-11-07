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
	assert.match(tg.last("editMessageText").text, /^<b>FAQ<\/b>/, "title is the name only, no emoji");
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
	const order = JSON.parse(await env.SUBS.get("buttons")).layout.menu.map((x) => x.k);
	assert.ok(order.indexOf(b.id) < order.indexOf(a.id), "B is now above A");
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

const menuRows = async (env, tg, user = ALICE) => {
	tg.reset();
	await handleUpdate(env, tg, msg(user, "/start"));
	return (tg.last("sendMessage") ?? tg.last("sendPhoto")).reply_markup.inline_keyboard.map((row) => row.map((b) => b.callback_data ?? b.url ?? b.text));
};

test("default menu layout is unchanged: shop alone, purchases + files together, privacy alone", async () => {
	const env = createEnv();
	const tg = createTelegram();
	assert.deepEqual(await menuRows(env, tg), [["shop"], ["my", "dl"], ["privacy"]]);
});

test("privacy and support can be put side by side (left / right)", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("cfg", JSON.stringify({ support: "@helper" }));
	assert.deepEqual(await menuRows(env, tg), [["shop"], ["my", "dl"], ["privacy"], ["https://t.me/helper"]]);
	await handleUpdate(env, tg, press(ADMIN, "a:btj:menu:support"));
	assert.deepEqual(await menuRows(env, tg), [["shop"], ["my", "dl"], ["privacy", "https://t.me/helper"]]);
	// back to its own row
	await handleUpdate(env, tg, press(ADMIN, "a:btj:menu:support"));
	assert.deepEqual(await menuRows(env, tg), [["shop"], ["my", "dl"], ["privacy"], ["https://t.me/helper"]]);
});

test("the first button cannot join a previous row, and a row holds at most three", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:btj:menu:shop"));
	assert.match(tg.last("answerCallbackQuery").text, /Первую кнопку/);
	// shop + my + dl = three in a row, the fourth (privacy) is refused
	await handleUpdate(env, tg, press(ADMIN, "a:btj:menu:my"));
	assert.deepEqual(await menuRows(env, tg), [["shop", "my", "dl"], ["privacy"]]);
	await handleUpdate(env, tg, press(ADMIN, "a:btj:menu:privacy"));
	assert.match(tg.last("answerCallbackQuery").text, /не больше 3/);
	assert.deepEqual(await menuRows(env, tg), [["shop", "my", "dl"], ["privacy"]]);
});

test("moving buttons up and down reorders the menu, hidden ones are skipped but keep their place", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:btd:menu:shop"));
	assert.deepEqual(await menuRows(env, tg), [["my"], ["shop", "dl"], ["privacy"]].map((r) => r), "shop swapped with my; dl keeps its join");
	await handleUpdate(env, tg, press(ADMIN, "a:btu:menu:privacy"));
	await handleUpdate(env, tg, press(ADMIN, "a:btv:menu:dl"));
	const rows = await menuRows(env, tg);
	assert.ok(!rows.flat().includes("dl"));
	// moving past the ends does nothing
	await handleUpdate(env, tg, press(ADMIN, "a:btu:menu:my"));
	await handleUpdate(env, tg, press(ADMIN, "a:btu:menu:my"));
	assert.equal((await menuRows(env, tg)).flat()[0], "my");
});

test("custom buttons take part in the same ordering and can be placed beside built-in ones", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const reviews = await addButton(env, tg, "menu", "Отзывы", "link", "@rev");
	const faq = await addButton(env, tg, "menu", "FAQ", "page", "текст");
	await handleUpdate(env, tg, press(ADMIN, `a:btj:menu:${faq.id}`));
	assert.deepEqual((await menuRows(env, tg)).slice(-2), [["privacy"], ["https://t.me/rev", `cb:${faq.id}`]]);
	// move reviews to the very top
	for (let i = 0; i < 5; i++) {
		await handleUpdate(env, tg, press(ADMIN, `a:btu:menu:${reviews.id}`));
	}
	assert.equal((await menuRows(env, tg))[0][0], "https://t.me/rev");
});

test("admin and back rows stay last; tariff rows stay on top in the shop section", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const own = await addButton(env, tg, "shop", "Помощь", "link", "https://example.com");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	const rows = tg.last("editMessageText").reply_markup.inline_keyboard;
	assert.match(rows[0][0].callback_data, /^t:/);
	assert.equal(rows.at(-1)[0].callback_data, "menu");
	assert.equal(rows.at(-2)[0].url, "https://example.com");
	const admin = await menuRows(env, tg, ADMIN);
	assert.equal(admin.at(-1)[0], "a:home");
	assert.ok(own.id);
});

test("the section screen shows a preview of the rows and the button card shows its place", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:bt:menu"));
	const text = tg.last("editMessageText").text;
	assert.match(text, /Как видят покупатели/);
	assert.match(text, /Мои покупки\s+┃\s+📥 Скачать файлы|Мои покупки\s+┃\s+Скачать файлы/);
	await handleUpdate(env, tg, press(ADMIN, "a:bte:menu:dl"));
	assert.match(tg.last("editMessageText").text, /в одной строке с предыдущей/);
	const data = tg.last("editMessageText").reply_markup.inline_keyboard.flat().map((b) => b.callback_data);
	assert.ok(data.includes("a:btu:menu:dl") && data.includes("a:btd:menu:dl") && data.includes("a:btj:menu:dl"));
});

test("a tariff can get its own emoji (plain or animated) shown on its button and card", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:t:std"));
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.callback_data === "a:te:std"));
	await handleUpdate(env, tg, press(ADMIN, "a:te:std"));
	await handleUpdate(env, tg, msg(ADMIN, "🔥"));
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.callback_data === "t:std" && b.text.startsWith("🔥 Standard")));

	await handleUpdate(env, tg, press(ADMIN, "a:te:std"));
	await handleUpdate(env, tg, msg(ADMIN, "💥", { entities: [{ type: "custom_emoji", offset: 0, length: 2, custom_emoji_id: "555" }] }));
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	const button = flat(tg.last("editMessageText")).find((b) => b.callback_data === "t:std");
	assert.equal(button.icon_custom_emoji_id, "555");
	assert.match(button.text, /^Standard — 200/);
	assert.ok(!("_icon" in button));
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "t:std"));
	assert.doesNotMatch(tg.last("editMessageText").text, /💥/, "the emoji stays on the button only");

	await handleUpdate(env, tg, press(ADMIN, "a:te:std"));
	await handleUpdate(env, tg, msg(ADMIN, "-"));
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.callback_data === "t:std" && b.text.startsWith("Standard")));
});

test("star position: at the end by default, at the front (so it can be animated) when switched", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("emoji", JSON.stringify({ "⭐": "888" }));
	const shopLabels = async () => {
		tg.reset();
		await handleUpdate(env, tg, press(ALICE, "shop"));
		return flat(tg.last("editMessageText")).filter((b) => b.callback_data?.startsWith("t:"));
	};
	assert.ok((await shopLabels()).every((b) => b.text.endsWith(" ⭐")), "default: star at the end");

	await handleUpdate(env, tg, press(ADMIN, "a:cs"));
	assert.equal(JSON.parse(await env.SUBS.get("cfg")).starFront, true);
	const front = await shopLabels();
	assert.ok(front.every((b) => !b.text.includes("⭐") && b.icon_custom_emoji_id === "888"), JSON.stringify(front));
	assert.match(front[0].text, /^Standard — 200$/);

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "t:std"));
	const pay = flat(tg.last("editMessageText")).find((b) => b.callback_data === "buy:std");
	assert.equal(pay.icon_custom_emoji_id, "888");
	assert.ok(!pay.text.includes("⭐"));

	await handleUpdate(env, tg, press(ADMIN, "a:cs"));
	assert.equal(JSON.parse(await env.SUBS.get("cfg")).starFront, false);
});

test("a tariff's own emoji replaces the star in front mode", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await env.SUBS.put("cfg", JSON.stringify({ starFront: true }));
	await handleUpdate(env, tg, press(ADMIN, "a:te:std"));
	await handleUpdate(env, tg, msg(ADMIN, "🔥"));
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "shop"));
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.callback_data === "t:std" && b.text === "🔥 Standard — 200"));
});

const dataOf = (params) => flat(params).map((b) => b.callback_data);

test("every custom button gets the same full card, whatever its type", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const link = await addButton(env, tg, "menu", "Ссылка", "link", "https://example.com");
	const page = await addButton(env, tg, "menu", "Страница", "page", "текст");
	const shop = await addButton(env, tg, "menu", "Раздел", "shop", "описание");
	for (const [item, textButton] of [[link, "btc"], [page, "btc"], [shop, "btc"]]) {
		await handleUpdate(env, tg, press(ADMIN, `a:bte:menu:${item.id}`));
		const data = dataOf(tg.last("editMessageText"));
		for (const action of ["btn", "btm", "btv", "btu", "btd", "btj", "btk", textButton, "btx"]) {
			assert.ok(data.includes(`a:${action}:menu:${item.id}`), `${item.text}: ${action}`);
		}
		assert.ok(data.includes(`a:sxl:${item.id}`), `${item.text}: products entry`);
	}
});

test("a link or page button can be switched to a shop section in one tap, and back", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const link = await addButton(env, tg, "menu", "Ссылка", "link", "https://example.com");
	await handleUpdate(env, tg, press(ADMIN, `a:sxl:${link.id}`));
	assert.match(tg.last("editMessageText").text, /не раздел с товарами/);
	await handleUpdate(env, tg, press(ADMIN, `a:btk:menu:${link.id}:shop`));
	let stored = JSON.parse(await env.SUBS.get("buttons")).custom.find((x) => x.id === link.id);
	assert.equal(stored.type, "shop");
	assert.equal(stored.url, "https://example.com", "the old link is kept");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `cb:${link.id}`));
	assert.match(tg.last("editMessageText").text, /Товаров пока нет/);

	await handleUpdate(env, tg, press(ADMIN, `a:btk:menu:${link.id}:link`));
	stored = JSON.parse(await env.SUBS.get("buttons")).custom.find((x) => x.id === link.id);
	assert.equal(stored.type, "link");
	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	assert.ok(flat(tg.last("sendMessage")).some((b) => b.url === "https://example.com"));
});

test("switching to a type that needs content asks for it first", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const link = await addButton(env, tg, "menu", "Ссылка", "link", "https://example.com");
	await handleUpdate(env, tg, press(ADMIN, `a:btk:menu:${link.id}:page`));
	assert.match(tg.last("editMessageText").text, /Пришлите текст страницы/);
	assert.equal(JSON.parse(await env.SUBS.get("buttons")).custom[0].type, "link", "not switched yet");
	await handleUpdate(env, tg, msg(ADMIN, "Новый текст страницы"));
	const stored = JSON.parse(await env.SUBS.get("buttons")).custom[0];
	assert.equal(stored.type, "page");
	assert.equal(stored.page, "Новый текст страницы");
	assert.equal(stored.url, "https://example.com");
});

test("built-in buttons get shortcuts to where their content is edited", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const shortcuts = { shop: ["a:t", "a:tk:shop_intro", "a:im:shop"], my: ["a:tk:my_title"], dl: ["a:b"], privacy: ["a:tk:privacy"], support: ["a:cf:support"] };
	for (const [key, expected] of Object.entries(shortcuts)) {
		await handleUpdate(env, tg, press(ADMIN, `a:bte:menu:${key}`));
		const data = dataOf(tg.last("editMessageText"));
		for (const target of expected) {
			assert.ok(data.includes(target), `${key}: ${target}`);
		}
		for (const action of ["btn", "btm", "btv", "btu", "btd", "btj"]) {
			assert.ok(data.includes(`a:${action}:menu:${key}`), `${key}: ${action}`);
		}
	}
});

const preCheckout = (from, payload, amount) => ({ pre_checkout_query: { id: `pc${++seq}`, from, invoice_payload: payload, total_amount: amount, currency: "XTR" } });

test("the Stars invoice has a pay button first and a cancel button under it", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ALICE, "buy:std"));
	const invoice = tg.last("sendInvoice");
	const rows = invoice.reply_markup.inline_keyboard;
	assert.equal(rows[0][0].pay, true, "first button is the pay button");
	assert.match(rows[0][0].text, /Заплатить ⭐200/);
	assert.match(rows[1][0].callback_data, /^ix:/);
	assert.match(rows[1][0].text, /Отменить/);
});

test("cancelling an invoice cancels the order, removes the invoice and blocks late payment", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ALICE, "buy:std"));
	const invoice = tg.last("sendInvoice");
	const cancel = invoice.reply_markup.inline_keyboard[1][0].callback_data;
	const orderId = cancel.slice(3);
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, cancel));
	assert.equal(tg.last("deleteMessage").message_id, 50);
	assert.match(tg.last("sendMessage").text, /Оплата отменена/);
	assert.ok(flat(tg.last("sendMessage")).some((b) => b.callback_data === "shop"));
	assert.equal(JSON.parse(env.SUBS.map.get(`order:${orderId}`).value).status, "cancelled");

	// a stale pay tap is refused with a clear reason
	tg.reset();
	await handleUpdate(env, tg, preCheckout(ALICE, invoice.payload, 200));
	assert.equal(tg.last("answerPreCheckoutQuery").ok, false);
	assert.match(tg.last("answerPreCheckoutQuery").error_message, /отменён/);

	// pressing cancel twice is harmless
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, cancel));
	assert.match(tg.last("answerCallbackQuery").text, /уже отменена/);
});

test("only the buyer can cancel, and a paid order cannot be cancelled", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ALICE, "buy:std"));
	const invoice = tg.last("sendInvoice");
	const cancel = invoice.reply_markup.inline_keyboard[1][0].callback_data;
	const orderId = cancel.slice(3);
	tg.reset();
	await handleUpdate(env, tg, press({ id: 2002, first_name: "Bob" }, cancel));
	assert.match(tg.last("answerCallbackQuery").text, /не найден/);
	assert.equal(JSON.parse(env.SUBS.map.get(`order:${orderId}`).value).status, "pending");

	await handleUpdate(env, tg, preCheckout(ALICE, invoice.payload, 200));
	await handleUpdate(env, tg, { message: { message_id: ++seq, from: ALICE, chat: { id: ALICE.id, type: "private" }, successful_payment: { currency: "XTR", total_amount: 200, invoice_payload: invoice.payload, telegram_payment_charge_id: "paid-1" } } });
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, cancel));
	assert.match(tg.last("answerCallbackQuery").text, /уже оплачен/);
	assert.notEqual(JSON.parse(env.SUBS.map.get(`order:${orderId}`).value).status, "cancelled");
});

test("products get the same cancel button under their invoice", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const section = await addButton(env, tg, "menu", "Раздел", "shop", "описание");
	await handleUpdate(env, tg, press(ADMIN, `a:sxa:${section.id}`));
	await handleUpdate(env, tg, msg(ADMIN, "Сертификат | 700 | ок"));
	const product = JSON.parse(await env.SUBS.get("products"))[0];
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `buy:p_${product.id}`));
	const rows = tg.last("sendInvoice").reply_markup.inline_keyboard;
	assert.equal(rows[0][0].pay, true);
	assert.match(rows[0][0].text, /Заплатить ⭐700/);
	assert.match(rows[1][0].callback_data, /^ix:/);
});

test("if Telegram refuses the invoice with the cancel button, a plain invoice is sent instead", async () => {
	const env = createEnv();
	const tg = createTelegram();
	tg.failNext("sendInvoice", "Bad Request: invalid reply markup", 400);
	await handleUpdate(env, tg, press(ALICE, "buy:std"));
	const sent = tg.sent("sendInvoice");
	assert.equal(sent.length, 2);
	assert.ok(sent[0].reply_markup);
	assert.equal(sent[1].reply_markup, undefined);
	assert.equal(tg.sent("sendMessage").length, 0, "no error shown to the buyer");
});
