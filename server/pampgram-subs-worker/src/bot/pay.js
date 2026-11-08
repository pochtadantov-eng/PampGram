/**
 * Manual payment methods (card number, wallet addresses, any text the owner writes) and the
 * confirm-by-hand flow:
 *
 *   buyer picks a method -> order "awaiting" + requisites shown -> "I paid" -> order "review",
 *   admins notified (and any receipt the buyer sends is copied to them) -> admin confirms ->
 *   the normal fulfilment (key + files), or rejects.
 *
 * Nothing here can verify a transfer; the admin's confirmation is what releases the goods.
 */

import { say, show, toast } from "./context.js";
import { btn, kb, esc, tierLabel, fmtHours } from "./ui.js";
import { trySend } from "./telegram.js";
import { getPayMethods, saveOrder, getOrder, newId, adminIds, getUserState, setUserState, clearUserState } from "./store.js";
import { banReason, availableTariffs, notifyAdmins } from "./shop.js";
import { findSellable } from "./products.js";
import { getText } from "./texts.js";
import { isAutoTon, tonComment, tonkeeperLink, markTonWaiting, confirmIfPaid } from "./ton.js";

const MAX_PROOFS = 5;

/** Price of a tariff in a manual method's currency: stars * rate, rounded up to cents. */
export function manualAmount(method, tariff) {
	return Math.ceil(tariff.stars * method.rate * 100 - 1e-9) / 100;
}

export function formatAmount(amount, currency) {
	return `${Number(amount.toFixed(2)).toString()} ${currency}`;
}

/**
 * Requisites as the owner typed them. Lines like "Карта: 2200 1234" get the value in <code> so a
 * tap copies just the number; other lines stay plain text. Everything is escaped.
 */
export function renderDetails(text) {
	return String(text ?? "")
		.split("\n")
		.map((line) => {
			const split = line.indexOf(":");
			const value = split > 0 ? line.slice(split + 1).trim() : "";
			if (split > 0 && split < 40 && value) {
				return `${esc(line.slice(0, split + 1))} <code>${esc(value)}</code>`;
			}
			return esc(line);
		})
		.join("\n");
}

/** Sum a list of { stars, currency, amount } as "1 200 ⭐ + 3 400 ₽". */
export function totalsText(items) {
	let stars = 0;
	const byCurrency = new Map();
	for (const item of items) {
		if (item.currency) {
			byCurrency.set(item.currency, (byCurrency.get(item.currency) ?? 0) + (item.amount || 0));
		} else {
			stars += item.stars || 0;
		}
	}
	const parts = [];
	if (stars || byCurrency.size === 0) {
		parts.push(`${String(stars).replace(/\B(?=(\d{3})+(?!\d))/g, " ")} ⭐`);
	}
	for (const [currency, sum] of byCurrency) {
		parts.push(formatAmount(sum, currency));
	}
	return parts.join(" + ");
}

export const orderPrice = (order) => order.priceText ?? `${order.stars} ⭐`;

function who(from) {
	return from.username ? `@${esc(from.username)}` : `id ${esc(from.id)}`;
}

export const reviewButtons = (orderId) => [
	[btn("✅ Подтвердить", `a:pc:${orderId}`), btn("❌ Отклонить", `a:pr:${orderId}`)],
	[btn("🧾 Заказ", `a:po:${orderId}`)],
];

export async function startManualPurchase(ctx, code, methodId) {
	if (await banReason(ctx.env, ctx.from.id)) {
		await toast(ctx, "Доступ ограничен", true);
		return;
	}
	const method = (await getPayMethods(ctx.env)).find((item) => item.id === methodId && item.kind === "manual" && item.active);
	const tariff = (await findSellable(ctx.env, code)) ?? (await availableTariffs(ctx.env, ctx.from.id)).find((item) => item.code === code);
	if (!method || !tariff) {
		await toast(ctx, "Этот способ или тариф недоступен", true);
		return;
	}
	const amount = manualAmount(method, tariff);
	const order = {
		id: newId(10),
		userId: String(ctx.from.id),
		tariff: tariff.code,
		title: tariff.title,
		tier: tariff.tier,
		hours: tariff.hours || 0,
		stars: tariff.stars,
		...(tariff.kind === "item" ? { kind: "item", pid: tariff.pid, give: tariff.give } : {}),
		method: method.id,
		methodTitle: method.title,
		currency: method.currency,
		amount,
		priceText: formatAmount(amount, method.currency),
		status: "awaiting",
		createdAt: ctx.now,
		paidAt: null,
		key: null,
		boundAt: null,
	};
	await saveOrder(ctx.env, order);
	await toast(ctx);
	if (isAutoTon(method)) {
		await markTonWaiting(ctx.env, order);
		return show(
			ctx,
			[
				`<b>Оплата: ${esc(method.title)}</b>`,
				tariff.kind === "item" ? `${esc(tariff.title)}` : `${esc(tariff.title)} · ${tierLabel(tariff.tier)} · ${fmtHours(tariff.hours)}`,
				`К оплате: <b>${esc(order.priceText)}</b>`,
				"",
				`Адрес: <code>${esc(method.tonAddress)}</code>`,
				`Комментарий: <code>${esc(tonComment(order))}</code>`,
				"",
				"Переведите сумму не меньше указанной <b>с этим комментарием</b> (без него платёж не найдётся). Кнопка ниже откроет Tonkeeper с заполненными полями. После перевода нажмите «Проверить оплату» — ключ придёт сам, обычно в течение минуты.",
			].join("\n"),
			kb([[{ text: "💎 Открыть в Tonkeeper", url: tonkeeperLink(method.tonAddress, order) }], [btn("🔄 Проверить оплату", `pd:${order.id}`)], [btn("✖️ Отмена", `px:${order.id}`)]])
		);
	}
	return show(
		ctx,
		[
			`<b>Оплата: ${esc(method.title)}</b>`,
			tariff.kind === "item" ? `${esc(tariff.title)}` : `${esc(tariff.title)} · ${tierLabel(tariff.tier)} · ${fmtHours(tariff.hours)}`,
			`К оплате: <b>${esc(order.priceText)}</b>`,
			"",
			renderDetails(method.details),
			"",
			await getText(ctx.env, tariff.kind === "item" ? "pay_manual_item" : "pay_manual_tariff"),
		].join("\n"),
		kb([[btn("✅ Я оплатил(а)", `pd:${order.id}`)], [btn("✖️ Отмена", `px:${order.id}`)]])
	);
}

