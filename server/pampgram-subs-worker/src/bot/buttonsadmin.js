/** Admin screens: add / rename / re-emoji / hide / reorder / delete buttons in the customer sections. */

import { show, say, toast } from "./context.js";
import { btn, kb, esc } from "./ui.js";
import { getButtons, saveButtons, newId, setState, clearState, getState } from "./store.js";
import { SECTIONS, BUILTIN, MAX_PER_ROW, splitLabel, labelOf, normalizeUrl, effectiveLayout, rowsFromLayout } from "./buttons.js";
import { customEmojiIds } from "./emoji.js";

const CANCEL = kb([[btn("✖️ Отмена", "a:bt")]]);
const TYPE_NAME = { link: "ссылка", page: "страница с текстом" };

const itemOf = (cfg, section, key) => cfg.custom.find((entry) => entry.id === key && entry.section === section);
const builtinLabel = (section, key) => BUILTIN[section]?.[key];

// ---------- screens ----------

export async function showSections(ctx) {
	const rows = Object.entries(SECTIONS).map(([key, title]) => [btn(`🔘 ${title}`, `a:bt:${key}`)]);
	rows.push([btn("← Админка", "a:home")]);
	return show(ctx, "🔘 <b>Кнопки</b>\nВыберите раздел: можно добавить свои кнопки, переименовать, сменить эмодзи, скрыть или переставить.", kb(rows));
}

function labelFor(cfg, section, key) {
	const item = itemOf(cfg, section, key);
	if (item) {
		return { label: labelOf(`${item.emoji ?? ""} ${item.text}`), hidden: item.hidden };
	}
	const override = cfg.overrides?.[section]?.[key];
	return { label: labelOf(builtinLabel(section, key), override), hidden: override?.hidden };
}

export async function showSection(ctx, section) {
	if (!SECTIONS[section]) {
		return showSections(ctx);
	}
	const cfg = await getButtons(ctx.env);
	const layout = effectiveLayout(cfg, section);
	const rows = layout.map(({ k }) => {
		const { label, hidden } = labelFor(cfg, section, k);
		return [btn(`${hidden ? "🙈" : itemOf(cfg, section, k) ? "🔹" : "▪️"} ${label}`.slice(0, 60), `a:bte:${section}:${k}`)];
	});
	rows.push([btn("➕ Новая кнопка", `a:bta:${section}`)]);
	rows.push([btn("← К разделам", "a:bt")]);
	const preview = rowsFromLayout(layout, (k) => {
		const { label, hidden } = labelFor(cfg, section, k);
		return hidden ? null : label;
	}).map((row) => `│ ${row.map(esc).join("  ┃  ")}`);
	const note = section === "shop" ? "\nКнопки тарифов создаются в «Тарифы» и стоят выше; здесь расставляются ваши кнопки под ними." : "";
	return show(
		ctx,
		`🔘 <b>${SECTIONS[section]}</b>${note}\n\n<b>Как видят покупатели</b> (┃ — кнопки в одной строке):\n${preview.join("\n") || "—"}\n\n▪️ встроенная · 🔹 ваша · 🙈 скрыта\nНажмите кнопку, чтобы переименовать, сменить эмодзи, переставить или поставить в одну строку с соседней.`,
		kb(rows)
	);
}

export async function showButton(ctx, section, key) {
	const cfg = await getButtons(ctx.env);
	const item = itemOf(cfg, section, key);
	const builtin = builtinLabel(section, key);
	if (!item && !builtin) {
		return showSection(ctx, section);
	}
	const override = cfg.overrides?.[section]?.[key];
	const hidden = item ? item.hidden : override?.hidden;
	const label = item ? labelOf(`${item.emoji ?? ""} ${item.text}`) : labelOf(builtin, override);
	const lines = [
		`🔘 <b>${esc(label)}</b>`,
		item ? `Тип: ${TYPE_NAME[item.type]}` : "Встроенная кнопка",
		item?.type === "link" ? `Ссылка: ${esc(item.url)}` : "",
		item?.type === "page" ? `Текст страницы: ${esc((item.page ?? "").slice(0, 200))}` : "",
		(item ? item.icon : override?.icon) ? "Эмодзи: анимированный" : "",
		`Показывается: ${hidden ? "нет" : "да"}`,
	].filter(Boolean);
	const layout = effectiveLayout(cfg, section);
	const place = layout.findIndex((entry) => entry.k === key);
	const joined = place > 0 && layout[place].j;
	lines.push(`Расположение: ${place + 1} из ${layout.length}, ${joined ? "в одной строке с предыдущей" : "отдельной строкой"}`);
	const rows = [
		[btn("✏️ Название", `a:btn:${section}:${key}`), btn("🙂 Эмодзи", `a:btm:${section}:${key}`)],
		[btn(hidden ? "👁 Показать" : "🙈 Скрыть", `a:btv:${section}:${key}`)],
		[btn("⬆️ Выше", `a:btu:${section}:${key}`), btn("⬇️ Ниже", `a:btd:${section}:${key}`)],
		[btn(joined ? "⬍ Отдельной строкой" : "↔ В строку с предыдущей", `a:btj:${section}:${key}`)],
	];
	if (item) {
		rows.push([btn(item.type === "link" ? "🔗 Ссылка" : "📄 Текст", `a:btc:${section}:${key}`), btn("🗑 Удалить", `a:btx:${section}:${key}`)]);
	} else if (override) {
		rows.push([btn("↩️ Вернуть стандартную", `a:btr:${section}:${key}`)]);
	}
	rows.push([btn("← К разделу", `a:bt:${section}`)]);
	return show(ctx, lines.join("\n"), kb(rows));
}

