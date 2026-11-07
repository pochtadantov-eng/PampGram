/** Customer-facing flows: menu, tariffs, Telegram Stars payment, delivery, purchases. */

import { readBanRecord, readSubscription } from "../core.js";
import { issueKey, redeemKeyForAccount } from "../keys.js";
import { updateUser, getUser } from "../users.js";
import { say, show, toast } from "./context.js";
import { trySend } from "./telegram.js";
import { btn, urlBtn, kb, esc, fmtTime, fmtHours, tierLabel, fixTitle } from "./ui.js";
import { getBanners, getConfig, getTariffs, getBundle, getOrder, saveOrder, listUserOrders, newId, markCharge, chargeOrder, adminIds, isAdmin, getPayMethods } from "./store.js";
import { manualAmount, formatAmount, orderPrice } from "./pay.js";
import { BUILTIN, customizeRows } from "./buttons.js";

export async function notifyAdmins(ctx, text, extra = {}) {
	for (const id of adminIds(ctx.env)) {
		await trySend(ctx.tg, id, text, extra);
	}
}

export async function banReason(env, userId) {
	const record = await readBanRecord(env, String(userId));
	return record.full ? record.full.reason : null;
}

const BANNER_METHOD = { photo: ["sendPhoto", "photo"], animation: ["sendAnimation", "animation"], video: ["sendVideo", "video"] };

/**
 * Shows a screen with the admin's banner above it (a picture, GIF or video with the text as its caption).
 * Without a banner, or if Telegram refuses the file, it is the ordinary text screen.
 */
export async function showWithBanner(ctx, key, text, extra = {}) {
	const banner = (await getBanners(ctx.env))[key];
	const [method, field] = BANNER_METHOD[banner?.type] ?? [];
	if (!method || !banner.fileId) {
		return show(ctx, text, extra);
	}
	const inCaption = text.length <= 1000;
	try {
		await ctx.tg.call(method, { chat_id: ctx.chatId, [field]: banner.fileId, ...(inCaption ? { caption: text, parse_mode: "HTML", ...extra } : {}) });
	} catch {
		return show(ctx, text, extra);
	}
	if (ctx.callback?.message_id) {
		await ctx.tg.call("deleteMessage", { chat_id: ctx.chatId, message_id: ctx.callback.message_id }).catch(() => {});
	}
	if (!inCaption) {
		return say(ctx, text, extra);
	}
	return true;
}

export async function showMenu(ctx) {
	const config = await getConfig(ctx.env);
	const rows = [
		[btn(BUILTIN.menu.shop, "shop")],
		[btn(BUILTIN.menu.my, "my"), btn(BUILTIN.menu.dl, "dl")],
		[btn(BUILTIN.menu.privacy, "privacy")],
	];
	if (config.support) {
		rows.push([{ ...urlBtn(BUILTIN.menu.support, `https://t.me/${config.support.replace(/^@/, "")}`), _key: "support" }]);
	}
	if (isAdmin(ctx.env, ctx.from.id)) {
		rows.push([btn("🛠 Админ-панель", "a:home")]);
	}
	return showWithBanner(ctx, "menu", config.welcome, kb(await customizeRows(ctx.env, "menu", rows, isAdmin(ctx.env, ctx.from.id) ? 1 : 0)));
}

async function ownsTier(env, userId, tier) {
	const orders = await listUserOrders(env, userId);
	return orders.some((order) => order.tier === tier && (order.status === "paid" || order.status === "delivered"));
}

export async function availableTariffs(env, userId) {
	const tariffs = (await getTariffs(env)).filter((tariff) => tariff.active);
	const result = [];
	for (const tariff of tariffs) {
		if (!tariff.requires || (await ownsTier(env, userId, tariff.requires))) {
			result.push(tariff);
		}
	}
	return result;
}

export async function showTariffs(ctx) {
	const ban = await banReason(ctx.env, ctx.from.id);
	if (ban) {
		return show(ctx, `⛔ Доступ ограничен.\nПричина: ${esc(ban)}`, kb([[btn("← Назад", "menu")]]));
	}
	const tariffs = await availableTariffs(ctx.env, ctx.from.id);
	if (tariffs.length === 0) {
		return show(ctx, "Сейчас нет доступных тарифов.", kb([[btn("← Назад", "menu")]]));
	}
	const rows = tariffs.map((tariff) => [btn(`${tariff.title} — ${tariff.stars} ⭐`, `t:${tariff.code}`)]);
	rows.push([btn("← Назад", "menu")]);
	return showWithBanner(ctx, "shop", "<b>Тарифы</b>\nВыберите тариф, затем способ оплаты. Ключ и файлы приходят после оплаты.", kb(await customizeRows(ctx.env, "shop", rows, 1)));
}

