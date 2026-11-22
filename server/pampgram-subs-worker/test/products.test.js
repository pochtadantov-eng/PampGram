import test from "node:test";
import assert from "node:assert/strict";
import { handleUpdate } from "../src/bot/main.js";
import { setPassword } from "../src/bot/security.js";
import { findSellable } from "../src/bot/products.js";
import { createEnv, createTelegram } from "./helpers.js";

const ADMIN = { id: 1000, first_name: "Owner", username: "owner" };
const ALICE = { id: 2001, first_name: "Alice", username: "alice" };
let seq = 0;
const msg = (from, text, extra = {}) => ({ message: { message_id: ++seq, from, chat: { id: from.id, type: "private" }, text, ...extra } });
const press = (from, data) => ({ callback_query: { id: `cb${++seq}`, from, data, message: { message_id: 50, chat: { id: from.id, type: "private" } } } });
const preCheckout = (from, payload, amount) => ({ pre_checkout_query: { id: `pc${++seq}`, from, invoice_payload: payload, total_amount: amount, currency: "XTR" } });
const payment = (from, payload, amount, charge) => ({ message: { message_id: ++seq, from, chat: { id: from.id, type: "private" }, successful_payment: { currency: "XTR", total_amount: amount, invoice_payload: payload, telegram_payment_charge_id: charge } } });
const flat = (params) => params.reply_markup.inline_keyboard.flat();
const texts = (tg, chat) => tg.sent("sendMessage").filter((m) => String(m.chat_id) === String(chat)).map((m) => m.text).join("\n");

async function newSection(env, tg, name = "Сертификаты", description = "Выберите сертификат") {
	await handleUpdate(env, tg, press(ADMIN, "a:bta:menu"));
	await handleUpdate(env, tg, msg(ADMIN, name));
	await handleUpdate(env, tg, press(ADMIN, "a:btt:menu:shop"));
	await handleUpdate(env, tg, msg(ADMIN, description));
	return JSON.parse(await env.SUBS.get("buttons")).custom.at(-1);
}

async function newProduct(env, tg, section, line) {
	await handleUpdate(env, tg, press(ADMIN, `a:sxa:${section.id}`));
	await handleUpdate(env, tg, msg(ADMIN, line));
	return JSON.parse(await env.SUBS.get("products")).at(-1);
}

async function payStars(env, tg, user, code, charge) {
	tg.reset();
	await handleUpdate(env, tg, press(user, `buy:${code}`));
	const invoice = tg.last("sendInvoice");
	assert.ok(invoice, "invoice sent");
	await handleUpdate(env, tg, preCheckout(user, invoice.payload, invoice.prices[0].amount));
	assert.equal(tg.last("answerPreCheckoutQuery").ok, true);
	tg.reset();
	await handleUpdate(env, tg, payment(user, invoice.payload, invoice.prices[0].amount, charge));
	return invoice;
}

test("admin creates a shop-type section and a product; customers see it in the menu and open it", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const section = await newSection(env, tg);
	assert.equal(section.type, "shop");
	const product = await newProduct(env, tg, section, "Сертификат обычный | 700 | Ваш сертификат придёт скоро");
	assert.equal(product.stars, 700);
	assert.equal(product.give, "Ваш сертификат придёт скоро");

	tg.reset();
	await handleUpdate(env, tg, msg(ALICE, "/start"));
	const entry = flat(tg.last("sendMessage")).find((b) => b.callback_data === `cb:${section.id}`);
	assert.equal(entry.text, "Сертификаты");

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `cb:${section.id}`));
	const screen = tg.last("editMessageText");
	assert.match(screen.text, /Сертификаты/);
	assert.match(screen.text, /Выберите сертификат/);
	const item = flat(screen).find((b) => b.callback_data === `sp:${product.id}`);
	assert.equal(item.text, "Сертификат обычный — 700 ⭐");
	assert.equal(flat(screen).at(-1).callback_data, "menu");

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `sp:${product.id}`));
	const card = tg.last("editMessageText");
	assert.match(card.text, /Цена: 700/);
	assert.ok(flat(card).some((b) => b.callback_data === `buy:p_${product.id}`));
	assert.equal(flat(card).at(-1).callback_data, `cb:${section.id}`);
});

