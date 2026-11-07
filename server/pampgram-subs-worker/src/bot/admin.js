/** Owner-only panel: stats, users, profile, ban, DM verification, grants, tariffs, delivery set. */

import { ALLOWED_TIERS, isValidAccountId, readBanRecord, writeBanRecord, readSubscription, writeSubscription, listAllKeys } from "../core.js";
import { getUser, updateUser, listUserSummaries, importLegacyUsers, displayName, noteTier } from "../users.js";
import { say, show, toast } from "./context.js";
import { trySend } from "./telegram.js";
import { btn, kb, esc, fmtTime, fmtAgo, fmtHours, tierLabel, fmtNumber } from "./ui.js";
import {
	getConfig, setConfig, getTariffs, saveTariffs, getBundle, saveBundle, newId,
	listOrderSummaries, listUserOrders, getState, setState, clearState, getCheck, saveCheck, listChecks,
} from "./store.js";
import { payCallback, payInput, pendingClaims } from "./payadmin.js";
import { visualsCallback, visualsInput } from "./visuals.js";
import { buttonsCallback, buttonsInput, readEmoji } from "./buttonsadmin.js";
import { GUARDED, askPassword, showPasswordMenu, securityInput } from "./security.js";
import { backupCallback, makeBackup } from "./backup.js";
import { totalsText } from "./pay.js";

const PAGE_SIZE = 8;
const ONLINE_MS = 10 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const CHECK_TTL_MS = 15 * 60 * 1000;

const CANCEL = kb([[btn("✖️ Отмена", "a:cancel")]]);

export async function adminHome(ctx) {
	await clearState(ctx.env, ctx.from.id);
	const claims = await pendingClaims(ctx.env);
	return show(
		ctx,
		"🛠 <b>Админ-панель</b>",
		kb([
			[btn("📊 Статистика", "a:stats"), btn("👥 Пользователи", "a:ul:all:0")],
			[btn("🔎 Найти", "a:find"), btn("💰 Тарифы", "a:t")],
			[btn("📦 Выдача", "a:b"), btn("💳 Оплата", "a:p")],
			[btn(claims ? `🧾 Заявки на оплату (${claims})` : "🧾 Заявки на оплату", "a:pq"), btn("⚙️ Настройки", "a:c")],
			[btn("🖼 Баннеры", "a:im"), btn("✨ Эмодзи", "a:em")],
			[btn("🔘 Кнопки", "a:bt"), btn("💾 Копии", "a:bk")],
			[btn("🔐 Пароль", "a:pw")],
			[btn("🔄 Импорт старых пользователей", "a:import")],
			[btn("← В меню", "menu")],
		])
	);
}

// ---------- stats ----------

async function showStats(ctx) {
	const users = await listUserSummaries(ctx.env);
	const orders = (await listOrderSummaries(ctx.env)).filter((order) => order.st === "paid" || order.st === "delivered");
	const banned = (await listAllKeys(ctx.env, "ban:")).length;
	const now = ctx.now;
	const count = (predicate) => users.filter(predicate).length;
	const versions = new Map();
	for (const user of users) {
		const version = user.v || "?";
		versions.set(version, (versions.get(version) ?? 0) + 1);
	}
	const versionLines = [...versions.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([version, n]) => `${esc(version)} — ${n}`);
	const asMoney = (list) => totalsText(list.map((order) => ({ stars: order.s, currency: order.c, amount: order.a })));
	const revenue = asMoney(orders);
	const revenue30 = asMoney(orders.filter((order) => now - (order.at || 0) < 30 * DAY_MS));
	const text = [
		"📊 <b>Статистика</b>",
		`Пользователей: <b>${users.length}</b> (запускали бота: ${count((u) => u.b)})`,
		`Онлайн (10 мин): ${count((u) => now - (u.ls || 0) < ONLINE_MS)} · за сутки: ${count((u) => now - (u.ls || 0) < DAY_MS)} · за неделю: ${count((u) => now - (u.ls || 0) < 7 * DAY_MS)}`,
		`Premium: ${count((u) => u.t === "pro")} · Standard: ${count((u) => u.t !== "pro")} · ключ активировали: ${count((u) => u.a)}`,
		`Заблокировано: ${banned}`,
		"",
		"<b>Версии приложения</b>",
		versionLines.join("\n") || "нет данных",
		"",
		`💰 Выручка: <b>${esc(revenue)}</b> (оплат: ${orders.length}), за 30 дней: ${esc(revenue30)}`,
	].join("\n");
	return show(ctx, text, kb([[btn("← Админка", "a:home")]]));
}