export async function showTariff(ctx, code) {
	const tariffs = await availableTariffs(ctx.env, ctx.from.id);
	const tariff = tariffs.find((item) => item.code === code);
	if (!tariff) {
		await toast(ctx, "Этот тариф недоступен", true);
		return showTariffs(ctx);
	}
	const text = `<b>${esc(tariff.title)}</b>\n${esc(tariff.desc ?? "")}\n\nУровень: ${tierLabel(tariff.tier)}\nСрок: ${fmtHours(tariff.hours)}\nЦена: ${tariff.stars} ⭐`;
	const methods = (await getPayMethods(ctx.env)).filter((method) => method.active);
	const rows = methods.map((method) =>
		method.kind === "stars"
			? [btn(`⭐ ${method.title} — ${tariff.stars} ⭐`, `buy:${tariff.code}`)]
			: [btn(`💳 ${method.title} — ${formatAmount(manualAmount(method, tariff), method.currency)}`.slice(0, 60), `pay:${tariff.code}:${method.id}`)]
	);
	rows.push([btn("← К тарифам", "shop")]);
	const hint = methods.length === 0 ? "\n\nСпособы оплаты пока не настроены. Напишите в поддержку." : "\n\nВыберите способ оплаты:";
	return show(ctx, text + hint, kb(rows));
}

export async function startPurchase(ctx, code) {
	const ban = await banReason(ctx.env, ctx.from.id);
	if (ban) {
		await toast(ctx, "Доступ ограничен", true);
		return;
	}
	const tariff = (await availableTariffs(ctx.env, ctx.from.id)).find((item) => item.code === code);
	if (!tariff) {
		await toast(ctx, "Этот тариф недоступен", true);
		return;
	}
	if (!(await getPayMethods(ctx.env)).some((method) => method.kind === "stars" && method.active)) {
		await toast(ctx, "Оплата Stars сейчас отключена", true);
		return;
	}
	const order = {
		id: newId(10),
		userId: String(ctx.from.id),
		tariff: tariff.code,
		title: tariff.title,
		tier: tariff.tier,
		hours: tariff.hours || 0,
		stars: tariff.stars,
		status: "pending",
		createdAt: ctx.now,
		paidAt: null,
		key: null,
		boundAt: null,
	};
	await saveOrder(ctx.env, order);
	await toast(ctx);
	try {
		await ctx.tg.call("sendInvoice", {
			chat_id: ctx.chatId,
			title: tariff.title.slice(0, 32),
			description: (tariff.desc || tariff.title).slice(0, 255),
			payload: `o:${order.id}`,
			currency: "XTR",
			prices: [{ label: tariff.title.slice(0, 32), amount: tariff.stars }],
		});
	} catch (error) {
		await say(ctx, "Не получилось создать счёт. Попробуйте ещё раз чуть позже.");
		await notifyAdmins(ctx, `⚠️ Не удалось создать счёт для ${esc(ctx.from.id)}: ${esc(error.description || error.message)}`);
	}
}

/** Telegram asks, within 10 seconds, whether the invoice may still be paid. */
export async function handlePreCheckout(ctx, query) {
	const fail = (message) => ctx.tg.call("answerPreCheckoutQuery", { pre_checkout_query_id: query.id, ok: false, error_message: message });
	const orderId = String(query.invoice_payload ?? "").startsWith("o:") ? query.invoice_payload.slice(2) : null;
	const order = orderId ? await getOrder(ctx.env, orderId) : null;
	if (!order || order.userId !== String(query.from.id)) {
		return fail("Заказ не найден. Откройте тариф заново.");
	}
	if (order.status !== "pending") {
		return fail("Этот заказ уже оплачен.");
	}
	if (query.currency !== "XTR" || query.total_amount !== order.stars) {
		return fail("Сумма не совпадает с заказом. Откройте тариф заново.");
	}
	if (await banReason(ctx.env, query.from.id)) {
		return fail("Доступ ограничен.");
	}
	return ctx.tg.call("answerPreCheckoutQuery", { pre_checkout_query_id: query.id, ok: true });
}