test("paying a product with Stars delivers the owner's text, issues no key and counts as a purchase", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const section = await newSection(env, tg);
	const product = await newProduct(env, tg, section, "Сертификат обычный | 700 | Ваш сертификат придёт скоро");
	const invoice = await payStars(env, tg, ALICE, `p_${product.id}`, "charge-1");
	assert.equal(invoice.prices[0].amount, 700);
	assert.match(texts(tg, ALICE.id), /Оплата получена/);
	assert.match(texts(tg, ALICE.id), /Ваш сертификат придёт скоро/);
	assert.ok(![...env.SUBS.map.keys()].some((key) => key.startsWith("key:")), "no activation key");
	const order = JSON.parse(env.SUBS.map.get([...env.SUBS.map.keys()].find((key) => key.startsWith("order:"))).value);
	assert.equal(order.kind, "item");
	assert.equal(order.status, "delivered");
	assert.match(texts(tg, ADMIN.id), /Новая оплата/);

	// repeated notification is applied once
	tg.reset();
	await handleUpdate(env, tg, payment(ALICE, invoice.payload, 700, "charge-1"));
	assert.equal(tg.sent("sendMessage").length, 0);

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "my"));
	assert.match(tg.last("editMessageText").text, /Сертификат обычный/);
	assert.match(tg.last("editMessageText").text, /выдано/);
});

test("a product without delivery text is handed over by hand: the buyer is told and the admin is notified", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const section = await newSection(env, tg);
	const product = await newProduct(env, tg, section, "Сертификат премиум | 1500");
	assert.equal(product.give, "");
	await payStars(env, tg, ALICE, `p_${product.id}`, "charge-2");
	assert.match(texts(tg, ALICE.id), /Администратор выдаст/);
	const alert = tg.sent("sendMessage").find((m) => String(m.chat_id) === "1000" && /Нужно выдать вручную/.test(m.text));
	assert.ok(alert);
	assert.ok(flat(alert).some((b) => b.callback_data === `a:dm:${ALICE.id}`));
	const order = JSON.parse(env.SUBS.map.get([...env.SUBS.map.keys()].find((key) => key.startsWith("order:"))).value);
	assert.equal(order.status, "paid");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, "my"));
	assert.match(tg.last("editMessageText").text, /ждёт выдачи/);
});

test("each section has its own payment methods", async () => {
	const env = createEnv();
	const tg = createTelegram();
	// a manual method
	await handleUpdate(env, tg, press(ADMIN, "a:pa"));
	await handleUpdate(env, tg, msg(ADMIN, "Карта"));
	await handleUpdate(env, tg, msg(ADMIN, "Карта: 2200 0000"));
	await handleUpdate(env, tg, msg(ADMIN, "2 ₽"));
	const card = JSON.parse(await env.SUBS.get("pay")).find((m) => m.kind === "manual");

	const certs = await newSection(env, tg, "Сертификаты");
	const other = await newSection(env, tg, "Другое");
	const p1 = await newProduct(env, tg, certs, "Сертификат | 700 | ок");
	const p2 = await newProduct(env, tg, other, "Вещь | 100 | ок");

	const buttonsOf = async (pid) => {
		tg.reset();
		await handleUpdate(env, tg, press(ALICE, `sp:${pid}`));
		return flat(tg.last("editMessageText")).map((b) => b.callback_data);
	};
	// default: both methods everywhere
	assert.ok((await buttonsOf(p1.id)).includes(`pay:p_${p1.id}:${card.id}`));
	assert.ok((await buttonsOf(p1.id)).includes(`buy:p_${p1.id}`));

	// certificates: card only
	await handleUpdate(env, tg, press(ADMIN, `a:sxy:${certs.id}`));
	await handleUpdate(env, tg, press(ADMIN, `a:sxz:${certs.id}:stars`));
	const onlyCard = await buttonsOf(p1.id);
	assert.ok(onlyCard.includes(`pay:p_${p1.id}:${card.id}`));
	assert.ok(!onlyCard.includes(`buy:p_${p1.id}`), "Stars switched off for this section");
	// the other section is untouched
	assert.ok((await buttonsOf(p2.id)).includes(`buy:p_${p2.id}`));
	// the price in the card's currency is converted from stars
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `sp:${p1.id}`));
	assert.ok(flat(tg.last("editMessageText")).some((b) => /1400 ₽/.test(b.text)));

	// back to "all"
	await handleUpdate(env, tg, press(ADMIN, `a:sxz:${certs.id}:all`));
	assert.ok((await buttonsOf(p1.id)).includes(`buy:p_${p1.id}`));
});

