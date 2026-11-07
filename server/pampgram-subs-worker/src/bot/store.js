/**
 * Bot storage on the shared KV namespace.
 *
 *   "cfg"                    -> JSON bot settings (welcome text, support handle, timezone)
 *   "tariffs"                -> JSON array of tariffs (seeded with defaults until first edited)
 *   "bundle"                 -> JSON array of delivery items (files by Telegram file_id, links, text)
 *   "order:<id>"             -> JSON order; KV metadata { st, s, at, tr } for cheap totals
 *   "ordu:<userId>:<id>"     -> "1" marker so one user's orders can be listed by prefix
 *   "charge:<chargeId>"      -> orderId, so a repeated payment notification is applied once
 *   "st:<adminId>"           -> JSON conversation state of an admin mid-prompt (1 h TTL)
 *   "check:<userId>"         -> JSON "come verify in DM" request
 *   "pay"                    -> JSON array of payment methods (built-in Stars + manual requisites)
 *   "ust:<userId>"           -> JSON { orderId }: a buyer who said "I paid" and may send a receipt (24 h TTL)
 */

import { listAllKeys } from "../core.js";

export const DEFAULT_CONFIG = {
	welcome: "👋 <b>PampGram</b> — мод для Telegram.\n\nЗдесь можно оформить доступ, получить файлы для установки и ключ активации.",
	support: "",
	tz: "Europe/Moscow",
	howto: "Как установить:\n1) скачайте файлы выше;\n2) установите приложение по инструкции из комплекта;\n3) при первом запуске введите ключ активации.",
};

export const DEFAULT_TARIFFS = [
	{ code: "std", title: "Standard", tier: "standard", stars: 200, hours: 0, desc: "Основные функции мода, навсегда.", active: true, requires: "" },
	{ code: "pro30", title: "Premium · 30 дней", tier: "pro", stars: 500, hours: 720, desc: "Все функции мода на 30 дней.", active: true, requires: "" },
	{ code: "pro", title: "Premium · навсегда", tier: "pro", stars: 2000, hours: 0, desc: "Все функции мода без ограничения по времени.", active: true, requires: "" },
	{ code: "up", title: "Доплата Standard → Premium", tier: "pro", stars: 1500, hours: 0, desc: "Для тех, кто уже купил Standard.", active: true, requires: "standard" },
];

async function readJson(env, key) {
	const raw = await env.SUBS.get(key);
	if (!raw) {
		return null;
	}
	try {
		return JSON.parse(raw);
	} catch {
		return null;
	}
}

export async function getConfig(env) {
	return { ...DEFAULT_CONFIG, ...((await readJson(env, "cfg")) ?? {}) };
}

export async function setConfig(env, patch) {
	const next = { ...(await getConfig(env)), ...patch };
	await env.SUBS.put("cfg", JSON.stringify(next));
	return next;
}

export async function getTariffs(env) {
	const stored = await readJson(env, "tariffs");
	return Array.isArray(stored) ? stored : DEFAULT_TARIFFS.map((tariff) => ({ ...tariff }));
}

export async function saveTariffs(env, tariffs) {
	await env.SUBS.put("tariffs", JSON.stringify(tariffs));
}

export const STARS_METHOD = { id: "stars", kind: "stars", title: "Telegram Stars", active: true };

/** Payment methods; the built-in Stars method is always present (it can be switched off, not removed). */
export async function getPayMethods(env) {
	const stored = await readJson(env, "pay");
	const methods = Array.isArray(stored) ? stored : [];
	return methods.some((method) => method.kind === "stars") ? methods : [{ ...STARS_METHOD }, ...methods];
}

export async function savePayMethods(env, methods) {
	await env.SUBS.put("pay", JSON.stringify(methods));
}

export async function getUserState(env, userId) {
	return readJson(env, `ust:${userId}`);
}

export async function setUserState(env, userId, state) {
	await env.SUBS.put(`ust:${userId}`, JSON.stringify(state), { expirationTtl: 24 * 3600 });
}

export async function clearUserState(env, userId) {
	await env.SUBS.delete(`ust:${userId}`);
}

export async function getBundle(env) {
	const stored = await readJson(env, "bundle");
	return Array.isArray(stored) ? stored : [];
}

export async function saveBundle(env, items) {
	await env.SUBS.put("bundle", JSON.stringify(items));
}

export function newId(length = 8) {
	const alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
	const bytes = new Uint8Array(length);
	crypto.getRandomValues(bytes);
	let out = "";
	for (const byte of bytes) {
		out += alphabet[byte % alphabet.length];
	}
	return out;
}

function orderMeta(order) {
	const meta = { st: order.status, s: order.stars, at: order.createdAt, tr: order.tariff, u: order.userId };
	if (order.currency) {
		// manual (non-Stars) order: carry the amount so totals need no order bodies
		meta.c = order.currency;
		meta.a = order.amount;
	}
	return meta;
}

export async function saveOrder(env, order) {
	await env.SUBS.put(`order:${order.id}`, JSON.stringify(order), { metadata: orderMeta(order) });
	await env.SUBS.put(`ordu:${order.userId}:${order.id}`, "1");
}

export async function getOrder(env, id) {
	return readJson(env, `order:${id}`);
}

export async function listUserOrders(env, userId) {
	const keys = await listAllKeys(env, `ordu:${userId}:`);
	const orders = await Promise.all(keys.map((key) => getOrder(env, key.name.split(":")[2])));
	return orders.filter(Boolean).sort((a, b) => b.createdAt - a.createdAt);
}

/** Summaries (no order bodies read) for revenue totals. */
export async function listOrderSummaries(env) {
	const keys = await listAllKeys(env, "order:");
	return keys.map((key) => ({ id: key.name.slice(6), ...(key.metadata ?? {}) }));
}

export async function markCharge(env, chargeId, orderId) {
	await env.SUBS.put(`charge:${chargeId}`, orderId);
}

export async function chargeOrder(env, chargeId) {
	return env.SUBS.get(`charge:${chargeId}`);
}

export async function getState(env, adminId) {
	return readJson(env, `st:${adminId}`);
}

export async function setState(env, adminId, state) {
	await env.SUBS.put(`st:${adminId}`, JSON.stringify(state), { expirationTtl: 3600 });
}

export async function clearState(env, adminId) {
	await env.SUBS.delete(`st:${adminId}`);
}

export async function getCheck(env, userId) {
	return readJson(env, `check:${userId}`);
}

export async function saveCheck(env, userId, check) {
	await env.SUBS.put(`check:${userId}`, JSON.stringify(check));
}

export async function listChecks(env) {
	const keys = await listAllKeys(env, "check:");
	const checks = await Promise.all(keys.map(async (key) => ({ userId: key.name.slice(6), check: await readJson(env, key.name) })));
	return checks.filter((entry) => entry.check);
}

export function adminIds(env) {
	return String(env.ADMIN_TG_IDS ?? "")
		.split(/[,\s]+/)
		.filter((value) => /^\d+$/.test(value));
}

export const isAdmin = (env, id) => adminIds(env).includes(String(id));
