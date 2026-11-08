/** Admin side of payments: editor for payment methods, and the queue of manual payment claims. */

import { show, say, toast } from "./context.js";
import { trySend } from "./telegram.js";
import { getUser } from "../users.js";
import { btn, kb, esc, fmtTime, tierLabel } from "./ui.js";
import {
	getPayMethods, savePayMethods, getTariffs, newId, getOrder, saveOrder, getState, setState, clearState,
	clearUserState, listOrderSummaries,
} from "./store.js";
import { fulfillOrder } from "./shop.js";
import { getText } from "./texts.js";
import { renderDetails, manualAmount, formatAmount, orderPrice, reviewButtons } from "./pay.js";
import { isTonAddress, tonRubRate, rubToTon } from "./ton.js";

const CANCEL = kb([[btn("✖️ Отмена", "a:cancel")]]);

const DETAILS_HELP =
	"Пришлите реквизиты текстом, можно в несколько строк. Строки вида «Подпись: значение» покупатель сможет скопировать одним тапом.\n\nПример:\n<code>Карта Сбербанк: 2202 2000 0000 0000\nПолучатель: Иван И.\nUSDT TRC20: TXyz…</code>";
const RATE_HELP =
	"Цена за 1 ⭐ в валюте этого способа: число и валюта. Сумма тарифа = цена в ⭐ × курс.\nПримеры: <code>1.8 ₽</code>, <code>0.02 USDT</code>, <code>0.9 грн</code>";

const TON_HELP = "Отправьте адрес вашего TON-кошелька: Tonkeeper → «Получить» → скопировать адрес (начинается с UQ или EQ).";
const RUB_RATE_HELP = "Сколько рублей стоит 1 ⭐ для этого способа? Например: 1.8 — тогда тариф за 500 ⭐ будет стоить 900 ₽, а в TON бот пересчитает сам по текущему курсу.";

function parseRub(text) {
	const match = /^(\d+(?:[.,]\d+)?)\s*(?:₽|руб\.?|р\.?|rub)?$/i.exec(text);
	if (!match) {
		return null;
	}
	const rate = Number(match[1].replace(",", "."));
	return rate > 0 && rate < 1e6 ? rate : null;
}

export function parseRate(text) {
	const match = /^(\d+(?:[.,]\d+)?)\s*(\S{1,8})$/.exec(text.trim());
	if (!match) {
		return null;
	}
	const rate = Number(match[1].replace(",", "."));
	return rate > 0 && rate < 1e7 ? { rate, currency: match[2] } : null;
}

// ---------- methods ----------

export async function showPayList(ctx) {
	const methods = await getPayMethods(ctx.env);
	const rows = methods.map((method) => [btn(`${method.active ? "✅" : "⏸"} ${method.kind === "stars" ? "⭐" : method.kind === "ton" ? "💎" : "💳"} ${method.title}`.slice(0, 60), `a:p:${method.id}`)]);
	rows.push([btn("➕ TON на мой кошелёк (Tonkeeper)", "a:pat")]);
	rows.push([btn("➕ Другой способ (вручную)", "a:pa")]);
	rows.push([btn("← Админка", "a:home")]);
	return show(
		ctx,
		"💳 <b>Способы оплаты</b>\nПокупатель выбирает один из включённых. Stars проверяются автоматически; остальные (карта, кошельки, любой текст) вы подтверждаете вручную по заявке.",
		kb(rows)
	);
}