test("a product bought with a manual method is confirmed by the admin and then delivered", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:pa"));
	await handleUpdate(env, tg, msg(ADMIN, "Карта"));
	await handleUpdate(env, tg, msg(ADMIN, "Карта: 2200 0000"));
	await handleUpdate(env, tg, msg(ADMIN, "2 ₽"));
	const card = JSON.parse(await env.SUBS.get("pay")).find((m) => m.kind === "manual");
	const section = await newSection(env, tg);
	const product = await newProduct(env, tg, section, "Сертификат | 700 | Держите файлы");

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `pay:p_${product.id}:${card.id}`));
	assert.match(tg.last("editMessageText").text, /К оплате: <b>1400 ₽<\/b>/);
	assert.match(tg.last("editMessageText").text, /получите товар/);
	const orderKey = [...env.SUBS.map.keys()].find((key) => key.startsWith("order:"));
	const orderId = orderKey.slice(6);
	await handleUpdate(env, tg, press(ALICE, `pd:${orderId}`));
	assert.match(texts(tg, ADMIN.id), /Сертификат — <b>1400 ₽<\/b>/);
	await handleUpdate(env, tg, press(ADMIN, `a:po:${orderId}`));
	assert.match(tg.last("editMessageText").text, /Сертификат · товар/);
	tg.reset();
	await handleUpdate(env, tg, press(ADMIN, `a:pc:${orderId}`));
	assert.match(texts(tg, ALICE.id), /Держите файлы/);
	assert.equal(JSON.parse(env.SUBS.map.get(orderKey).value).status, "delivered");
});

test("inactive, deleted or unknown products cannot be bought", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const section = await newSection(env, tg);
	const product = await newProduct(env, tg, section, "Сертификат | 700 | ок");
	await handleUpdate(env, tg, press(ADMIN, `a:sxt:${product.id}`));
	assert.equal(await findSellable(env, `p_${product.id}`), null);
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `buy:p_${product.id}`));
	assert.equal(tg.sent("sendInvoice").length, 0);
	await handleUpdate(env, tg, press(ALICE, "buy:p_nothere"));
	assert.equal(tg.sent("sendInvoice").length, 0);
	await handleUpdate(env, tg, press(ALICE, `sp:${product.id}`));
	assert.match(tg.last("answerCallbackQuery").text, /недоступен/);
});

test("editing a product: name, price, description, delivery, emoji; invalid price is refused", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const section = await newSection(env, tg);
	const product = await newProduct(env, tg, section, "Старое | 100");
	const edit = async (action, text, extra) => {
		await handleUpdate(env, tg, press(ADMIN, `a:${action}:${product.id}`));
		await handleUpdate(env, tg, msg(ADMIN, text, extra));
	};
	await edit("sxn", "Новое имя");
	await edit("sxp", "900");
	await edit("sxd", "Описание товара");
	await edit("sxg", "Выдача тут");
	await edit("sxm", "🔥");
	let stored = JSON.parse(await env.SUBS.get("products"))[0];
	assert.deepEqual([stored.title, stored.stars, stored.desc, stored.give, stored.emoji], ["Новое имя", 900, "Описание товара", "Выдача тут", "🔥"]);
	await handleUpdate(env, tg, press(ADMIN, `a:sxp:${product.id}`));
	await handleUpdate(env, tg, msg(ADMIN, "много"));
	assert.match(tg.last("sendMessage").text, /целое число/);
	assert.equal(JSON.parse(await env.SUBS.get("products"))[0].stars, 900);
	await edit("sxg", "-");
	assert.equal(JSON.parse(await env.SUBS.get("products"))[0].give, "");

	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `cb:${section.id}`));
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.text === "🔥 Новое имя — 900 ⭐"));
	// animated emoji on the product button
	await edit("sxm", "💥", { entities: [{ type: "custom_emoji", offset: 0, length: 2, custom_emoji_id: "321" }] });
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `cb:${section.id}`));
	const button = flat(tg.last("editMessageText")).find((b) => b.callback_data === `sp:${product.id}`);
	assert.equal(button.icon_custom_emoji_id, "321");
});