// ---------- changing things ----------

async function update(ctx, section, key, mutate) {
	const cfg = await getButtons(ctx.env);
	const item = itemOf(cfg, section, key);
	if (item) {
		mutate(item);
	} else if (builtinLabel(section, key)) {
		cfg.overrides[section] ??= {};
		cfg.overrides[section][key] ??= {};
		mutate(cfg.overrides[section][key]);
	} else {
		return false;
	}
	await saveButtons(ctx.env, cfg);
	return true;
}

async function saveLayoutList(ctx, cfg, section, list) {
	cfg.layout = { ...cfg.layout, [section]: list };
	await saveButtons(ctx.env, cfg);
}

/** Moves a button one place up / down the section's list. */
async function move(ctx, section, key, delta) {
	const cfg = await getButtons(ctx.env);
	const list = effectiveLayout(cfg, section);
	const index = list.findIndex((entry) => entry.k === key);
	const target = index + delta;
	if (index < 0 || target < 0 || target >= list.length) {
		return false;
	}
	[list[index], list[target]] = [list[target], list[index]];
	await saveLayoutList(ctx, cfg, section, list);
	return true;
}

/** Puts a button in the same row as the previous one, or back on its own row. */
async function toggleJoin(ctx, section, key) {
	const cfg = await getButtons(ctx.env);
	const list = effectiveLayout(cfg, section);
	const index = list.findIndex((entry) => entry.k === key);
	if (index <= 0) {
		return "Первую кнопку нельзя поставить в строку с предыдущей";
	}
	if (!list[index].j) {
		// count how many already stand in the row of the previous button
		let size = 1;
		for (let i = index - 1; i > 0 && list[i].j; i--) {
			size++;
		}
		if (size >= MAX_PER_ROW) {
			return `В одной строке не больше ${MAX_PER_ROW} кнопок`;
		}
	}
	list[index].j = !list[index].j;
	await saveLayoutList(ctx, cfg, section, list);
	return null;
}

/** Returns true when the callback belongs to this module. `parts` is the callback data without "a:". */
export async function buttonsCallback(ctx, parts) {
	const [action, section, key] = parts;
	switch (action) {
		case "bt":
			await toast(ctx);
			await (section ? showSection(ctx, section) : showSections(ctx));
			return true;
		case "bte":
			await toast(ctx);
			await showButton(ctx, section, key);
			return true;
		case "bta":
			if (!SECTIONS[section]) {
				return true;
			}
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "btn_add", section, step: "name" });
			await show(ctx, "Название новой кнопки. Можно начать с эмодзи, например «🎁 Отзывы».", CANCEL);
			return true;
		case "btt": {
			// a:btt:<section>:<link|page> -> type chosen while adding
			const type = key;
			if (!["link", "page"].includes(type)) {
				return true;
			}
			await toast(ctx);
			const state = await getState(ctx.env, ctx.from.id);
			if (!state || state.a !== "btn_add" || state.step !== "type") {
				return true;
			}
			await setState(ctx.env, ctx.from.id, { ...state, step: "content", type });
			await show(ctx, type === "link" ? "Пришлите ссылку: https://…, @ник или t.me/…" : "Пришлите текст страницы, который откроется по нажатию.", CANCEL);
			return true;
		}
		case "btn":
		case "btm":
		case "btc": {
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: { btn: "btn_name", btm: "btn_emoji", btc: "btn_content" }[action], section, key });
			const prompt = {
				btn: "Новое название кнопки (без эмодзи, эмодзи меняется отдельно).",
				btm: "Пришлите эмодзи: обычный или анимированный (Premium). «-» уберёт эмодзи.",
				btc: "Пришлите новую ссылку или текст страницы.",
			}[action];
			await show(ctx, prompt, kb([[btn("✖️ Отмена", `a:bte:${section}:${key}`)]]));
			return true;
		}
		case "btv":
			await update(ctx, section, key, (entry) => {
				entry.hidden = !entry.hidden;
			});
			await toast(ctx);
			await showButton(ctx, section, key);
			return true;
		case "btu":
		case "btd":
			await move(ctx, section, key, action === "btu" ? -1 : 1);
			await toast(ctx);
			await showButton(ctx, section, key);
			return true;
		case "btj": {
			const problem = await toggleJoin(ctx, section, key);
			await toast(ctx, problem ?? "", Boolean(problem));
			await showButton(ctx, section, key);
			return true;
		}
		case "btx": {
			const cfg = await getButtons(ctx.env);
			cfg.custom = cfg.custom.filter((entry) => !(entry.id === key && entry.section === section));
			await saveButtons(ctx.env, cfg);
			await toast(ctx, "Удалено");
			await showSection(ctx, section);
			return true;
		}
		case "btr": {
			const cfg = await getButtons(ctx.env);
			if (cfg.overrides?.[section]) {
				delete cfg.overrides[section][key];
			}
			await saveButtons(ctx.env, cfg);
			await toast(ctx, "Возвращено");
			await showButton(ctx, section, key);
			return true;
		}
		default:
			return false;
	}
}