export async function showPayCard(ctx, id) {
	const methods = await getPayMethods(ctx.env);
	const method = methods.find((item) => item.id === id);
	if (!method) {
		return showPayList(ctx);
	}
	if (method.kind === "stars") {
		return show(
			ctx,
			`⭐ <b>${esc(method.title)}</b>\nВстроенный способ: платёж внутри Telegram, ключ и файлы выдаются сами.\nСтатус: ${method.active ? "включён" : "выключен"}`,
			kb([[btn(method.active ? "⏸ Выключить" : "▶️ Включить", `a:pt:${id}`)], [btn("← К способам", "a:p")]])
		);
	}
	if (method.kind === "ton") {
		const rate = await tonRubRate(ctx.env);
		const sample = (await getTariffs(ctx.env)).find((item) => item.active);
		const rub = sample ? manualAmount(method, sample) : null;
		const lines = [
			`💎 <b>${esc(method.title)}</b>`,
			`Кошелёк: <code>${esc(method.tonAddress ?? "не задан")}</code>`,
			`Цена: 1 ⭐ = ${esc(method.rate)} ₽, в TON пересчитывается по курсу при каждом заказе.`,
			rate ? `Курс сейчас: 1 TON ≈ ${esc(formatAmount(rate, "₽"))}` : "Курс сейчас недоступен.",
			sample && rate ? `Пример: ${esc(sample.title)} — ${esc(formatAmount(rub, "₽"))} ≈ ${esc(formatAmount(rubToTon(rub, rate), "TON"))}` : "",
			`Статус: ${method.active ? "включён" : "выключен"}`,
			"",
			"Покупатель переводит TON с уникальным комментарием, бот сам находит платёж в блокчейне и выдаёт ключ.",
		].filter(Boolean);
		return show(
			ctx,
			lines.join("\n"),
			kb([
				[btn(method.active ? "⏸ Выключить" : "▶️ Включить", `a:pt:${id}`), btn("✏️ Название", `a:pe:${id}:title`)],
				[btn("💎 Кошелёк", `a:pe:${id}:ton`), btn("💲 ₽ за 1 ⭐", `a:pe:${id}:rate`)],
				[btn("🗑 Удалить", `a:pdel:${id}`), btn("← К способам", "a:p")],
			])
		);
	}
	const tariff = (await getTariffs(ctx.env)).find((item) => item.active);
	const example = tariff ? `\nПример: ${esc(tariff.title)} — ${esc(formatAmount(manualAmount(method, tariff), method.currency))}` : "";
	const text = [
		`💳 <b>${esc(method.title)}</b>`,
		`Курс: 1 ⭐ = ${esc(method.rate)} ${esc(method.currency)}${example}`,
		`Статус: ${method.active ? "включён" : "выключен"}`,
		"",
		"<b>Реквизиты (как увидит покупатель)</b>",
		renderDetails(method.details),
	].join("\n");
	return show(
		ctx,
		text,
		kb([
			[btn(method.active ? "⏸ Выключить" : "▶️ Включить", `a:pt:${id}`), btn("✏️ Название", `a:pe:${id}:title`)],
			[btn("📝 Реквизиты", `a:pe:${id}:details`), btn("💲 Курс", `a:pe:${id}:rate`)],
			[btn("🗑 Удалить", `a:pdel:${id}`), btn("← К способам", "a:p")],
		])
	);
}

// ---------- claims queue ----------

async function orderCardText(ctx, order) {
	const user = await getUser(ctx.env, order.userId);
	const buyer = user?.username ? `@${esc(user.username)}` : `id ${esc(order.userId)}`;
	const state = { awaiting: "ждёт оплаты", review: "на проверке", paid: "оплачен", delivered: "выдан", rejected: "отклонён", cancelled: "отменён" }[order.status] ?? order.status;
	return [
		`🧾 <b>Заказ</b> <code>${esc(order.id)}</code> — ${state}`,
		`Покупатель: ${buyer} (<code>${esc(order.userId)}</code>)`,
		order.kind === "item" ? `${esc(order.title)} · товар` : `${esc(order.title)} · ${tierLabel(order.tier)}`,
		`Сумма: <b>${esc(orderPrice(order))}</b>${order.methodTitle ? ` · ${esc(order.methodTitle)}` : ""}`,
		`Создан: ${esc(fmtTime(order.createdAt))}${order.claimedAt ? `, «оплатил»: ${esc(fmtTime(order.claimedAt))}` : ""}`,
		order.proofs ? `Присланных чеков: ${order.proofs}` : "",
	].filter(Boolean).join("\n");
}

export async function showOrder(ctx, id) {
	const order = await getOrder(ctx.env, id);
	if (!order) {
		return toast(ctx, "Заказ не найден", true);
	}
	const open = order.status === "review" || order.status === "awaiting";
	const rows = open ? reviewButtons(id).slice(0, 1) : [];
	rows.push([btn("👤 Профиль", `a:u:${order.userId}`), btn("← Заявки", "a:pq")]);
	return show(ctx, await orderCardText(ctx, order), kb(rows));
}