async function ownOrder(ctx, orderId) {
	const order = await getOrder(ctx.env, orderId);
	return order && order.userId === String(ctx.from.id) ? order : null;
}

export async function claimPaid(ctx, orderId) {
	const order = await ownOrder(ctx, orderId);
	if (!order) {
		return toast(ctx, "Заказ не найден", true);
	}
	if (order.status === "review") {
		return toast(ctx, "Заявка уже отправлена, ждите проверки", true);
	}
	if (order.status !== "awaiting") {
		return toast(ctx, "Этот заказ уже обработан", true);
	}
	const method = (await getPayMethods(ctx.env)).find((item) => item.id === order.method);
	if (isAutoTon(method)) {
		let paid = false;
		try {
			paid = await confirmIfPaid(ctx.env, ctx.tg, order, method, ctx.now);
		} catch {
			return toast(ctx, "Не удалось проверить блокчейн, попробуйте через минуту", true);
		}
		if (!paid) {
			return toast(ctx, "Платёж пока не найден. Если уже перевели — подождите минуту и нажмите ещё раз.", true);
		}
		return toast(ctx, "Оплата найдена, ключ отправлен");
	}
	order.status = "review";
	order.claimedAt = ctx.now;
	order.proofs = 0;
	await saveOrder(ctx.env, order);
	await setUserState(ctx.env, order.userId, { orderId: order.id });
	await toast(ctx);
	await notifyAdmins(
		ctx,
		`🧾 <b>Заявка на оплату</b>\n${who(ctx.from)} (<code>${esc(order.userId)}</code>)\n${esc(order.title)} — <b>${esc(orderPrice(order))}</b> · ${esc(order.methodTitle)}\nЗаказ: <code>${esc(order.id)}</code>`,
		kb([...reviewButtons(order.id), [btn("👤 Профиль", `a:u:${order.userId}`)]])
	);
	return show(
		ctx,
		await getText(ctx.env, "claim_sent"),
		kb([[btn("← В меню", "menu")]])
	);
}

export async function cancelOrder(ctx, orderId) {
	const order = await ownOrder(ctx, orderId);
	if (!order || order.status !== "awaiting") {
		return toast(ctx, "Заказ нельзя отменить", true);
	}
	order.status = "cancelled";
	await saveOrder(ctx.env, order);
	await toast(ctx, "Отменено");
	return show(ctx, await getText(ctx.env, "order_cancelled"), kb([[btn("🛒 К тарифам", "shop")], [btn("← В меню", "menu")]]));
}

/** A buyer's message while their payment is under review: copy it to the admins. */
export async function forwardProof(ctx, message) {
	const state = await getUserState(ctx.env, ctx.from.id);
	if (!state) {
		return false;
	}
	const order = await getOrder(ctx.env, state.orderId);
	if (!order || order.status !== "review") {
		await clearUserState(ctx.env, ctx.from.id);
		return false;
	}
	if ((order.proofs ?? 0) >= MAX_PROOFS) {
		await say(ctx, "Уже получили достаточно сообщений по этой заявке. Ждите проверки.");
		return true;
	}
	order.proofs = (order.proofs ?? 0) + 1;
	await saveOrder(ctx.env, order);
	for (const admin of adminIds(ctx.env)) {
		await trySend(ctx.tg, admin, `📎 К заявке <code>${esc(order.id)}</code> от ${who(ctx.from)}:`);
		try {
			await ctx.tg.call("copyMessage", {
				chat_id: admin,
				from_chat_id: message.chat.id,
				message_id: message.message_id,
				reply_markup: kb(reviewButtons(order.id)).reply_markup,
			});
		} catch {
			// an admin who blocked the bot just does not get the copy
		}
	}
	await say(ctx, await getText(ctx.env, "proof_ok"));
	return true;
}