// ---------- users ----------

const FILTERS = { all: "Все", on: "24 ч", ban: "Баны", pro: "Premium" };

function userRow(user, bannedIds, now) {
	const dot = now - (user.ls || 0) < ONLINE_MS ? "🟢" : now - (user.ls || 0) < DAY_MS ? "🟡" : "⚪";
	const label = user.un ? `@${user.un}` : user.nm || `id ${user.id}`;
	const flags = `${user.t === "pro" ? "💎" : ""}${bannedIds.has(user.id) ? "⛔" : ""}`;
	const text = `${dot}${flags} ${label} · v${user.v || "?"} · ${fmtAgo(user.ls, now)}`;
	return [btn(text.slice(0, 60), `a:u:${user.id}`)];
}

async function showUsers(ctx, filter, page) {
	const bannedIds = new Set((await listAllKeys(ctx.env, "ban:")).map((key) => key.name.slice(4)));
	let users = await listUserSummaries(ctx.env);
	if (filter === "on") {
		users = users.filter((user) => ctx.now - (user.ls || 0) < DAY_MS);
	} else if (filter === "ban") {
		users = users.filter((user) => bannedIds.has(user.id));
	} else if (filter === "pro") {
		users = users.filter((user) => user.t === "pro");
	}
	const pages = Math.max(1, Math.ceil(users.length / PAGE_SIZE));
	const current = Math.min(Math.max(0, page), pages - 1);
	const slice = users.slice(current * PAGE_SIZE, (current + 1) * PAGE_SIZE);
	const rows = slice.map((user) => userRow(user, bannedIds, ctx.now));
	rows.push(Object.entries(FILTERS).map(([key, title]) => btn(key === filter ? `• ${title}` : title, `a:ul:${key}:0`)));
	const nav = [];
	if (current > 0) {
		nav.push(btn("⬅️", `a:ul:${filter}:${current - 1}`));
	}
	nav.push(btn(`${current + 1}/${pages}`, "a:noop"));
	if (current < pages - 1) {
		nav.push(btn("➡️", `a:ul:${filter}:${current + 1}`));
	}
	rows.push(nav);
	rows.push([btn("← Админка", "a:home")]);
	const title = `👥 <b>Пользователи</b> — ${FILTERS[filter] ?? "Все"}: ${users.length}\n🟢 онлайн · 🟡 сегодня · ⚪ давно · 💎 Premium · ⛔ бан`;
	return show(ctx, title, kb(rows));
}

async function profileText(ctx, id) {
	const [user, subscription, ban, check, orders] = await Promise.all([
		getUser(ctx.env, id),
		readSubscription(ctx.env, id),
		readBanRecord(ctx.env, id),
		getCheck(ctx.env, id),
		listUserOrders(ctx.env, id),
	]);
	const config = await getConfig(ctx.env);
	const tz = config.tz;
	const profile = user ?? { id, username: "", name: "", sessions: [], bot: null };
	const lines = [`👤 <b>${esc(displayName(profile))}</b>`, `id: <code>${esc(id)}</code>`];
	const until = subscription.expiresAt ? ` до ${esc(fmtTime(subscription.expiresAt, tz))}` : "";
	lines.push(`Уровень: <b>${tierLabel(subscription.tier)}</b>${until}`);
	lines.push(`Версия: ${profile.appVersion ? `${esc(profile.appVersion)}${profile.appBuild ? ` (${esc(profile.appBuild)})` : ""}` : "нет данных"}`);
	lines.push(`Первый вход: ${esc(fmtTime(profile.firstSeen, tz))}`);
	lines.push(`Последний: ${esc(fmtAgo(profile.lastSeen, ctx.now))}${profile.lastSeen ? ` (${esc(fmtTime(profile.lastSeen, tz))})` : ""}`);
	const sessions = (profile.sessions ?? []).slice(-8).reverse();
	lines.push(`Заходы (${(profile.sessions ?? []).length}): ${sessions.length ? sessions.map((ms) => esc(fmtTime(ms, tz).slice(0, 11) + fmtTime(ms, tz).slice(-5))).join(", ") : "нет данных"}`);
	lines.push(`Ключ активирован: ${profile.activatedAt ? `да (${esc(fmtTime(profile.activatedAt, tz))})` : "нет"}`);
	lines.push(`Бот: ${profile.bot ? (profile.bot.blocked ? "заблокировал бота" : "запускал") : "не запускал"}`);
	const paid = orders.filter((order) => order.status === "paid" || order.status === "delivered");
	lines.push(`Покупок: ${paid.length}${paid.length ? ` (${esc(totalsText(paid))})` : ""}`);
	if (ban.full) {
		lines.push(`⛔ <b>Заблокирован</b>: ${esc(ban.full.reason)}${ban.full.at ? ` (${esc(fmtTime(ban.full.at, tz))})` : ""}`);
	}
	if (check) {
		const state = check.status === "pending" ? `ждём ответа до ${fmtTime(check.expiresAt, tz)}` : check.status === "ok" ? `пройдена ${fmtTime(check.answeredAt, tz)}` : "не ответил вовремя";
		lines.push(`🔍 Проверка: ${esc(state)}`);
	}
	if (profile.note) {
		lines.push(`📝 ${esc(profile.note)}`);
	}
	return { text: lines.join("\n"), banned: Boolean(ban.full) };
}

