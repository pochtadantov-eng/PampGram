/**
 * Every message the bot shows to customers that the owner may want to reword. Each has a standard text; the
 * owner's own wording is kept separately in KV key "texts" ({ key: text }) and is never overwritten by updates.
 *
 * An owner's text is plain text: it is escaped, "*так*" makes bold, {names} are replaced with the real values
 * (listed in the editor). The standard text may contain HTML.
 */

import { esc } from "./ui.js";
import { show, toast } from "./context.js";
import { btn, kb } from "./ui.js";
import { getConfig, setState, clearState } from "./store.js";

export const TEXTS = {
	shop_intro: { group: "Тарифы", title: "Экран тарифов", vars: [], text: "<b>Тарифы</b>\nВыберите тариф, затем способ оплаты. Ключ и файлы приходят после оплаты." },
	no_tariffs: { group: "Тарифы", title: "Нет тарифов", vars: [], text: "Сейчас нет доступных тарифов." },
	choose_method: { group: "Тарифы", title: "Над кнопками способов оплаты", vars: [], text: "Выберите способ оплаты:" },
	no_methods: { group: "Тарифы", title: "Способы оплаты не настроены", vars: [], text: "Способы оплаты пока не настроены. Напишите в поддержку." },
	banned: { group: "Тарифы", title: "Доступ ограничен (бан)", vars: ["reason"], text: "⛔ Доступ ограничен.\nПричина: {reason}" },
	no_products: { group: "Разделы с товарами", title: "В разделе нет товаров", vars: [], text: "Товаров пока нет." },
	no_methods_section: { group: "Разделы с товарами", title: "У раздела не настроена оплата", vars: [], text: "Способы оплаты для этого раздела не настроены. Напишите в поддержку." },
	pay_manual_tariff: { group: "Оплата картой и кошельком", title: "Под реквизитами (тариф)", vars: [], text: "Переведите точную сумму, затем нажмите «Я оплатил(а)». После проверки придут ключ и файлы." },
	pay_manual_item: { group: "Оплата картой и кошельком", title: "Под реквизитами (товар)", vars: [], text: "Переведите точную сумму, затем нажмите «Я оплатил(а)». После проверки вы получите товар." },
	claim_sent: { group: "Оплата картой и кошельком", title: "После «Я оплатил(а)»", vars: [], text: "✅ Заявка отправлена. Можете прислать сюда скриншот или чек перевода — это ускорит проверку. Ключ и файлы придут сюда сразу после подтверждения." },
	invoice_cancelled: { group: "Тарифы", title: "Оплата отменена (под счётом)", vars: [], text: "Оплата отменена. Вы можете выбрать тариф заново." },
	proof_ok: { group: "Оплата картой и кошельком", title: "Получен чек", vars: [], text: "📨 Получено, передали на проверку." },
	order_cancelled: { group: "Оплата картой и кошельком", title: "Заказ отменён", vars: [], text: "Заказ отменён." },
	pay_rejected: { group: "Оплата картой и кошельком", title: "Оплата не подтверждена", vars: ["title"], text: "❌ Оплата заказа «{title}» не подтверждена. Если вы платили — напишите в поддержку и приложите чек." },
	paid_title: { group: "После оплаты", title: "Заголовок «Оплата получена»", vars: [], text: "✅ <b>Оплата получена</b>" },
	key_note: { group: "После оплаты", title: "Пояснение под ключом", vars: [], text: "Ключ одноразовый: он привяжется к тому аккаунту Telegram, который введёт его первым." },
	item_hand: { group: "После оплаты", title: "Товар выдаётся вручную", vars: [], text: "Администратор выдаст вам товар и напишет сюда в ближайшее время." },
	bundle_empty: { group: "После оплаты", title: "После оплаты нет файлов в выдаче", vars: [], text: "Файлы для установки пока не добавлены — администратор пришлёт их вручную." },
	no_files: { group: "После оплаты", title: "Кнопка «Скачать файлы»: файлов нет", vars: [], text: "Файлы пока не добавлены. Напишите в поддержку." },
	my_title: { group: "Мои покупки", title: "Заголовок «Мои покупки»", vars: [], text: "<b>Мои покупки</b>" },
	my_empty: { group: "Мои покупки", title: "Покупок нет", vars: [], text: "Покупок пока нет." },
	privacy: { group: "Приватность", title: "Экран «Приватность»", vars: [], text: "<b>Какие данные собираются</b>\nПри запуске мод обращается к серверу лицензий и передаёт служебные данные: id вашего аккаунта Telegram, версию приложения, ник и имя профиля, время обращений. Они нужны для проверки подписки и блокировок. Сообщения и содержимое чатов не передаются.\n\nБот хранит ваш id, ник, имя и историю покупок." },
};

