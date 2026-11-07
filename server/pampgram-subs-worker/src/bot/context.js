/** Reply helpers bound to one incoming update. */

import { trySend } from "./telegram.js";

/** New message to the chat of this update. */
export async function say(ctx, text, extra = {}) {
	return trySend(ctx.tg, ctx.chatId, text, extra);
}

/**
 * Shows `text`: edits the message a button was pressed on when there is one, otherwise sends a
 * new message. A failed edit (message too old, or identical content) falls back to a new send.
 */
export async function show(ctx, text, extra = {}) {
	if (ctx.callback?.message_id) {
		try {
			await ctx.tg.call("editMessageText", {
				chat_id: ctx.chatId,
				message_id: ctx.callback.message_id,
				text,
				parse_mode: "HTML",
				disable_web_page_preview: true,
				...extra,
			});
			return true;
		} catch (error) {
			const reason = String(error.description ?? error.message);
			if (reason.includes("not modified")) {
				return true;
			}
			if (reason.includes("no text in the message")) {
				// the message is a banner (photo/animation): replace it instead of editing
				try {
					await ctx.tg.call("deleteMessage", { chat_id: ctx.chatId, message_id: ctx.callback.message_id });
				} catch {
					// too old to delete: the new message is still sent below
				}
			}
		}
	}
	return say(ctx, text, extra);
}

/** Small popup for a button press (also stops the button's loading spinner). */
export async function toast(ctx, text = "", alert = false) {
	if (!ctx.callback?.id) {
		return;
	}
	try {
		await ctx.tg.call("answerCallbackQuery", { callback_query_id: ctx.callback.id, text: text.slice(0, 190), show_alert: alert });
	} catch {
		// a stale callback id is not worth failing the update for
	}
}
