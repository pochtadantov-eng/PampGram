/** Entry point for one Telegram update. */

import { recordBotSeen, updateUser } from "../users.js";
import { say } from "./context.js";
import { trySend } from "./telegram.js";
import { isAdmin } from "./store.js";
import { withEmoji } from "./emoji.js";
import { showCustomPage } from "./buttons.js";
import { showProduct } from "./products.js";
import { adminHome, adminCallback, adminInput, answerCheck } from "./admin.js";
import {
	showMenu, showTariffs, showTariff, startPurchase, handlePreCheckout, handleSuccessfulPayment,
	bindKey, showPurchases, resendFiles, showPrivacy,
} from "./shop.js";
import { startManualPurchase, claimPaid, cancelOrder, forwardProof } from "./pay.js";

function buildContext(env, tg, now, update) {
	const callback = update.callback_query;
	const message = update.message ?? callback?.message;
	const from = update.message?.from ?? callback?.from ?? update.pre_checkout_query?.from ?? update.my_chat_member?.from;
	return {
		env,
		tg,
		now,
		from,
		chatId: message?.chat?.id ?? from?.id,
		callback: callback ? { id: callback.id, message_id: callback.message?.message_id } : null,
	};
}

async function handleCallback(ctx, data) {
	if (data.startsWith("a:")) {
		if (!isAdmin(ctx.env, ctx.from.id)) {
			return;
		}
		return adminCallback(ctx, data.slice(2));
	}
	const [action, arg] = [data.split(":")[0], data.slice(data.indexOf(":") + 1)];
	switch (action) {
		case "menu":
			return showMenu(ctx);
		case "shop":
			return showTariffs(ctx);
		case "t":
			return showTariff(ctx, arg);
		case "buy":
			return startPurchase(ctx, arg);
		case "pay": {
			const [code, methodId] = arg.split(":");
			return startManualPurchase(ctx, code, methodId);
		}
		case "pd":
			return claimPaid(ctx, arg);
		case "px":
			return cancelOrder(ctx, arg);
		case "cb":
			return showCustomPage(ctx, arg);
		case "sp":
			return showProduct(ctx, arg);
		case "bind":
			return bindKey(ctx, arg);
		case "my":
			return showPurchases(ctx);
		case "dl":
			return resendFiles(ctx);
		case "privacy":
			return showPrivacy(ctx);
		case "ck":
			return answerCheck(ctx);
		default:
			return;
	}
}

async function handleMessage(ctx, message) {
	if (message.successful_payment) {
		return handleSuccessfulPayment(ctx, message.successful_payment);
	}
	if (message.chat?.type !== "private") {
		return; // the bot only talks in direct messages
	}
	const text = (message.text ?? "").trim();
	if (text.startsWith("/")) {
		const command = text.split(/\s|@/)[0].toLowerCase();
		if (command === "/admin" && isAdmin(ctx.env, ctx.from.id)) {
			return adminHome(ctx);
		}
		if (command === "/privacy") {
			return showPrivacy(ctx);
		}
		// /start, /menu, /help and anything unknown all land on the menu; it also drops an
		// admin's half-finished prompt.
		if (isAdmin(ctx.env, ctx.from.id)) {
			await adminHome({ ...ctx, callback: null });
		}
		return showMenu(ctx);
	}
	if (isAdmin(ctx.env, ctx.from.id) && (await adminInput(ctx, message))) {
		return;
	}
	if (await forwardProof(ctx, message)) {
		return;
	}
	return showMenu(ctx);
}

/** The Telegram "my_chat_member" update: the user blocked or unblocked the bot. */
async function handleMembership(ctx, update) {
	const status = update.my_chat_member?.new_chat_member?.status;
	if (update.my_chat_member?.chat?.type !== "private" || !status) {
		return;
	}
	await updateUser(ctx.env, String(ctx.from.id), (user) => {
		user.bot = { ...(user.bot ?? { startedAt: ctx.now }), blocked: status === "kicked", lastAt: ctx.now };
	}, ctx.now);
}

export async function handleUpdate(env, rawTg, update, now = Date.now()) {
	const tg = withEmoji(env, rawTg);
	const ctx = buildContext(env, tg, now, update);
	if (!ctx.from || ctx.from.is_bot) {
		return;
	}
	if (update.my_chat_member) {
		return handleMembership(ctx, update);
	}
	// Staff pressing buttons are not customers: keep them out of the user list and the stats.
	if (!isAdmin(env, ctx.from.id)) {
		await recordBotSeen(env, ctx.from, now).catch(() => {});
	}
	if (update.pre_checkout_query) {
		return handlePreCheckout(ctx, update.pre_checkout_query);
	}
	if (update.callback_query) {
		return handleCallback(ctx, update.callback_query.data ?? "");
	}
	if (update.message) {
		return handleMessage(ctx, update.message);
	}
}

export { trySend, say };
