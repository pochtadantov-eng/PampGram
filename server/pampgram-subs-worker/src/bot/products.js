/**
 * Shop-type sections: a button the owner added that opens its own list of products, each with a price, its own
 * set of payment methods and its own delivery (a text, or "by hand": the admin is told to hand it over).
 *
 *   button (type "shop")  { id, section, text, emoji, icon, page (description), methods: [ids], customMethods }
 *   product               { id, section: <button id>, title, desc, stars, give, emoji, icon, active }
 *
 * Products are sold through the same order / payment / confirmation flow as tariffs; their sellable code is "p_<id>".
 */

import { show, say, toast } from "./context.js";
import { btn, kb, esc } from "./ui.js";
import { getButtons, saveButtons, getProducts, saveProducts, getConfig, getPayMethods, newId, setState, clearState } from "./store.js";
import { readEmoji } from "./buttonsadmin.js";
import { manualAmount, formatAmount, orderPrice } from "./pay.js";
import { banReason, notifyAdmins } from "./shop.js";
import { getText } from "./texts.js";

const CANCEL = kb([[btn("✖️ Отмена", "a:bt")]]);

export const productCode = (id) => `p_${id}`;

async function sectionOf(env, buttonId) {
	return (await getButtons(env)).custom.find((entry) => entry.id === buttonId && entry.type === "shop");
}

/** A product as the purchase flow sees it (same shape as a tariff), or null. */
export async function findSellable(env, code) {
	if (!String(code).startsWith("p_")) {
		return null;
	}
	const product = (await getProducts(env)).find((entry) => productCode(entry.id) === code && entry.active);
	const section = product ? await sectionOf(env, product.section) : null;
	if (!product || !section || section.hidden) {
		return null;
	}
	return { code, title: product.title, tier: null, hours: 0, stars: product.stars, desc: product.desc, kind: "item", pid: product.id, give: product.give ?? "", sectionId: product.section };
}

/** Payment methods this section accepts (all active ones unless the owner narrowed them). */
export async function allowedMethods(env, sectionId) {
	const section = await sectionOf(env, sectionId);
	const methods = (await getPayMethods(env)).filter((method) => method.active);
	return section?.customMethods ? methods.filter((method) => (section.methods ?? []).includes(method.id)) : methods;
}

// ---------- buyer side ----------

export async function showShopSection(ctx, button) {
	const products = (await getProducts(ctx.env)).filter((entry) => entry.section === button.id && entry.active);
	const starFront = Boolean((await getConfig(ctx.env)).starFront);
	const rows = products.map((entry) => [
		{ ...btn(`${entry.emoji ? `${entry.emoji} ` : ""}${entry.title} — ${entry.stars}${starFront ? "" : " ⭐"}`, `sp:${entry.id}`), ...(entry.icon && entry.emoji ? { _icon: entry.icon } : {}) },
	]);
	rows.push([btn("← Назад", button.section === "shop" ? "shop" : "menu")]);
	const text = `<b>${esc(button.text)}</b>\n${esc(button.page ?? "")}${products.length ? "" : `\n\n${await getText(ctx.env, "no_products")}`}`;
	return show(ctx, text, kb(rows));
}

export async function showProduct(ctx, pid) {
	if (await banReason(ctx.env, ctx.from.id)) {
		return toast(ctx, "Доступ ограничен", true);
	}
	const sellable = await findSellable(ctx.env, productCode(pid));
	if (!sellable) {
		return toast(ctx, "Этот товар недоступен", true);
	}
	await toast(ctx);
	const methods = await allowedMethods(ctx.env, sellable.sectionId);
	const starFront = Boolean((await getConfig(ctx.env)).starFront);
	const rows = methods.map((method) =>
		method.kind === "stars"
			? [btn(`⭐ ${method.title} — ${sellable.stars}${starFront ? "" : " ⭐"}`, `buy:${sellable.code}`)]
			: [btn(`💳 ${method.title} — ${formatAmount(manualAmount(method, sellable), method.currency)}`.slice(0, 60), `pay:${sellable.code}:${method.id}`)]
	);
	rows.push([btn("← Назад", `cb:${sellable.sectionId}`)]);
	const hint = `\n\n${await getText(ctx.env, methods.length === 0 ? "no_methods_section" : "choose_method")}`;
	return show(ctx, `<b>${esc(sellable.title)}</b>\n${esc(sellable.desc ?? "")}\n\nЦена: ${sellable.stars} ⭐${hint}`, kb(rows));
}

/** After payment: the owner's delivery text, or a note that the admin will hand the product over. */
export async function deliverProduct(ctx, order) {
	const head = `${await getText(ctx.env, "paid_title")}\n${esc(order.title)} — ${esc(orderPrice(order))}`;
	if (order.give) {
		await say(ctx, `${head}\n\n${esc(order.give)}`);
		return "delivered";
	}
	await say(ctx, `${head}\n\n${await getText(ctx.env, "item_hand")}`);
	await notifyAdmins(
		ctx,
		`📦 <b>Нужно выдать вручную</b>\n${esc(order.title)} — ${esc(orderPrice(order))}\nПокупатель: <code>${esc(order.userId)}</code>`,
		kb([[btn("✉️ Написать", `a:dm:${order.userId}`), btn("👤 Профиль", `a:u:${order.userId}`)]])
	);
	return "paid";
}