async function showProfile(ctx, id) {
	if (!isValidAccountId(id)) {
		return toast(ctx, "Неверный id", true);
	}
	const { text, banned } = await profileText(ctx, id);
	const rows = [
		[banned ? btn("✅ Разбанить", `a:unban:${id}`) : btn("🚫 Забанить", `a:ban:${id}`), btn("🔍 На проверку в ЛС", `a:chk:${id}`)],
		[btn("💎 Выдать тариф", `a:gr:${id}`), btn("✉️ Написать", `a:dm:${id}`)],
		[btn("📝 Заметка", `a:note:${id}`), btn("🔄 Обновить", `a:u:${id}`)],
		[btn("← К списку", "a:ul:all:0")],
	];
	return show(ctx, text, kb(rows));
}

async function findUser(ctx, query) {
	const text = query.trim();
	if (/^\d{1,20}$/.test(text)) {
		await showProfile(ctx, text);
		return true;
	}
	const handle = text.replace(/^@/, "").toLowerCase();
	const users = await listUserSummaries(ctx.env);
	const matches = users.filter((user) => user.un === handle || (user.nm || "").toLowerCase().includes(handle)).slice(0, 8);
	if (matches.length === 0) {
		await say(ctx, "Никого не нашёл. Пришлите id или @ник ещё раз или нажмите «Отмена».", CANCEL);
		return false;
	}
	if (matches.length === 1) {
		await showProfile({ ...ctx, callback: null }, matches[0].id);
		return true;
	}
	await say(ctx, "Нашёл несколько:", kb([...matches.map((user) => userRow(user, new Set(), ctx.now)), [btn("← Админка", "a:home")]]));
	return true;
}

// ---------- ban / check / grant / dm ----------

async function applyBan(ctx, id, reason) {
	const record = await readBanRecord(ctx.env, id);
	record.full = { reason, at: ctx.now };
	await writeBanRecord(ctx.env, id, record);
	await trySend(ctx.tg, id, `⛔ Ваш доступ ограничен.\nПричина: ${esc(reason)}`);
	await showProfile({ ...ctx, callback: null }, id);
}

async function applyUnban(ctx, id) {
	const record = await readBanRecord(ctx.env, id);
	record.full = null;
	await writeBanRecord(ctx.env, id, record);
	await trySend(ctx.tg, id, "✅ Ограничения сняты.");
	await toast(ctx, "Разбанен");
	return showProfile(ctx, id);
}

async function requestCheck(ctx, id) {
	const check = { status: "pending", requestedAt: ctx.now, expiresAt: ctx.now + CHECK_TTL_MS, by: String(ctx.from.id), answeredAt: null };
	const delivered = await trySend(
		ctx.tg,
		id,
		"🔍 <b>Проверка аккаунта</b>\nАдминистратор просит подтвердить, что вы на связи. Нажмите кнопку в течение 15 минут.",
		kb([[btn("✅ Я здесь", "ck:ok")]])
	);
	if (!delivered) {
		await toast(ctx, "Не удалось написать: пользователь не запускал бота или заблокировал его", true);
		return;
	}
	await saveCheck(ctx.env, id, check);
	await toast(ctx, "Запрос отправлен, жду ответа 15 минут", true);
	return showProfile(ctx, id);
}