/** Reads the emoji an admin sent: { emoji, icon } for an animated one, { emoji } for an ordinary one. */
export function readEmoji(message, text) {
	const ids = customEmojiIds(message);
	if (ids.length > 0) {
		const entity = [...(message.entities ?? [])].find((item) => item.type === "custom_emoji");
		const fallback = String(message.text ?? "").slice(entity.offset, entity.offset + entity.length);
		return { emoji: fallback || "✨", icon: ids[0] };
	}
	const head = splitLabel(text);
	return head.emoji ? { emoji: head.emoji, icon: undefined } : null;
}

/** Returns true when the admin's message answered one of this module's prompts. */
export async function buttonsInput(ctx, state, message, text) {
	const plain = { ...ctx, callback: null };
	if (state.a === "btn_add") {
		if (state.step === "name") {
			if (!text || text.length > 50) {
				await say(ctx, "Название: от 1 до 50 символов.", CANCEL);
				return true;
			}
			const head = splitLabel(text);
			await setState(ctx.env, ctx.from.id, { ...state, step: "type", text: head.rest || text, emoji: head.rest ? head.emoji : "" });
			await say(ctx, "Что должна делать кнопка?", kb([[btn("🔗 Открывать ссылку", `a:btt:${state.section}:link`)], [btn("📄 Показывать текст", `a:btt:${state.section}:page`)], [btn("✖️ Отмена", "a:bt")]]));
			return true;
		}
		if (state.step === "content") {
			const cfg = await getButtons(ctx.env);
			const item = { id: newId(6), section: state.section, type: state.type, text: state.text, emoji: state.emoji };
			if (state.type === "link") {
				const url = normalizeUrl(text);
				if (!url) {
					await say(ctx, "Это не ссылка. Пример: https://example.com, @ник или t.me/ник.", CANCEL);
					return true;
				}
				item.url = url;
			} else {
				if (!text || text.length > 3000) {
					await say(ctx, "Текст: от 1 до 3000 символов.", CANCEL);
					return true;
				}
				item.page = text;
			}
			cfg.custom.push(item);
			await saveButtons(ctx.env, cfg);
			await clearState(ctx.env, ctx.from.id);
			await showButton(plain, state.section, item.id);
			return true;
		}
		return false;
	}
	if (state.a === "btn_name") {
		if (!text || text.length > 50) {
			await say(ctx, "Название: от 1 до 50 символов.", CANCEL);
			return true;
		}
		const head = splitLabel(text);
		await update(ctx, state.section, state.key, (entry) => {
			entry.text = head.rest || text;
			if (head.rest && head.emoji) {
				entry.emoji = head.emoji;
				delete entry.icon;
			}
		});
		await clearState(ctx.env, ctx.from.id);
		await showButton(plain, state.section, state.key);
		return true;
	}
	if (state.a === "btn_emoji") {
		if (text === "-") {
			await update(ctx, state.section, state.key, (entry) => {
				entry.emoji = "";
				delete entry.icon;
			});
		} else {
			const found = readEmoji(message, text);
			if (!found) {
				await say(ctx, "Не вижу эмодзи. Пришлите одно эмодзи (или «-», чтобы убрать).", kb([[btn("✖️ Отмена", `a:bte:${state.section}:${state.key}`)]]));
				return true;
			}
			await update(ctx, state.section, state.key, (entry) => {
				entry.emoji = found.emoji;
				if (found.icon) {
					entry.icon = found.icon;
				} else {
					delete entry.icon;
				}
			});
		}
		await clearState(ctx.env, ctx.from.id);
		await showButton(plain, state.section, state.key);
		return true;
	}
	if (state.a === "btn_content") {
		const cfg = await getButtons(ctx.env);
		const item = itemOf(cfg, state.section, state.key);
		if (!item) {
			await clearState(ctx.env, ctx.from.id);
			await showSection(plain, state.section);
			return true;
		}
		if (item.type === "link") {
			const url = normalizeUrl(text);
			if (!url) {
				await say(ctx, "Это не ссылка. Пример: https://example.com, @ник или t.me/ник.", CANCEL);
				return true;
			}
			item.url = url;
		} else {
			if (!text || text.length > 3000) {
				await say(ctx, "Текст: от 1 до 3000 символов.", CANCEL);
				return true;
			}
			item.page = text;
		}
		await saveButtons(ctx.env, cfg);
		await clearState(ctx.env, ctx.from.id);
		await showButton(plain, state.section, state.key);
		return true;
	}
	return false;
}
