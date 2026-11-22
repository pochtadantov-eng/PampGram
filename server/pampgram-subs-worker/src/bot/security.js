/**
 * The owner's password for destructive actions (deleting what was built in the admin panel, resetting,
 * restoring a backup). Only a salted SHA-256 of it is stored, in KV under "pw"; it is never in the code or
 * in the repository. Wrong attempts lock the prompt for a while.
 */

import { show, say } from "./context.js";
import { btn, kb } from "./ui.js";
import { getState, setState, clearState } from "./store.js";

const MAX_TRIES = 5;
const LOCK_MS = 10 * 60 * 1000;

async function sha256(text) {
	const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
	return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function randomSalt() {
	const bytes = new Uint8Array(16);
	crypto.getRandomValues(bytes);
	return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function hashPassword(password, salt = randomSalt()) {
	return { salt, hash: await sha256(`${salt}:${password}`) };
}

export async function setPassword(env, password) {
	await env.SUBS.put("pw", JSON.stringify(await hashPassword(password)));
	await env.SUBS.delete("pwfail");
}

export async function hasPassword(env) {
	return Boolean(await env.SUBS.get("pw"));
}

/** ms of lockout left, 0 when not locked. */
export async function lockedFor(env, now = Date.now()) {
	try {
		const fail = JSON.parse((await env.SUBS.get("pwfail")) ?? "null");
		return fail && fail.until > now ? fail.until - now : 0;
	} catch {
		return 0;
	}
}

/** true / false; counts failures and locks after too many. */
export async function verifyPassword(env, input, now = Date.now()) {
	let stored;
	try {
		stored = JSON.parse((await env.SUBS.get("pw")) ?? "null");
	} catch {
		stored = null;
	}
	if (!stored || (await lockedFor(env, now)) > 0) {
		return false;
	}
	const ok = (await hashPassword(String(input), stored.salt)).hash === stored.hash;
	if (ok) {
		await env.SUBS.delete("pwfail");
		return true;
	}
	let fail;
	try {
		fail = JSON.parse((await env.SUBS.get("pwfail")) ?? "null");
	} catch {
		fail = null;
	}
	const n = ((fail && !(fail.until && fail.until <= now) ? fail.n : 0) || 0) + 1;
	await env.SUBS.put("pwfail", JSON.stringify(n >= MAX_TRIES ? { n: 0, until: now + LOCK_MS } : { n, until: 0 }));
	return false;
}

const CANCEL = kb([[btn("✖️ Отмена", "a:cancel")]]);

/** Actions that remove what the owner built. They run only after the password. */
export const GUARDED = new Set(["tx", "bd", "pdel", "imd", "emd", "emr", "btx", "btr", "bkr", "sxx", "tkr"]);

export async function askPassword(ctx, data) {
	if (!(await hasPassword(ctx.env))) {
		return show(ctx, "🔐 Пароль для удаления ещё не задан. Задайте его: /admin → 🔐 Пароль.", kb([[btn("🔐 Задать пароль", "a:pw")], [btn("← Админка", "a:home")]]));
	}
	await setState(ctx.env, ctx.from.id, { a: "pw", data });
	return show(ctx, "🔐 Это удаляет сделанное вами. Введите пароль (сообщение с ним бот сразу удалит).", CANCEL);
}

async function eraseMessage(ctx, message) {
	await ctx.tg.call("deleteMessage", { chat_id: ctx.chatId, message_id: message.message_id }).catch(() => {});
}

/** Screen behind "🔐 Пароль": set or change it. */
export async function showPasswordMenu(ctx) {
	if (await hasPassword(ctx.env)) {
		await setState(ctx.env, ctx.from.id, { a: "pw_old" });
		return show(ctx, "🔐 Смена пароля. Введите текущий пароль.", CANCEL);
	}
	await setState(ctx.env, ctx.from.id, { a: "pw_new" });
	return show(ctx, "🔐 Придумайте пароль (не короче 4 символов). Сообщение с ним бот удалит.", CANCEL);
}

/**
 * Input handler for the password prompts. `run(ctx, data)` executes the guarded admin action once the
 * password is right; `before(ctx, data)` is called first (backup). Returns true when it consumed the message.
 */
export async function securityInput(ctx, state, message, text, run, before) {
	if (state.a !== "pw" && state.a !== "pw_old" && state.a !== "pw_new") {
		return false;
	}
	await eraseMessage(ctx, message);
	if (state.a === "pw_new") {
		if (text.length < 4 || text.length > 64) {
			await say(ctx, "Пароль: от 4 до 64 символов.", CANCEL);
			return true;
		}
		await setPassword(ctx.env, text);
		await clearState(ctx.env, ctx.from.id);
		await say(ctx, "✅ Пароль сохранён.", kb([[btn("← Админка", "a:home")]]));
		return true;
	}
	const wait = await lockedFor(ctx.env, ctx.now);
	if (wait > 0) {
		await say(ctx, `🔒 Слишком много неверных попыток. Подождите ${Math.ceil(wait / 60000)} мин.`, CANCEL);
		return true;
	}
	if (!(await verifyPassword(ctx.env, text, ctx.now))) {
		const left = await lockedFor(ctx.env, ctx.now);
		await say(ctx, left > 0 ? "🔒 Неверный пароль. Ввод заблокирован на 10 минут." : "❌ Неверный пароль. Попробуйте ещё раз или нажмите «Отмена».", CANCEL);
		return true;
	}
	if (state.a === "pw_old") {
		await setState(ctx.env, ctx.from.id, { a: "pw_new" });
		await say(ctx, "Пароль верный. Введите новый (не короче 4 символов).", CANCEL);
		return true;
	}
	await clearState(ctx.env, ctx.from.id);
	await before(ctx, state.data);
	await run({ ...ctx, callback: null, pwOk: true }, state.data);
	return true;
}