/** A user pressing "Я здесь" on a verification request. */
export async function answerCheck(ctx) {
	const id = String(ctx.from.id);
	const check = await getCheck(ctx.env, id);
	if (!check || check.status !== "pending") {
		await toast(ctx, "Запрос уже неактуален");
		return;
	}
	check.status = "ok";
	check.answeredAt = ctx.now;
	await saveCheck(ctx.env, id, check);
	await toast(ctx, "Спасибо, проверка пройдена");
	await show(ctx, "✅ Проверка пройдена. Спасибо!");
	await trySend(ctx.tg, check.by, `✅ ${esc(displayName((await getUser(ctx.env, id)) ?? { id }))} прошёл проверку.`, kb([[btn("👤 Профиль", `a:u:${id}`)]]));
}

/** Cron: pending verifications that ran out of time. */
export async function expireChecks(env, tg, now) {
	for (const { userId, check } of await listChecks(env)) {
		if (check.status === "pending" && check.expiresAt <= now) {
			check.status = "expired";
			await saveCheck(env, userId, check);
			const user = await getUser(env, userId);
			await trySend(tg, check.by, `⌛ ${esc(displayName(user ?? { id: userId }))} не ответил на проверку.`, kb([[btn("👤 Профиль", `a:u:${userId}`)]]));
		}
	}
}

const GRANTS = {
	std: { label: "Standard (сбросить Premium)", tier: "standard", hours: 0 },
	p7: { label: "Premium 7 дней", tier: "pro", hours: 168 },
	p30: { label: "Premium 30 дней", tier: "pro", hours: 720 },
	pf: { label: "Premium навсегда", tier: "pro", hours: 0 },
};

async function applyGrant(ctx, id, option) {
	const grant = GRANTS[option];
	if (!grant) {
		return toast(ctx, "Неизвестный вариант", true);
	}
	await ctx.env.SUBS.put(`tier_changed:${id}`, String(ctx.now));
	await writeSubscription(ctx.env, id, grant.tier, grant.hours);
	await noteTier(ctx.env, id, grant.tier, ctx.now);
	await trySend(ctx.tg, id, `💎 Вам выдан уровень: <b>${tierLabel(grant.tier)}</b>${grant.hours ? ` на ${fmtHours(grant.hours)}` : ""}.`);
	await toast(ctx, "Готово");
	return showProfile(ctx, id);
}

// ---------- tariffs ----------

async function showTariffList(ctx) {
	const tariffs = await getTariffs(ctx.env);
	const rows = tariffs.map((tariff) => [btn(`${tariff.active ? "✅" : "⏸"} ${tariff.title} — ${tariff.stars} ⭐`, `a:t:${tariff.code}`)]);
	rows.push([btn("➕ Добавить", "a:ta")]);
	rows.push([btn("← Админка", "a:home")]);
	return show(ctx, "💰 <b>Тарифы</b>\nЦены в Telegram Stars. Standard — навсегда; срок работает для Premium.", kb(rows));
}

async function showTariffCard(ctx, code) {
	const tariff = (await getTariffs(ctx.env)).find((item) => item.code === code);
	if (!tariff) {
		return showTariffList(ctx);
	}
	const text = [
		`<b>${esc(tariff.title)}</b> (<code>${esc(tariff.code)}</code>)`,
		esc(tariff.desc ?? ""),
		`Уровень: ${tierLabel(tariff.tier)} · срок: ${fmtHours(tariff.hours)} · цена: ${tariff.stars} ⭐`,
		tariff.requires ? `Нужна покупка: ${tierLabel(tariff.requires)}` : "",
		`Эмодзи на кнопке: ${tariff.emoji ? `${esc(tariff.emoji)}${tariff.icon ? " (анимированный)" : ""}` : "нет"}`,
		`Статус: ${tariff.active ? "продаётся" : "выключен"}`,
	].filter(Boolean).join("\n");
	return show(
		ctx,
		text,
		kb([
			[btn(tariff.active ? "⏸ Выключить" : "▶️ Включить", `a:tt:${code}`), btn("💲 Цена", `a:tp:${code}`)],
			[btn("✏️ Название", `a:tn:${code}`), btn("📝 Описание", `a:td:${code}`)],
			[btn("🙂 Эмодзи на кнопке", `a:te:${code}`)],
			[btn("🗑 Удалить", `a:tx:${code}`), btn("← К тарифам", "a:t")],
		])
	);
}

async function editTariff(ctx, code, mutate) {
	const tariffs = await getTariffs(ctx.env);
	const tariff = tariffs.find((item) => item.code === code);
	if (!tariff) {
		return false;
	}
	mutate(tariff, tariffs);
	await saveTariffs(ctx.env, tariffs);
	return true;
}