export async function handleSuccessfulPayment(ctx, payment) {
	const chargeId = payment.telegram_payment_charge_id;
	if (chargeId && (await chargeOrder(ctx.env, chargeId))) {
		return; // Telegram redelivered the same notification
	}
	const orderId = String(payment.invoice_payload ?? "").startsWith("o:") ? payment.invoice_payload.slice(2) : null;
	const order = orderId ? await getOrder(ctx.env, orderId) : null;
	if (!order || order.userId !== String(ctx.from.id)) {
		await notifyAdmins(ctx, `⚠️ Оплата без заказа: пользователь ${esc(ctx.from.id)}, ${esc(payment.total_amount)} ⭐, charge <code>${esc(chargeId)}</code>`);
		await say(ctx, "Оплата получена, но заказ не найден. Напишите в поддержку, всё исправим.");
		return;
	}
	if (payment.currency !== "XTR" || payment.total_amount !== order.stars) {
		await notifyAdmins(ctx, `⚠️ Сумма оплаты не совпала с заказом ${esc(order.id)}: ${esc(payment.total_amount)} ${esc(payment.currency)} вместо ${order.stars} ⭐, charge <code>${esc(chargeId)}</code>`);
		await say(ctx, "Оплата получена, но сумма не совпала с заказом. Напишите в поддержку.");
		return;
	}
	if (chargeId) {
		await markCharge(ctx.env, chargeId, order.id);
	}
	order.chargeId = chargeId ?? null;
	await fulfillOrder(ctx, order, ctx.from, true);
}

/**
 * Marks an order paid, issues its key, delivers key + files to the buyer (`ctx.chatId` must be the
 * buyer's chat) and optionally tells the admins. Shared by Stars payments and manual confirmation.
 */
export async function fulfillOrder(ctx, order, buyer, notify) {
	order.status = "paid";
	order.paidAt = ctx.now;
	order.key = await issueKey(ctx.env, order.tier, order.hours > 0 ? order.hours : undefined);
	await saveOrder(ctx.env, order);
	await updateUser(ctx.env, order.userId, (user) => {
		user.purchases = (user.purchases ?? 0) + 1;
		user.lastPurchaseAt = ctx.now;
	}, ctx.now);

	if (!order.key) {
		await notifyAdmins(ctx, `⚠️ Оплата прошла, но ключ не создался: заказ ${esc(order.id)}, пользователь ${esc(order.userId)}`);
		await say(ctx, "Оплата получена. Ключ выдадим вручную в ближайшее время.");
		return false;
	}
	await deliver(ctx, order);
	order.status = "delivered";
	await saveOrder(ctx.env, order);
	if (notify) {
		const who = buyer.username ? `@${esc(buyer.username)}` : `id ${esc(buyer.id)}`;
		await notifyAdmins(ctx, `💰 <b>Новая оплата</b>\n${esc(order.title)} — ${esc(orderPrice(order))}\nПокупатель: ${who} (<code>${esc(order.userId)}</code>)`, kb([[btn("👤 Профиль", `a:u:${order.userId}`)]]));
	}
	return true;
}

async function sendBundle(ctx, tier) {
	const items = (await getBundle(ctx.env)).filter((item) => (item.tiers ?? []).includes(tier));
	let failed = 0;
	for (const item of items) {
		try {
			if (item.kind === "file") {
				await ctx.tg.call("sendDocument", { chat_id: ctx.chatId, document: item.fileId, caption: item.title, parse_mode: "HTML" });
			} else if (item.kind === "link") {
				await ctx.tg.call("sendMessage", { chat_id: ctx.chatId, text: `${esc(item.title)}\n${esc(item.url)}`, parse_mode: "HTML" });
			} else {
				await ctx.tg.call("sendMessage", { chat_id: ctx.chatId, text: `<b>${esc(item.title)}</b>\n${esc(item.text)}`, parse_mode: "HTML" });
			}
		} catch (error) {
			failed++;
			await notifyAdmins(ctx, `⚠️ Не удалось отправить «${esc(item.title)}» пользователю ${esc(ctx.from.id)}: ${esc(error.description || error.message)}`);
		}
	}
	return { total: items.length, failed };
}