// ---------- admin side ----------

const productOf = async (env, pid) => (await getProducts(env)).find((entry) => entry.id === pid);

export async function showProductList(ctx, buttonId) {
	const section = await sectionOf(ctx.env, buttonId);
	if (!section) {
		return show(ctx, "Раздел не найден.", kb([[btn("← Кнопки", "a:bt")]]));
	}
	const products = (await getProducts(ctx.env)).filter((entry) => entry.section === buttonId);
	const rows = products.map((entry) => [btn(`${entry.active ? "✅" : "⏸"} ${entry.title} — ${entry.stars} ⭐`.slice(0, 60), `a:sxe:${entry.id}`)]);
	rows.push([btn("➕ Новый товар", `a:sxa:${buttonId}`)]);
	rows.push([btn("💳 Способы оплаты раздела", `a:sxy:${buttonId}`)]);
	rows.push([btn("← К кнопке", `a:bte:${section.section}:${buttonId}`)]);
	return show(ctx, `🛍 <b>Товары раздела «${esc(section.text)}»</b>\nЦена в ⭐. Для оплаты картой и кошельками цена пересчитывается по курсу способа.`, kb(rows));
}

export async function showProductCard(ctx, pid) {
	const product = await productOf(ctx.env, pid);
	if (!product) {
		return show(ctx, "Товар не найден.", kb([[btn("← Кнопки", "a:bt")]]));
	}
	const lines = [
		`🛍 <b>${esc(product.title)}</b> (<code>${esc(product.id)}</code>)`,
		esc(product.desc || "без описания"),
		`Цена: ${product.stars} ⭐`,
		`Выдача: ${product.give ? esc(product.give.slice(0, 200)) : "вручную (вам придёт уведомление)"}`,
		`Эмодзи на кнопке: ${product.emoji ? `${esc(product.emoji)}${product.icon ? " (анимированный)" : ""}` : "нет"}`,
		`Статус: ${product.active ? "продаётся" : "выключен"}`,
	];
	return show(
		ctx,
		lines.join("\n"),
		kb([
			[btn("✏️ Название", `a:sxn:${pid}`), btn("💲 Цена", `a:sxp:${pid}`)],
			[btn("📝 Описание", `a:sxd:${pid}`), btn("📦 Выдача", `a:sxg:${pid}`)],
			[btn("🙂 Эмодзи", `a:sxm:${pid}`), btn(product.active ? "⏸ Выключить" : "▶️ Включить", `a:sxt:${pid}`)],
			[btn("🗑 Удалить", `a:sxx:${pid}`), btn("← К товарам", `a:sxl:${product.section}`)],
		])
	);
}

async function showMethods(ctx, buttonId) {
	const section = await sectionOf(ctx.env, buttonId);
	if (!section) {
		return showProductList(ctx, buttonId);
	}
	const all = await getPayMethods(ctx.env);
	const allowed = (method) => (section.customMethods ? (section.methods ?? []).includes(method.id) : true);
	const rows = all.map((method) => [btn(`${allowed(method) ? "✅" : "⬜"} ${method.kind === "stars" ? "⭐" : "💳"} ${method.title}${method.active ? "" : " (выключен)"}`.slice(0, 60), `a:sxz:${buttonId}:${method.id}`)]);
	rows.push([btn("↩️ Все включённые способы", `a:sxz:${buttonId}:all`)]);
	rows.push([btn("← К товарам", `a:sxl:${buttonId}`)]);
	return show(
		ctx,
		`💳 <b>Оплата раздела «${esc(section.text)}»</b>\n${section.customMethods ? "Принимаются отмеченные ✅ способы." : "Сейчас принимаются все включённые способы."}\nСами способы и реквизиты — в «Оплата».`,
		kb(rows)
	);
}