function parseTariffLine(text, existing) {
	const parts = text.split("|").map((part) => part.trim());
	if (parts.length < 5) {
		return { error: "Нужно 5-6 полей через |: код | название | standard или pro | цена в ⭐ | часы (0 = навсегда) | требует (необязательно)" };
	}
	const [code, title, tier, stars, hours, requires = ""] = parts;
	if (!/^[a-z0-9-]{1,16}$/.test(code)) {
		return { error: "Код: латиница, цифры и дефис, до 16 символов." };
	}
	if (existing.some((tariff) => tariff.code === code)) {
		return { error: "Такой код уже есть." };
	}
	if (!title || title.length > 60) {
		return { error: "Название: 1-60 символов." };
	}
	if (!ALLOWED_TIERS.has(tier)) {
		return { error: "Уровень: standard или pro." };
	}
	const price = Number(stars);
	if (!Number.isInteger(price) || price < 1 || price > 100000) {
		return { error: "Цена: целое число от 1 до 100000." };
	}
	const duration = Number(hours);
	if (!Number.isFinite(duration) || duration < 0) {
		return { error: "Часы: число 0 или больше." };
	}
	if (requires && !ALLOWED_TIERS.has(requires)) {
		return { error: "«Требует»: standard, pro или пусто." };
	}
	return { tariff: { code, title, tier, stars: price, hours: duration, desc: "", active: true, requires } };
}

// ---------- delivery set ----------

const tiersLabel = (tiers) => `${tiers.includes("standard") ? "S" : ""}${tiers.includes("pro") ? "P" : ""}` || "—";
const KIND_ICON = { file: "📄", link: "🔗", text: "📝" };

async function showBundleList(ctx) {
	const items = await getBundle(ctx.env);
	const rows = items.map((item) => [btn(`${KIND_ICON[item.kind] ?? "•"} ${item.title} [${tiersLabel(item.tiers ?? [])}]`.slice(0, 60), `a:b:${item.id}`)]);
	rows.push([btn("➕ Файл", "a:baf"), btn("➕ Ссылка", "a:bal"), btn("➕ Текст", "a:bat")]);
	rows.push([btn("← Админка", "a:home")]);
	return show(
		ctx,
		"📦 <b>Комплект выдачи</b>\nЧто получает покупатель после оплаты: приложение, сертификат, инструкции.\nS — Standard, P — Premium. Файлы пришлите боту (любой размер), он запомнит их.",
		kb(rows)
	);
}

async function showBundleCard(ctx, id) {
	const item = (await getBundle(ctx.env)).find((entry) => entry.id === id);
	if (!item) {
		return showBundleList(ctx);
	}
	const tiers = item.tiers ?? [];
	const detail = item.kind === "file" ? "файл в Telegram" : item.kind === "link" ? esc(item.url) : esc((item.text ?? "").slice(0, 200));
	return show(
		ctx,
		`${KIND_ICON[item.kind] ?? ""} <b>${esc(item.title)}</b>\n${detail}`,
		kb([
			[btn(`${tiers.includes("standard") ? "✅" : "❌"} Standard`, `a:bg:${id}:standard`), btn(`${tiers.includes("pro") ? "✅" : "❌"} Premium`, `a:bg:${id}:pro`)],
			[btn("✏️ Название", `a:bn:${id}`), btn("🗑 Удалить", `a:bd:${id}`)],
			[btn("← К комплекту", "a:b")],
		])
	);
}

function extractFile(message) {
	if (message.document) {
		return { fileId: message.document.file_id, title: message.document.file_name };
	}
	if (message.video) {
		return { fileId: message.video.file_id, title: message.video.file_name };
	}
	if (message.audio) {
		return { fileId: message.audio.file_id, title: message.audio.file_name };
	}
	if (message.animation) {
		return { fileId: message.animation.file_id, title: message.animation.file_name };
	}
	if (message.photo?.length) {
		return { fileId: message.photo[message.photo.length - 1].file_id, title: "Фото" };
	}
	return null;
}

// ---------- settings ----------

async function showSettings(ctx) {
	const config = await getConfig(ctx.env);
	const text = [
		"⚙️ <b>Настройки бота</b>",
		`Поддержка: ${config.support ? esc(config.support) : "не задана"}`,
		`Часовой пояс: ${esc(config.tz)}`,
		"",
		"<b>Приветствие</b>",
		config.welcome,
		"",
		"<b>Инструкция после покупки</b>",
		esc(config.howto),
	].join("\n");
	return show(
		ctx,
		text,
		kb([
			[btn("✏️ Приветствие", "a:cf:welcome"), btn("✏️ Инструкция", "a:cf:howto")],
			[btn("💬 Поддержка", "a:cf:support"), btn("🕒 Часовой пояс", "a:cf:tz")],
			[btn(`⭐ Звезда на кнопках тарифов: ${config.starFront ? "спереди (анимируется)" : "в конце"}`, "a:cs")],
			[btn("← Админка", "a:home")],
		])
	);
}

