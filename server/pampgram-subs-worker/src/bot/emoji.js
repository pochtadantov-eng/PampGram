/**
 * Animated (custom) emoji for the bot's messages and buttons.
 *
 * Everything in the bot is written with ordinary emoji. When the admin has assigned an animated emoji to
 * one of them (admin panel -> Эмодзи), every outgoing call is rewritten on the fly:
 *   - in HTML text the ordinary emoji becomes <tg-emoji emoji-id="...">…</tg-emoji>;
 *   - a leading emoji on an inline button becomes that button's icon_custom_emoji_id.
 * If Telegram refuses (the bot's owner has no Premium and the bot has no Fragment username), the call is
 * repeated unchanged, so the bot never breaks because of a decoration; the refusal is remembered and shown
 * in the admin panel.
 */

import { getEmoji, setEmojiError } from "./store.js";

/** The ordinary emoji the bot uses, in the order shown in the admin panel. */
export const EMOJI_SLOTS = [
	"⭐", "🛒", "🔑", "📥", "🔒", "💬", "🛠", "📊", "👥", "🔎", "💰", "📦", "💳", "🧾", "⚙", "🔄",
	"✅", "❌", "⏸", "▶", "🗑", "✏", "📝", "🕒", "🔍", "💎", "⛔", "🟢", "🟡", "⚪", "🚫", "📎",
	"✉", "👤", "➕", "✖", "👋", "⚠", "🖼", "✨",
];

const VS16 = "\uFE0F";
const escapeRe = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function buildMatchers(map) {
	const keys = Object.keys(map).filter((key) => map[key]);
	if (keys.length === 0) {
		return null;
	}
	keys.sort((a, b) => b.length - a.length);
	const alternation = keys.map(escapeRe).join("|");
	return {
		inText: new RegExp(`(${alternation})${VS16}?`, "gu"),
		leading: new RegExp(`^(${alternation})${VS16}?\\s*`, "u"),
	};
}

function wrapText(html, map, matchers) {
	return String(html)
		.split(/(<[^>]*>)/)
		.map((part) => (part.startsWith("<") ? part : part.replace(matchers.inText, (match, key) => `<tg-emoji emoji-id="${map[key]}">${match}</tg-emoji>`)))
		.join("");
}

function wrapMarkup(markup, map, matchers) {
	const rows = markup?.inline_keyboard;
	if (!Array.isArray(rows)) {
		return markup;
	}
	return {
		...markup,
		inline_keyboard: rows.map((row) =>
			row.map((button) => {
				if (typeof button.text !== "string") {
					return button;
				}
				// a per-button animated emoji chosen by the owner ("_icon") wins over the global mapping
				if (button._icon) {
					const { _icon, ...rest } = button;
					const head = /^(\p{Extended_Pictographic}\uFE0F?(?:\u200D\p{Extended_Pictographic}\uFE0F?)*)\s*/u.exec(button.text);
					return head && head[0].length < button.text.length ? { ...rest, text: button.text.slice(head[0].length), icon_custom_emoji_id: _icon } : rest;
				}
				const found = matchers ? matchers.leading.exec(button.text) : null;
				if (!found || found[0].length >= button.text.length) {
					return button;
				}
				return { ...button, text: button.text.slice(found[0].length), icon_custom_emoji_id: map[found[1]] };
			})
		),
	};
}

/** Removes the private "_icon" marker so a plain retry never sends it to Telegram. */
export function stripPrivate(params) {
	const rows = params.reply_markup?.inline_keyboard;
	if (!Array.isArray(rows) || !rows.some((row) => row.some((button) => button._icon))) {
		return params;
	}
	return { ...params, reply_markup: { ...params.reply_markup, inline_keyboard: rows.map((row) => row.map(({ _icon, ...button }) => button)) } };
}

const TEXT_FIELD = {
	sendMessage: "text",
	editMessageText: "text",
	sendPhoto: "caption",
	sendAnimation: "caption",
	sendVideo: "caption",
	sendDocument: "caption",
	editMessageCaption: "caption",
};

/** Returns params with animated emoji applied, or the very same object when nothing changes. */
export function applyEmoji(method, params, map) {
	const matchers = buildMatchers(map);
	let next = params;
	const field = TEXT_FIELD[method];
	if (matchers && field && typeof params[field] === "string" && params.parse_mode === "HTML") {
		const text = wrapText(params[field], map, matchers);
		if (text !== params[field]) {
			next = { ...next, [field]: text };
		}
	}
	if (params.reply_markup) {
		const markup = wrapMarkup(params.reply_markup, map, matchers);
		if (JSON.stringify(markup) !== JSON.stringify(params.reply_markup)) {
			next = { ...next, reply_markup: markup };
		}
	}
	return next;
}

const emojiRelated = (error) => /emoji|entit|custom|premium|BUTTON_|DOCUMENT_INVALID|parse/i.test(String(error?.description ?? error?.message ?? ""));

/** Wraps a Telegram client so that configured animated emoji are used, with a safe fallback. */
export function withEmoji(env, tg) {
	let loaded = null;
	const map = async () => (loaded ??= await getEmoji(env).catch(() => ({})));
	return {
		async call(method, params = {}) {
			const emoji = await map();
			const next = applyEmoji(method, params, emoji);
			if (next === params) {
				return tg.call(method, params);
			}
			const plain = stripPrivate(params);
			try {
				return await tg.call(method, next);
			} catch (error) {
				if (!emojiRelated(error)) {
					throw error;
				}
				await setEmojiError(env, { at: Date.now(), message: String(error.description ?? error.message).slice(0, 200) }).catch(() => {});
				return tg.call(method, plain);
			}
		},
	};
}

/** Custom emoji ids in a message, in order of appearance. */
export function customEmojiIds(message) {
	const entities = [...(message.entities ?? []), ...(message.caption_entities ?? [])];
	return entities.filter((entity) => entity.type === "custom_emoji" && entity.custom_emoji_id).sort((a, b) => a.offset - b.offset).map((entity) => entity.custom_emoji_id);
}
