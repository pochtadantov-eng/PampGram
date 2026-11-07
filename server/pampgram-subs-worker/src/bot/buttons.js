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

/** Longest row the owner can build (Telegram itself allows 8, but long names stop fitting). */
export const MAX_PER_ROW = 3;

/** Which built-in buttons stand next to the previous one by default. */
const DEFAULT_JOIN = { menu: { dl: true } };

/**
 * The order and row grouping of a section as a list of { k: key, j: stands in the same row as the previous one }.
 * Built from what the owner saved, plus anything new (new buttons are appended as their own row).
 */
export function effectiveLayout(cfg, section) {
	const keys = [...Object.keys(BUILTIN[section] ?? {}), ...cfg.custom.filter((entry) => entry.section === section).map((entry) => entry.id)];
	const saved = (cfg.layout?.[section] ?? []).filter((entry, index, all) => keys.includes(entry.k) && all.findIndex((other) => other.k === entry.k) === index);
	const seen = new Set(saved.map((entry) => entry.k));
	const out = saved.map((entry) => ({ k: entry.k, j: Boolean(entry.j) }));
	for (const key of keys) {
		if (!seen.has(key)) {
			out.push({ k: key, j: Boolean(DEFAULT_JOIN[section]?.[key]) });
		}
	}
	return out;
}

/** Cuts a flat list into rows following the "j" flags, never longer than MAX_PER_ROW. */
export function rowsFromLayout(entries, itemOf) {
	const rows = [];
	for (const entry of entries) {
		const item = itemOf(entry.k);
		if (!item) {
			continue;
		}
		const last = rows[rows.length - 1];
		if (entry.j && last && last.length < MAX_PER_ROW) {
			last.push(item);
		} else {
			rows.push([item]);
		}
	}
	return rows;
}

/**
 * Applies the owner's overrides and layout to the rows of a customer screen. `tail` rows at the end (back /
 * admin button) stay last. In "menu" the built-in and custom buttons are one freely arranged list; in "shop"
 * the tariff rows stay on top and only the custom buttons are arranged below them.
 */
export async function customizeRows(env, section, rows, tail = 0) {
	const cfg = await getButtons(env);
	const overrides = cfg.overrides?.[section] ?? {};
	const tailRows = tail ? rows.slice(-tail) : [];
	const body = tail ? rows.slice(0, -tail) : rows;
	const fixed = section === "shop" ? body : [];
	const movable = section === "shop" ? [] : body;
	const items = new Map();
	const defaults = [];
	for (const row of movable) {
		for (const button of row) {
			const key = button._key ?? button.callback_data;
			const override = overrides[key];
			defaults.push(key);
			if (override?.hidden) {
				continue;
			}
			if (!override) {
				items.set(key, strip(button));
				continue;
			}
			const styled = { ...strip(button), text: labelOf(button.text, override) };
			if (override.icon && splitLabel(styled.text).emoji) {
				styled._icon = override.icon;
			}
			items.set(key, styled);
		}
	}
	for (const entry of cfg.custom.filter((item) => item.section === section && !item.hidden)) {
		const label = labelOf(`${entry.emoji ?? ""} ${entry.text}`, undefined);
		const button = entry.type === "link" ? urlBtn(label, entry.url) : btn(label, `cb:${entry.id}`);
		items.set(entry.id, entry.icon && entry.emoji ? { ...button, _icon: entry.icon } : button);
	}
	const order = effectiveLayout(cfg, section);
	// anything the layout does not know (unexpected buttons) goes last, one per row
	for (const key of items.keys()) {
		if (!order.some((entry) => entry.k === key)) {
			order.push({ k: key, j: false });
		}
	}
	const arranged = rowsFromLayout(order, (key) => items.get(key));
	return [...fixed.map((row) => row.map(strip)), ...arranged, ...tailRows.map((row) => row.map(strip))];
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