// ---------- router ----------

/** `data` is the callback data without the leading "a:". */
export async function adminCallback(ctx, data) {
	const parts = data.split(":");
	const action = parts[0];
	const arg = parts[1];
	if (GUARDED.has(action) && !ctx.pwOk) {
		await toast(ctx);
		return askPassword(ctx, data);
	}
	switch (action) {
		case "home":
			await toast(ctx);
			return adminHome(ctx);
		case "noop":
			return toast(ctx);
		case "cancel":
			await clearState(ctx.env, ctx.from.id);
			await toast(ctx, "Отменено");
			return adminHome(ctx);
		case "stats":
			await toast(ctx);
			return showStats(ctx);
		case "ul":
			await toast(ctx);
			return showUsers(ctx, FILTERS[arg] ? arg : "all", parseInt(parts[2], 10) || 0);
		case "u":
			await toast(ctx);
			return showProfile(ctx, arg);
		case "find":
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "find" });
			return show(ctx, "Пришлите id или @ник пользователя.", CANCEL);
		case "ban":
			if (!isValidAccountId(arg)) {
				return toast(ctx, "Неверный id", true);
			}
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "ban", id: arg });
			return show(ctx, "Причина блокировки? Пользователь её увидит.", CANCEL);
		case "unban":
			return isValidAccountId(arg) ? applyUnban(ctx, arg) : toast(ctx, "Неверный id", true);
		case "chk":
			return isValidAccountId(arg) ? requestCheck(ctx, arg) : toast(ctx, "Неверный id", true);
		case "gr": {
			if (!isValidAccountId(arg)) {
				return toast(ctx, "Неверный id", true);
			}
			await toast(ctx);
			const rows = Object.entries(GRANTS).map(([key, grant]) => [btn(grant.label, `a:g:${arg}:${key}`)]);
			rows.push([btn("← Профиль", `a:u:${arg}`)]);
			return show(ctx, "Какой уровень выдать?", kb(rows));
		}
		case "g":
			return isValidAccountId(arg) ? applyGrant(ctx, arg, parts[2]) : toast(ctx, "Неверный id", true);
		case "dm":
			if (!isValidAccountId(arg)) {
				return toast(ctx, "Неверный id", true);
			}
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "dm", id: arg });
			return show(ctx, "Что отправить пользователю? Напишите сообщение.", CANCEL);
		case "note":
			if (!isValidAccountId(arg)) {
				return toast(ctx, "Неверный id", true);
			}
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "note", id: arg });
			return show(ctx, "Текст заметки (пустое «-» стирает).", CANCEL);
		case "import": {
			await toast(ctx);
			const imported = await importLegacyUsers(ctx.env);
			return show(ctx, `Импортировано профилей: <b>${imported}</b>`, kb([[btn("← Админка", "a:home")]]));
		}
		case "t":
			await toast(ctx);
			return arg ? showTariffCard(ctx, arg) : showTariffList(ctx);
		case "tt":
			await editTariff(ctx, arg, (tariff) => {
				tariff.active = !tariff.active;
			});
			await toast(ctx);
			return showTariffCard(ctx, arg);
		case "tx":
			await saveTariffs(ctx.env, (await getTariffs(ctx.env)).filter((tariff) => tariff.code !== arg));
			await toast(ctx, "Удалён");
			return showTariffList(ctx);
		case "tp":
		case "tn":
		case "td": {
			await toast(ctx);
			const field = { tp: "price", tn: "title", td: "desc" }[action];
			await setState(ctx.env, ctx.from.id, { a: "tariff_edit", code: arg, field });
			const prompt = { price: "Новая цена в ⭐ (целое число).", title: "Новое название.", desc: "Новое описание." }[field];
			return show(ctx, prompt, CANCEL);
		}
		case "te":
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "tariff_emoji", code: arg });
			return show(ctx, "Пришлите эмодзи для кнопки этого тарифа: обычный или анимированный (Premium). «-» уберёт эмодзи.", kb([[btn("✖️ Отмена", `a:t:${arg}`)]]));
		case "ta":
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "tariff_add" });
			return show(ctx, "Новый тариф одной строкой:\n<code>код | название | standard или pro | цена ⭐ | часы (0 = навсегда) | требует</code>\nПример:\n<code>pro90 | Premium · 90 дней | pro | 1200 | 2160</code>", CANCEL);
		case "b":
			await toast(ctx);
			return arg ? showBundleCard(ctx, arg) : showBundleList(ctx);
		case "baf":
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "bundle_file" });
			return show(ctx, "Пришлите файл (документ, видео, фото). Для .ipa и сертификатов — как документ.", CANCEL);
		case "bal":
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "bundle_link" });
			return show(ctx, "Ссылка одной строкой:\n<code>Название | https://…</code>", CANCEL);
		case "bat":
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "bundle_text" });
			return show(ctx, "Текст одной строкой (например, пароль сертификата):\n<code>Название | текст</code>", CANCEL);
		case "bg": {
			const items = await getBundle(ctx.env);
			const item = items.find((entry) => entry.id === arg);
			if (item && ALLOWED_TIERS.has(parts[2])) {
				const tiers = new Set(item.tiers ?? []);
				tiers.has(parts[2]) ? tiers.delete(parts[2]) : tiers.add(parts[2]);
				item.tiers = [...tiers];
				await saveBundle(ctx.env, items);
			}
			await toast(ctx);
			return showBundleCard(ctx, arg);
		}
		case "bn":
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "bundle_rename", id: arg });
			return show(ctx, "Новое название.", CANCEL);
		case "bd":
			await saveBundle(ctx.env, (await getBundle(ctx.env)).filter((entry) => entry.id !== arg));
			await toast(ctx, "Удалено");
			return showBundleList(ctx);
		case "c":
			await toast(ctx);
			return showSettings(ctx);
		case "cs": {
			const config = await getConfig(ctx.env);
			await setConfig(ctx.env, { starFront: !config.starFront });
			await toast(ctx, !config.starFront ? "Звезда теперь спереди" : "Звезда в конце");
			return showSettings(ctx);
		}
		case "cf": {
			await toast(ctx);
			if (!["welcome", "howto", "support", "tz"].includes(arg)) {
				return;
			}
			await setState(ctx.env, ctx.from.id, { a: "cfg", field: arg });
			const prompt = {
				welcome: "Новый текст приветствия (можно HTML: <b>, <i>).",
				howto: "Новая инструкция после покупки.",
				support: "Ник поддержки, например @name (или «-», чтобы убрать).",
				tz: "Часовой пояс, например Europe/Moscow.",
			}[arg];
			return show(ctx, prompt, CANCEL);
		}
		default:
			if (action === "pw") {
				await toast(ctx);
				return showPasswordMenu(ctx);
			}
			if ((await payCallback(ctx, parts)) || (await visualsCallback(ctx, parts)) || (await buttonsCallback(ctx, parts)) || (await backupCallback(ctx, parts))) {
				return;
			}
			return toast(ctx, "Неизвестное действие");
	}
}