test("deleting a product needs the password", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await setPassword(env, "test-pass-7");
	const section = await newSection(env, tg);
	const product = await newProduct(env, tg, section, "Сертификат | 700");
	await handleUpdate(env, tg, press(ADMIN, `a:sxx:${product.id}`));
	assert.equal(JSON.parse(await env.SUBS.get("products")).length, 1);
	await handleUpdate(env, tg, msg(ADMIN, "test-pass-7"));
	assert.equal(JSON.parse(await env.SUBS.get("products")).length, 0);
});

test("an existing text page can be turned into a shop section, keeping its description", async () => {
	const env = createEnv();
	const tg = createTelegram();
	await handleUpdate(env, tg, press(ADMIN, "a:bta:menu"));
	await handleUpdate(env, tg, msg(ADMIN, "Сертификаты"));
	await handleUpdate(env, tg, press(ADMIN, "a:btt:menu:page"));
	await handleUpdate(env, tg, msg(ADMIN, "Сертификат обычный 700зв"));
	const page = JSON.parse(await env.SUBS.get("buttons")).custom.at(-1);
	assert.equal(page.type, "page");
	await handleUpdate(env, tg, press(ADMIN, `a:bte:menu:${page.id}`));
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.callback_data === `a:btk:menu:${page.id}`), "type button on the card");
	await handleUpdate(env, tg, press(ADMIN, `a:btk:menu:${page.id}`));
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.callback_data === `a:btk:menu:${page.id}:shop`), "type chooser");
	await handleUpdate(env, tg, press(ADMIN, `a:btk:menu:${page.id}:shop`));
	const shop = JSON.parse(await env.SUBS.get("buttons")).custom.at(-1);
	assert.equal(shop.type, "shop");
	assert.equal(shop.page, "Сертификат обычный 700зв");
	assert.ok(flat(tg.last("editMessageText")).some((b) => b.callback_data === `a:sxl:${page.id}`));
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `cb:${page.id}`));
	assert.match(tg.last("editMessageText").text, /Сертификат обычный 700зв/);
	assert.match(tg.last("editMessageText").text, /Товаров пока нет/);
});

test("hiding a shop section hides its products too; invalid product line is refused", async () => {
	const env = createEnv();
	const tg = createTelegram();
	const section = await newSection(env, tg);
	await handleUpdate(env, tg, press(ADMIN, `a:sxa:${section.id}`));
	await handleUpdate(env, tg, msg(ADMIN, "без цены"));
	assert.match(tg.last("sendMessage").text, /Формат/);
	await handleUpdate(env, tg, msg(ADMIN, "Товар | -5"));
	assert.match(tg.last("sendMessage").text, /Формат/);
	const product = await newProduct(env, tg, section, "Товар | 10 | ок");
	await handleUpdate(env, tg, press(ADMIN, `a:btv:menu:${section.id}`));
	assert.equal(await findSellable(env, `p_${product.id}`), null, "a hidden section sells nothing");
	tg.reset();
	await handleUpdate(env, tg, press(ALICE, `cb:${section.id}`));
	assert.match(tg.last("answerCallbackQuery").text, /недоступен/);
});
