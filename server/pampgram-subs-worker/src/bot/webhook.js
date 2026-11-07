/** Telegram webhook: secret check, then one update through the router. */

import { createTelegram } from "./telegram.js";
import { handleUpdate } from "./main.js";
import { expireChecks } from "./admin.js";

function constantTimeEqual(a, b) {
	if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) {
		return false;
	}
	let diff = 0;
	for (let i = 0; i < a.length; i++) {
		diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
	}
	return diff === 0;
}

export async function handleWebhook(request, env, tg = createTelegram(env)) {
	if (!env.BOT_TOKEN || !env.WEBHOOK_SECRET) {
		return new Response("bot is not configured", { status: 503 });
	}
	// Telegram echoes the secret given to setWebhook in this header on every delivery.
	if (!constantTimeEqual(request.headers.get("x-telegram-bot-api-secret-token") ?? "", env.WEBHOOK_SECRET)) {
		return new Response("forbidden", { status: 403 });
	}
	let update;
	try {
		update = await request.json();
	} catch {
		return new Response("bad request", { status: 400 });
	}
	try {
		await handleUpdate(env, tg, update);
	} catch (error) {
		// Always answer 200: Telegram would otherwise redeliver the same update in a loop.
		console.error("bot update failed", error?.stack ?? error);
	}
	return new Response("ok");
}

export async function runScheduled(env, tg = createTelegram(env)) {
	if (!env.BOT_TOKEN) {
		return;
	}
	await expireChecks(env, tg, Date.now());
}