/**
 * An admin message while a prompt is open (state set by a button). Returns true when the
 * message was consumed as an answer.
 */
export async function adminInput(ctx, message) {
	const state = await getState(ctx.env, ctx.from.id);
	if (!state) {
		return false;
	}
	const text = (message.text ?? message.caption ?? "").trim();
	const done = async () => {
		await clearState(ctx.env, ctx.from.id);
	};
	if (await securityInput(ctx, state, message, text, adminCallback, (c, data) => makeBackup(c.env, `перед удалением (${String(data).split(":")[0]})`, c.now))) {
		return true;
	}
	if (await payInput(ctx, state, text)) {
		return true;
	}
	if (await buttonsInput(ctx, state, message, text)) {
		return true;
	}
	if (await visualsInput(ctx, state, message)) {
		return true;
	}
	switch (state.a) {
		case "find":
			if (await findUser({ ...ctx, callback: null }, text)) {
				await done();
			}
			return true;
		case "ban":
			if (!text) {
				await say(ctx, "Причину нужно написать текстом.", CANCEL);
				return true;
			}
			await done();
			await applyBan(ctx, state.id, text.slice(0, 200));
			return true;
		case "dm": {
			await done();
			const sent = await trySend(ctx.tg, state.id, text, {});
			await say(ctx, sent ? "✉️ Отправлено." : "Не удалось отправить: пользователь не запускал бота или заблокировал его.", kb([[btn("👤 Профиль", `a:u:${state.id}`)]]));
			return true;
		}
		case "note":
			await done();
			await updateUser(ctx.env, state.id, (user) => {
				user.note = text === "-" ? "" : text.slice(0, 300);
			}, ctx.now);
			await showProfile({ ...ctx, callback: null }, state.id);
			return true;
		case "tariff_add": {
			const existing = await getTariffs(ctx.env);
			const parsed = parseTariffLine(text, existing);
			if (parsed.error) {
				await say(ctx, `${esc(parsed.error)}\nПопробуйте ещё раз или нажмите «Отмена».`, CANCEL);
				return true;
			}
			await saveTariffs(ctx.env, [...existing, parsed.tariff]);
			await done();
			await showTariffCard({ ...ctx, callback: null }, parsed.tariff.code);
			return true;
		}
		case "tariff_emoji": {
			let patch;
			if (text === "-") {
				patch = { emoji: "", icon: "" };
			} else {
				const found = readEmoji(message, text);
				if (!found) {
					await say(ctx, "Не вижу эмодзи. Пришлите одно эмодзи (или «-», чтобы убрать).", kb([[btn("✖️ Отмена", `a:t:${state.code}`)]]));
					return true;
				}
				patch = { emoji: found.emoji, icon: found.icon ?? "" };
			}
			await editTariff(ctx, state.code, (tariff) => Object.assign(tariff, patch));
			await done();
			await showTariffCard({ ...ctx, callback: null }, state.code);
			return true;
		}
		case "tariff_edit": {
			let value = text;
			if (state.field === "price") {
				value = Number(text);
				if (!Number.isInteger(value) || value < 1 || value > 100000) {
					await say(ctx, "Нужно целое число от 1 до 100000.", CANCEL);
					return true;
				}
			} else if (!text || text.length > 120) {
				await say(ctx, "Нужен текст до 120 символов.", CANCEL);
				return true;
			}
			await editTariff(ctx, state.code, (tariff) => {
				tariff[state.field === "price" ? "stars" : state.field] = value;
			});
			await done();
			await showTariffCard({ ...ctx, callback: null }, state.code);
			return true;
		}
		case "bundle_file": {
			const file = extractFile(message);
			if (!file) {
				await say(ctx, "Это не файл. Пришлите документ, видео или фото.", CANCEL);
				return true;
			}
			const items = await getBundle(ctx.env);
			const item = { id: newId(6), kind: "file", title: (text || file.title || "Файл").slice(0, 60), fileId: file.fileId, tiers: ["standard", "pro"] };
			await saveBundle(ctx.env, [...items, item]);
			await done();
			await showBundleCard({ ...ctx, callback: null }, item.id);
			return true;
		}
		case "bundle_link":
		case "bundle_text": {
			const split = text.indexOf("|");
			const title = split > 0 ? text.slice(0, split).trim() : "";
			const value = split > 0 ? text.slice(split + 1).trim() : "";
			if (!title || !value || (state.a === "bundle_link" && !/^https?:\/\//i.test(value))) {
				await say(ctx, state.a === "bundle_link" ? "Формат: Название | https://…" : "Формат: Название | текст", CANCEL);
				return true;
			}
			const items = await getBundle(ctx.env);
			const item = state.a === "bundle_link"
				? { id: newId(6), kind: "link", title: title.slice(0, 60), url: value, tiers: ["standard", "pro"] }
				: { id: newId(6), kind: "text", title: title.slice(0, 60), text: value.slice(0, 1500), tiers: ["standard", "pro"] };
			await saveBundle(ctx.env, [...items, item]);
			await done();
			await showBundleCard({ ...ctx, callback: null }, item.id);
			return true;
		}
		case "bundle_rename": {
			const items = await getBundle(ctx.env);
			const item = items.find((entry) => entry.id === state.id);
			if (item && text) {
				item.title = text.slice(0, 60);
				await saveBundle(ctx.env, items);
			}
			await done();
			await showBundleCard({ ...ctx, callback: null }, state.id);
			return true;
		}
		case "cfg": {
			if (!text) {
				await say(ctx, "Нужен текст.", CANCEL);
				return true;
			}
			const value = state.field === "support" ? (text === "-" ? "" : text.slice(0, 40)) : text.slice(0, 3000);
			if (state.field === "tz") {
				try {
					new Intl.DateTimeFormat("ru-RU", { timeZone: value });
				} catch {
					await say(ctx, "Не знаю такого пояса. Пример: Europe/Moscow.", CANCEL);
					return true;
				}
			}
			await setConfig(ctx.env, { [state.field]: value });
			await done();
			await showSettings({ ...ctx, callback: null });
			return true;
		}
		default:
			await done();
			return false;
	}
}