export async function showQueue(ctx) {
	const waiting = (await listOrderSummaries(ctx.env)).filter((order) => order.st === "review").sort((a, b) => (a.at || 0) - (b.at || 0));
	const orders = (await Promise.all(waiting.slice(0, 20).map((entry) => getOrder(ctx.env, entry.id)))).filter(Boolean);
	if (orders.length === 0) {
		return show(ctx, "🧾 Заявок на проверке нет.", kb([[btn("← Админка", "a:home")]]));
	}
	const rows = orders.map((order) => [btn(`${order.title} · ${orderPrice(order)} · id ${order.userId}`.slice(0, 60), `a:po:${order.id}`)]);
	rows.push([btn("← Админка", "a:home")]);
	return show(ctx, `🧾 <b>Заявки на проверке: ${waiting.length}</b>`, kb(rows));
}

export async function pendingClaims(env) {
	return (await listOrderSummaries(env)).filter((order) => order.st === "review").length;
}

async function confirmOrder(ctx, id) {
	const order = await getOrder(ctx.env, id);
	if (!order || (order.status !== "review" && order.status !== "awaiting")) {
		return toast(ctx, "Заказ уже обработан", true);
	}
	order.confirmedBy = String(ctx.from.id);
	order.confirmedAt = ctx.now;
	await clearUserState(ctx.env, order.userId);
	const user = await getUser(ctx.env, order.userId);
	// Delivery goes to the buyer's chat; the admin's own callback only supplies the clock/env/api.
	const buyerCtx = { ...ctx, chatId: order.userId, callback: null, from: { id: order.userId, username: user?.username ?? "" } };
	const ok = await fulfillOrder(buyerCtx, order, buyerCtx.from, false);
	await toast(ctx, ok ? "Подтверждено, выдано" : "Подтверждено, но ключ не создан", true);
	return show(ctx, `${await orderCardText(ctx, order)}\n\n${ok ? "✅ Подтверждено, ключ и файлы отправлены." : "⚠️ Ключ не создался, выдайте вручную."}`, kb([[btn("👤 Профиль", `a:u:${order.userId}`), btn("← Заявки", "a:pq")]]));
}

async function rejectOrder(ctx, id) {
	const order = await getOrder(ctx.env, id);
	if (!order || (order.status !== "review" && order.status !== "awaiting")) {
		return toast(ctx, "Заказ уже обработан", true);
	}
	order.status = "rejected";
	order.rejectedAt = ctx.now;
	await saveOrder(ctx.env, order);
	await clearUserState(ctx.env, order.userId);
	await trySend(ctx.tg, order.userId, await getText(ctx.env, "pay_rejected", { title: order.title }));
	await toast(ctx, "Отклонено");
	return show(ctx, `${await orderCardText(ctx, order)}\n\n❌ Отклонено, покупатель уведомлён.`, kb([[btn("← Заявки", "a:pq")]]));
}

// ---------- router hooks ----------

/** Returns true when it handled the callback. `parts` is the callback data split by ":" without "a:". */
export async function payCallback(ctx, parts) {
	const [action, arg, extra] = parts;
	switch (action) {
		case "p":
			await toast(ctx);
			await showPayHome(ctx, arg);
			return true;
		case "pt": {
			const methods = await getPayMethods(ctx.env);
			const method = methods.find((item) => item.id === arg);
			if (method) {
				method.active = !method.active;
				await savePayMethods(ctx.env, methods);
			}
			await toast(ctx);
			await showPayCard(ctx, arg);
			return true;
		}
		case "pat":
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "pay_add_ton", step: "address" });
			await show(ctx, TON_HELP, CANCEL);
			return true;
		case "pdel": {
			const methods = await getPayMethods(ctx.env);
			await savePayMethods(ctx.env, methods.filter((item) => item.id !== arg || item.kind === "stars"));
			await toast(ctx, "Удалён");
			await showPayList(ctx);
			return true;
		}
		case "pa":
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "pay_add", step: "title" });
			await show(ctx, "Название способа для покупателя, например «Карта Сбербанк» или «USDT TRC20».", CANCEL);
			return true;
		case "pe": {
			if (!["title", "details", "rate", "ton"].includes(extra)) {
				return true;
			}
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "pay_edit", id: arg, field: extra });
			await show(ctx, { title: "Новое название.", details: DETAILS_HELP, rate: RATE_HELP, ton: TON_HELP }[extra], CANCEL);
			return true;
		}
		case "pq":
			await toast(ctx);
			await showQueue(ctx);
			return true;
		case "po":
			await toast(ctx);
			await showOrder(ctx, arg);
			return true;
		case "pc":
			await confirmOrder(ctx, arg);
			return true;
		case "pr":
			await rejectOrder(ctx, arg);
			return true;
		default:
			return false;
	}
}