/** Returns true when the callback belongs to this module. `parts` is the callback data without "a:". */
export async function productsCallback(ctx, parts) {
	const [action, arg, extra] = parts;
	switch (action) {
		case "sxl":
			await toast(ctx);
			await showProductList(ctx, arg);
			return true;
		case "sxe":
			await toast(ctx);
			await showProductCard(ctx, arg);
			return true;
		case "sxy":
			await toast(ctx);
			await showMethods(ctx, arg);
			return true;
		case "sxz": {
			const cfg = await getButtons(ctx.env);
			const section = cfg.custom.find((entry) => entry.id === arg && entry.type === "shop");
			if (section) {
				if (extra === "all") {
					section.customMethods = false;
					section.methods = [];
				} else {
					const ids = new Set(section.customMethods ? section.methods ?? [] : (await getPayMethods(ctx.env)).map((method) => method.id));
					ids.has(extra) ? ids.delete(extra) : ids.add(extra);
					section.customMethods = true;
					section.methods = [...ids];
				}
				await saveButtons(ctx.env, cfg);
			}
			await toast(ctx);
			await showMethods(ctx, arg);
			return true;
		}
		case "sxa":
			if (!(await sectionOf(ctx.env, arg))) {
				return true;
			}
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "sx_add", button: arg });
			await show(ctx, "Новый товар одной строкой:\n<code>название | цена ⭐ | текст выдачи (необязательно)</code>\nПример:\n<code>Сертификат обычный | 700 | Ваш сертификат придёт в течение часа</code>\nБез текста выдачи товар выдаётся вручную: вам придёт уведомление.", kb([[btn("✖️ Отмена", `a:sxl:${arg}`)]]));
			return true;
		case "sxt": {
			const products = await getProducts(ctx.env);
			const product = products.find((entry) => entry.id === arg);
			if (product) {
				product.active = !product.active;
				await saveProducts(ctx.env, products);
			}
			await toast(ctx);
			await showProductCard(ctx, arg);
			return true;
		}
		case "sxx": {
			const product = await productOf(ctx.env, arg);
			await saveProducts(ctx.env, (await getProducts(ctx.env)).filter((entry) => entry.id !== arg));
			await toast(ctx, "Удалено");
			await showProductList(ctx, product?.section);
			return true;
		}
		case "sxn":
		case "sxp":
		case "sxd":
		case "sxg":
		case "sxm": {
			await toast(ctx);
			const field = { sxn: "title", sxp: "stars", sxd: "desc", sxg: "give", sxm: "emoji" }[action];
			await setState(ctx.env, ctx.from.id, { a: "sx_edit", pid: arg, field });
			const prompt = {
				title: "Новое название товара.",
				stars: "Новая цена в ⭐ (целое число).",
				desc: "Новое описание («-» очистит).",
				give: "Что получит покупатель после оплаты: текст (например, ссылка или инструкция). «-» значит «выдаю вручную».",
				emoji: "Пришлите эмодзи для кнопки товара: обычный или анимированный (Premium). «-» уберёт эмодзи.",
			}[field];
			await show(ctx, prompt, kb([[btn("✖️ Отмена", `a:sxe:${arg}`)]]));
			return true;
		}
		default:
			return false;
	}
}

const validStars = (value) => Number.isInteger(value) && value >= 1 && value <= 100000;

/** Returns true when the admin's message answered one of this module's prompts. */
export async function productsInput(ctx, state, message, text) {
	const plain = { ...ctx, callback: null };
	if (state.a === "sx_add") {
		const parts = text.split("|").map((part) => part.trim());
		const [title, price, ...rest] = parts;
		const stars = Number(price);
		if (!title || title.length > 60 || !validStars(stars)) {
			await say(ctx, "Формат: название | цена ⭐ | текст выдачи (необязательно). Цена — целое число от 1 до 100000.", kb([[btn("✖️ Отмена", `a:sxl:${state.button}`)]]));
			return true;
		}
		const products = await getProducts(ctx.env);
		const product = { id: newId(6), section: state.button, title, desc: "", stars, give: rest.join("|").trim().slice(0, 3000), emoji: "", icon: "", active: true };
		await saveProducts(ctx.env, [...products, product]);
		await clearState(ctx.env, ctx.from.id);
		await showProductCard(plain, product.id);
		return true;
	}
	if (state.a === "sx_edit") {
		const products = await getProducts(ctx.env);
		const product = products.find((entry) => entry.id === state.pid);
		if (!product) {
			await clearState(ctx.env, ctx.from.id);
			return true;
		}
		if (state.field === "stars") {
			const stars = Number(text);
			if (!validStars(stars)) {
				await say(ctx, "Нужно целое число от 1 до 100000.", kb([[btn("✖️ Отмена", `a:sxe:${state.pid}`)]]));
				return true;
			}
			product.stars = stars;
		} else if (state.field === "title") {
			if (!text || text.length > 60) {
				await say(ctx, "Название: 1-60 символов.", kb([[btn("✖️ Отмена", `a:sxe:${state.pid}`)]]));
				return true;
			}
			product.title = text;
		} else if (state.field === "desc") {
			product.desc = text === "-" ? "" : text.slice(0, 1500);
		} else if (state.field === "give") {
			product.give = text === "-" ? "" : text.slice(0, 3000);
		} else if (state.field === "emoji") {
			if (text === "-") {
				product.emoji = "";
				product.icon = "";
			} else {
				const found = readEmoji(message, text);
				if (!found) {
					await say(ctx, "Не вижу эмодзи. Пришлите одно эмодзи (или «-», чтобы убрать).", kb([[btn("✖️ Отмена", `a:sxe:${state.pid}`)]]));
					return true;
				}
				product.emoji = found.emoji;
				product.icon = found.icon ?? "";
			}
		}
		await saveProducts(ctx.env, products);
		await clearState(ctx.env, ctx.from.id);
		await showProductCard(plain, state.pid);
		return true;
	}
	return false;
}
