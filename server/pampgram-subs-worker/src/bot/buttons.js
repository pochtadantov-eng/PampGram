/**
 * Owner-defined buttons. Two things live in KV key "buttons":
 *   overrides  - a changed name / emoji / visibility for a built-in button (found by its callback data);
 *   custom     - extra buttons the owner added to a section: a link, or a page of text.
 * Sections: "menu" (main menu) and "shop" (tariff list).
 */

import { show, toast } from "./context.js";
import { btn, urlBtn, kb, esc } from "./ui.js";
import { getButtons } from "./store.js";

export const SECTIONS = { menu: "Главное меню", shop: "Тарифы" };

/** Built-in buttons the owner may rename; the label is "emoji + text". */
export const BUILTIN = {
	menu: {
		shop: "🛒 Купить доступ",
		my: "🔑 Мои покупки",
		dl: "📥 Скачать файлы",
		privacy: "🔒 Приватность",
		support: "💬 Поддержка",
	},
	shop: {},
};

const EMOJI_HEAD = /^(\p{Extended_Pictographic}\uFE0F?(?:\u200D\p{Extended_Pictographic}\uFE0F?)*)\s*/u;

/** "🛒 Купить" -> { emoji: "🛒", rest: "Купить" }. */
export function splitLabel(label) {
	const found = EMOJI_HEAD.exec(String(label ?? ""));
	return found ? { emoji: found[1], rest: String(label).slice(found[0].length) } : { emoji: "", rest: String(label ?? "") };
}

/** Final label of a button from its defaults and the owner's override. */
export function labelOf(defaultLabel, override) {
	const base = splitLabel(defaultLabel);
	const emoji = override?.emoji !== undefined ? override.emoji : base.emoji;
	const text = override?.text !== undefined ? override.text : base.rest;
	return `${emoji} ${text}`.trim();
}

export function normalizeUrl(value) {
	const v = String(value ?? "").trim();
	if (/^https?:\/\//i.test(v) || /^tg:\/\//i.test(v)) {
		return v;
	}
	if (/^@[A-Za-z0-9_]{3,}$/.test(v)) {
		return `https://t.me/${v.slice(1)}`;
	}
	if (/^t\.me\//i.test(v)) {
		return `https://${v}`;
	}
	return null;
}

function strip(button) {
	const { _key, ...rest } = button;
	return rest;
}

/**
 * Applies the owner's overrides to `rows` of a customer screen and inserts the custom buttons of `section`
 * before the last `tail` rows (back / admin button).
 */
export async function customizeRows(env, section, rows, tail = 0) {
	const cfg = await getButtons(env);
	const overrides = cfg.overrides?.[section] ?? {};
	const out = [];
	for (const row of rows) {
		const next = [];
		for (const button of row) {
			const key = button._key ?? button.callback_data;
			const override = overrides[key];
			if (!override) {
				next.push(strip(button));
			} else if (!override.hidden) {
				const styled = { ...strip(button), text: labelOf(button.text, override) };
				if (override.icon && splitLabel(styled.text).emoji) {
					styled._icon = override.icon;
				}
				next.push(styled);
			}
		}
		if (next.length) {
			out.push(next);
		}
	}
	const extra = cfg.custom
		.filter((item) => item.section === section && !item.hidden)
		.map((item) => {
			const label = labelOf(`${item.emoji ?? ""} ${item.text}`, undefined);
			const button = item.type === "link" ? urlBtn(label, item.url) : btn(label, `cb:${item.id}`);
			return item.icon && item.emoji ? [{ ...button, _icon: item.icon }] : [button];
		});
	const at = Math.max(0, out.length - tail);
	return [...out.slice(0, at), ...extra, ...out.slice(at)];
}

/** A custom "page" button was pressed. */
export async function showCustomPage(ctx, id) {
	const cfg = await getButtons(ctx.env);
	const item = cfg.custom.find((entry) => entry.id === id && entry.type === "page" && !entry.hidden);
	if (!item) {
		return toast(ctx, "Раздел недоступен", true);
	}
	await toast(ctx);
	return show(ctx, `<b>${esc(labelOf(`${item.emoji ?? ""} ${item.text}`))}</b>\n\n${esc(item.page ?? "")}`, kb([[btn("← Назад", item.section === "shop" ? "shop" : "menu")]]));
}