export async function readTexts(env) {
	try {
		const stored = JSON.parse((await env.SUBS.get("texts")) ?? "null");
		return stored && typeof stored === "object" && !Array.isArray(stored) ? stored : {};
	} catch {
		return {};
	}
}

export async function saveTexts(env, map) {
	await env.SUBS.put("texts", JSON.stringify(map));
}

function fill(template, vars) {
	return template.replace(/\{(\w+)\}/g, (match, name) => (name in vars ? esc(vars[name]) : match));
}

/** Owner's plain text -> safe HTML ("*bold*" supported). */
function ownerHtml(text) {
	return esc(text).replace(/\*([^*\n]+)\*/g, "<b>$1</b>");
}

/** The message to show: the owner's wording if set, else the standard one. `vars` fill {placeholders}. */
export async function getText(env, key, vars = {}) {
	const entry = TEXTS[key];
	const override = (await readTexts(env))[key];
	if (override) {
		return fill(ownerHtml(override), vars);
	}
	return fill(entry.text, vars);
}

// ---------- admin screens ----------

const GROUPS = [...new Set(Object.values(TEXTS).map((entry) => entry.group))];

export async function showTextList(ctx) {
	const overrides = await readTexts(ctx.env);
	const rows = [[btn("👋 Приветствие бота", "a:cf:welcome"), btn("📖 Инструкция", "a:cf:howto")]];
	for (const group of GROUPS) {
		rows.push([btn(`── ${group} ──`, "a:noop")]);
		for (const [key, entry] of Object.entries(TEXTS)) {
			if (entry.group === group) {
				rows.push([btn(`${overrides[key] ? "✏️" : "▪️"} ${entry.title}`.slice(0, 60), `a:tk:${key}`)]);
			}
		}
	}
	rows.push([btn("← Админка", "a:home")]);
	return show(ctx, "📝 <b>Тексты бота</b>\nВыберите сообщение, чтобы изменить его. ✏️ — вы уже меняли, ▪️ — стандартный текст.\nОписания и названия кнопок меняются в «Кнопки», тарифов — в «Тарифы», товаров — в их карточках.", kb(rows));
}

export async function showTextCard(ctx, key) {
	const entry = TEXTS[key];
	if (!entry) {
		return showTextList(ctx);
	}
	const overrides = await readTexts(ctx.env);
	const current = overrides[key];
	const lines = [
		`📝 <b>${esc(entry.title)}</b>`,
		current ? "Сейчас (ваш текст):" : "Сейчас (стандартный текст):",
		esc(current ?? entry.text.replace(/<\/?b>/g, "")),
		entry.vars.length ? `\nМожно вставить: ${entry.vars.map((name) => `{${name}}`).join(", ")}` : "",
	].filter(Boolean);
	const rows = [[btn("✏️ Изменить", `a:tke:${key}`)]];
	if (current) {
		rows.push([btn("↩️ Вернуть стандартный", `a:tkr:${key}`)]);
	}
	rows.push([btn("← К текстам", "a:tk")]);
	return show(ctx, lines.join("\n"), kb(rows));
}

/** Returns true when the callback belongs to this module. */
export async function textsCallback(ctx, parts) {
	const [action, key] = parts;
	switch (action) {
		case "tk":
			await toast(ctx);
			await (key ? showTextCard(ctx, key) : showTextList(ctx));
			return true;
		case "tke": {
			const entry = TEXTS[key];
			if (!entry) {
				return true;
			}
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "text_set", key });
			await show(ctx, `Пришлите новый текст для «${entry.title}».\n*так* — жирный шрифт${entry.vars.length ? `; сюда подставятся: ${entry.vars.map((name) => `{${name}}`).join(", ")}` : ""}. Анимированные эмодзи подставляются сами, если назначены в «Эмодзи».`, kb([[btn("✖️ Отмена", `a:tk:${key}`)]]));
			return true;
		}
		case "tkr": {
			const map = await readTexts(ctx.env);
			delete map[key];
			await saveTexts(ctx.env, map);
			await toast(ctx, "Возвращён стандартный");
			await showTextCard(ctx, key);
			return true;
		}
		default:
			return false;
	}
}

export async function textsInput(ctx, state, text) {
	if (state.a !== "text_set") {
		return false;
	}
	if (!text || text.length > 3000) {
		await show({ ...ctx, callback: null }, "Текст: от 1 до 3000 символов.", kb([[btn("✖️ Отмена", `a:tk:${state.key}`)]]));
		return true;
	}
	const map = await readTexts(ctx.env);
	map[state.key] = text;
	await saveTexts(ctx.env, map);
	await clearState(ctx.env, ctx.from.id);
	await showTextCard({ ...ctx, callback: null }, state.key);
	return true;
}