const showPayHome = (ctx, id) => (id ? showPayCard(ctx, id) : showPayList(ctx));

/** Returns true when `state` belongs to the payment editor (and the message was consumed). */
export async function payInput(ctx, state, text) {
	if (state.a !== "pay_add" && state.a !== "pay_edit" && state.a !== "pay_add_ton") {
		return false;
	}
	const plain = { ...ctx, callback: null };
	if (state.a === "pay_add_ton") {
		const value = (text ?? "").trim();
		if (state.step === "address") {
			if (!isTonAddress(value)) {
				await say(ctx, `Это не похоже на адрес TON.\n${TON_HELP}`, CANCEL);
				return true;
			}
			await setState(ctx.env, ctx.from.id, { a: "pay_add_ton", step: "rate", address: value });
			await say(ctx, RUB_RATE_HELP, CANCEL);
			return true;
		}
		const rate = parseRub(value);
		if (!rate) {
			await say(ctx, `Не понял число.\n${RUB_RATE_HELP}`, CANCEL);
			return true;
		}
		const methods = await getPayMethods(ctx.env);
		const method = { id: newId(6), kind: "ton", title: "TON (Tonkeeper)", details: "", tonAddress: state.address, rate, currency: "₽", active: true };
		await savePayMethods(ctx.env, [...methods, method]);
		await clearState(ctx.env, ctx.from.id);
		await showPayCard(plain, method.id);
		return true;
	}
	if (state.a === "pay_add") {
		if (state.step === "title") {
			if (!text || text.length > 40) {
				await say(ctx, "Название: 1-40 символов.", CANCEL);
				return true;
			}
			await setState(ctx.env, ctx.from.id, { a: "pay_add", step: "details", title: text });
			await say(ctx, DETAILS_HELP, CANCEL);
			return true;
		}
		if (state.step === "details") {
			if (!text || text.length > 1500) {
				await say(ctx, "Реквизиты: текст до 1500 символов.", CANCEL);
				return true;
			}
			await setState(ctx.env, ctx.from.id, { a: "pay_add", step: "rate", title: state.title, details: text });
			await say(ctx, RATE_HELP, CANCEL);
			return true;
		}
		const parsed = parseRate(text);
		if (!parsed) {
			await say(ctx, `Не понял курс.\n${RATE_HELP}`, CANCEL);
			return true;
		}
		const methods = await getPayMethods(ctx.env);
		const method = { id: newId(6), kind: "manual", title: state.title, details: state.details, rate: parsed.rate, currency: parsed.currency, active: true };
		await savePayMethods(ctx.env, [...methods, method]);
		await clearState(ctx.env, ctx.from.id);
		await showPayCard(plain, method.id);
		return true;
	}
	const methods = await getPayMethods(ctx.env);
	const method = methods.find((item) => item.id === state.id && (item.kind === "manual" || item.kind === "ton"));
	if (!method) {
		await clearState(ctx.env, ctx.from.id);
		await showPayList(plain);
		return true;
	}
	if (state.field === "title") {
		if (!text || text.length > 40) {
			await say(ctx, "Название: 1-40 символов.", CANCEL);
			return true;
		}
		method.title = text;
	} else if (state.field === "details") {
		if (!text || text.length > 1500) {
			await say(ctx, "Реквизиты: текст до 1500 символов.", CANCEL);
			return true;
		}
		method.details = text;
	} else if (state.field === "ton") {
		const value = (text ?? "").trim();
		if (value === "-") {
			delete method.tonAddress;
		} else if (isTonAddress(value)) {
			method.tonAddress = value;
		} else {
			await say(ctx, `Это не похоже на адрес TON.\n${TON_HELP}`, CANCEL);
			return true;
		}
	} else if (method.kind === "ton") {
		const rate = parseRub((text ?? "").trim());
		if (!rate) {
			await say(ctx, `Не понял число.\n${RUB_RATE_HELP}`, CANCEL);
			return true;
		}
		method.rate = rate;
		method.currency = "₽";
	} else {
		const parsed = parseRate(text);
		if (!parsed) {
			await say(ctx, `Не понял курс.\n${RATE_HELP}`, CANCEL);
			return true;
		}
		method.rate = parsed.rate;
		method.currency = parsed.currency;
	}
	await savePayMethods(ctx.env, methods);
	await clearState(ctx.env, ctx.from.id);
	await showPayCard(plain, method.id);
	return true;
}
