/**
 * Snapshots of everything the owner configured (settings, tariffs, delivery set, payment methods, emoji,
 * banners, buttons). One is taken automatically before every password-confirmed deletion, so a deletion
 * can always be undone from "💾 Копии". Orders and users are not part of it.
 */

import { show, toast } from "./context.js";
import { btn, kb, esc, fmtTime } from "./ui.js";
import { listAllKeys } from "../core.js";

export const BACKUP_KEYS = ["cfg", "tariffs", "bundle", "pay", "emoji", "banners", "buttons", "products", "texts"];
const KEEP = 12;

export async function makeBackup(env, reason, now = Date.now()) {
	// two copies in the same millisecond must never share a key (the second would overwrite the first)
	while ((await env.SUBS.get(`bk:${now}`)) !== null) {
		now++;
	}
	const data = {};
	for (const key of BACKUP_KEYS) {
		data[key] = await env.SUBS.get(key);
	}
	await env.SUBS.put(`bk:${now}`, JSON.stringify({ at: now, reason: String(reason ?? "").slice(0, 60), data }), { metadata: { at: now, r: String(reason ?? "").slice(0, 60) } });
	const keys = (await listAllKeys(env, "bk:")).map((key) => key.name).sort();
	for (const old of keys.slice(0, Math.max(0, keys.length - KEEP))) {
		await env.SUBS.delete(old);
	}
	return now;
}

export async function listBackups(env) {
	const keys = await listAllKeys(env, "bk:");
	return keys.map((key) => ({ at: Number(key.name.slice(3)), reason: key.metadata?.r ?? "" })).sort((a, b) => b.at - a.at);
}

export async function restoreBackup(env, at) {
	const raw = await env.SUBS.get(`bk:${at}`);
	if (!raw) {
		return false;
	}
	const { data } = JSON.parse(raw);
	for (const key of BACKUP_KEYS) {
		if (data[key] == null) {
			await env.SUBS.delete(key);
		} else {
			await env.SUBS.put(key, data[key]);
		}
	}
	return true;
}

export async function showBackups(ctx) {
	const list = (await listBackups(ctx.env)).slice(0, 6);
	const rows = list.map((item) => [btn(`↩️ ${fmtTime(item.at)} · ${item.reason || "вручную"}`.slice(0, 60), `a:bkr:${item.at}`)]);
	rows.push([btn("💾 Сделать копию сейчас", "a:bkn")]);
	rows.push([btn("← Админка", "a:home")]);
	return show(
		ctx,
		`💾 <b>Копии настроек</b>\nКопия делается сама перед каждым удалением. Нажмите на копию, чтобы вернуть настройки (нужен пароль).${list.length ? "" : "\n\nКопий пока нет."}`,
		kb(rows)
	);
}

export async function backupCallback(ctx, parts, run) {
	const [action, arg] = parts;
	if (action === "bk") {
		await toast(ctx);
		await showBackups(ctx);
		return true;
	}
	if (action === "bkn") {
		await makeBackup(ctx.env, "вручную", ctx.now);
		await toast(ctx, "Копия сохранена");
		await showBackups(ctx);
		return true;
	}
	if (action === "bkr") {
		const ok = await restoreBackup(ctx.env, arg);
		await show(ctx, ok ? `✅ Настройки возвращены из копии ${esc(fmtTime(Number(arg)))}.` : "Копия не найдена.", kb([[btn("← Админка", "a:home")]]));
		return true;
	}
	return false;
}