/** The purchase confirmation: key, files, how-to. */
export async function deliver(ctx, order) {
	const config = await getConfig(ctx.env);
	const expiry = order.hours > 0 ? `, действует ${fmtHours(order.hours)} с момента активации` : "";
	await say(
		ctx,
		`✅ <b>Оплата получена</b>\n${esc(fixTitle(order.title, order.hours))} — ${esc(orderPrice(order))}\n\nВаш ключ активации (${tierLabel(order.tier)}${expiry}):\n<code>${esc(order.key)}</code>\n\nКлюч одноразовый: он привяжется к тому аккаунту Telegram, который введёт его первым.`,
		kb([[btn("🔗 Привязать к этому аккаунту", `bind:${order.id}`)]])
	);
	const sent = await sendBundle(ctx, order.tier);
	if (sent.total === 0) {
		await say(ctx, "Файлы для установки пока не добавлены — администратор пришлёт их вручную.");
		await notifyAdmins(ctx, "⚠️ Покупатель получил ключ, но комплект выдачи пуст. Добавьте файлы: /admin → Выдача.");
	}
	await say(ctx, esc(config.howto));
}

export async function bindKey(ctx, orderId) {
	const order = await getOrder(ctx.env, orderId);
	if (!order || order.userId !== String(ctx.from.id) || !order.key) {
		await toast(ctx, "Заказ не найден", true);
		return;
	}
	if (order.boundAt) {
		await toast(ctx, "Уже привязан к вашему аккаунту", true);
		return;
	}
	const result = await redeemKeyForAccount(ctx.env, String(ctx.from.id), order.key);
	if (!result.ok) {
		await toast(ctx, "Ключ уже использован", true);
		return;
	}
	order.boundAt = ctx.now;
	await saveOrder(ctx.env, order);
	await toast(ctx, `Готово: ${tierLabel(result.tier)} включён на вашем аккаунте`, true);
	await say(ctx, `🔗 Ключ привязан к вашему аккаунту (${tierLabel(result.tier)}). Откройте мод: доступ уже включён.`);
}

export async function showPurchases(ctx) {
	const orders = (await listUserOrders(ctx.env, ctx.from.id)).filter((order) => order.status === "paid" || order.status === "delivered");
	if (orders.length === 0) {
		return show(ctx, "Покупок пока нет.", kb([[btn("🛒 Купить доступ", "shop")], [btn("← Назад", "menu")]]));
	}
	const lines = orders.slice(0, 10).map((order) => {
		const state = order.boundAt ? "привязан к вашему аккаунту" : "не активирован";
		return `• <b>${esc(fixTitle(order.title, order.hours))}</b> — ${esc(orderPrice(order))}, ${esc(fmtTime(order.paidAt))}\n  <code>${esc(order.key ?? "—")}</code> (${state})`;
	});
	return show(ctx, `<b>Мои покупки</b>\n\n${lines.join("\n\n")}`, kb([[btn("📥 Скачать файлы", "dl")], [btn("← Назад", "menu")]]));
}

export async function resendFiles(ctx) {
	if (await banReason(ctx.env, ctx.from.id)) {
		await toast(ctx, "Доступ ограничен", true);
		return;
	}
	const orders = (await listUserOrders(ctx.env, ctx.from.id)).filter((order) => order.status === "paid" || order.status === "delivered");
	if (orders.length === 0) {
		await toast(ctx, "Сначала оформите доступ", true);
		return;
	}
	await toast(ctx);
	const tier = orders.some((order) => order.tier === "pro") ? "pro" : "standard";
	const sent = await sendBundle(ctx, tier);
	if (sent.total === 0) {
		await say(ctx, "Файлы пока не добавлены. Напишите в поддержку.");
	}
}

export async function showPrivacy(ctx) {
	return show(
		ctx,
		"<b>Какие данные собираются</b>\nПри запуске мод обращается к серверу лицензий и передаёт служебные данные: id вашего аккаунта Telegram, версию приложения, ник и имя профиля, время обращений. Они нужны для проверки подписки и блокировок. Сообщения и содержимое чатов не передаются.\n\nБот хранит ваш id, ник, имя и историю покупок.",
		kb([[btn("← Назад", "menu")]])
	);
}

export async function subscriptionLine(env, userId) {
	const subscription = await readSubscription(env, String(userId));
	const user = await getUser(env, String(userId));
	const until = subscription.expiresAt ? ` до ${fmtTime(subscription.expiresAt)}` : "";
	return `${tierLabel(subscription.tier)}${until}${user?.activatedAt ? "" : " (ключ не активирован)"}`;
}
