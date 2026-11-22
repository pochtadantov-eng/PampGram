/** Admin screens for the bot's look: animated emoji and banners. */

import { show, say, toast } from "./context.js";
import { btn, kb, esc } from "./ui.js";
import { getEmoji, saveEmoji, getBanners, saveBanners, getEmojiError, setEmojiError, setState, clearState } from "./store.js";
import { EMOJI_SLOTS, customEmojiIds } from "./emoji.js";

const BACK = kb([[btn("← К эмодзи", "a:em")]]);

// ---------- animated emoji ----------

export async function showEmojiList(ctx) {
	const [map, error] = await Promise.all([getEmoji(ctx.env), getEmojiError(ctx.env)]);
	const done = EMOJI_SLOTS.filter((slot) => map[slot]).length;
	const rows = [];
	for (let i = 0; i < EMOJI_SLOTS.length; i += 4) {
		rows.push(EMOJI_SLOTS.slice(i, i + 4).map((slot, k) => btn(`${slot}${map[slot] ? " ✓" : ""}`, `a:em:${i + k}`)));
	}
	rows.push([btn("🧪 Проверить", "a:emt"), btn("🗑 Сбросить все", "a:emr")]);
	rows.push([btn("← Админка", "a:home")]);
	const lines = [
		"✨ <b>Анимированные эмодзи</b>",
		`Назначено: <b>${done}</b> из ${EMOJI_SLOTS.length}. Нажмите на обычный эмодзи, затем пришлите боту анимированный. Можно прислать сразу несколько: они встанут по порядку на следующие места.`,
		"",
		"Анимация показывается в сообщениях и на кнопках бота. Telegram разрешает это только если у владельца бота есть Telegram Premium (или у бота куплено имя на Fragment); иначе бот продолжит работать с обычными эмодзи.",
	];
	if (error) {
		lines.push("", `⚠️ Последний отказ Telegram: <code>${esc(error.message)}</code>`);
	}
	return show(ctx, lines.join("\n"), kb(rows));
}

async function showEmojiSlot(ctx, index) {
	const slot = EMOJI_SLOTS[index];
	if (!slot) {
		return showEmojiList(ctx);
	}
	const map = await getEmoji(ctx.env);
	await setState(ctx.env, ctx.from.id, { a: "emoji_set", i: index });
	const state = map[slot] ? "сейчас назначен анимированный" : "анимированный пока не назначен";
	return show(
		ctx,
		`Для ${slot} ${state}.\nПришлите анимированный эмодзи (из набора Telegram Premium). Можно несколько подряд: они назначатся на ${slot} и следующие по списку.`,
		kb([[btn("🗑 Убрать этот", `a:emd:${index}`)], [btn("← К эмодзи", "a:em")]])
	);
}

async function testEmoji(ctx) {
	await setEmojiError(ctx.env, null);
	const map = await getEmoji(ctx.env);
	const used = EMOJI_SLOTS.filter((slot) => map[slot]);
	if (used.length === 0) {
		return toast(ctx, "Сначала назначьте хотя бы один", true);
	}
	await toast(ctx);
	await say(ctx, `Проверка: ${used.join(" ")}`, kb([used.slice(0, 3).map((slot) => btn(`${slot} кнопка`, "a:noop"))]));
	const error = await getEmojiError(ctx.env);
	return say(
		ctx,
		error ? `⚠️ Telegram не принял анимированные эмодзи: <code>${esc(error.message)}</code>\nБот показывает обычные.` : "✅ Если выше эмодзи анимируются, всё работает. Если они обычные, у владельца бота нет Premium.",
		BACK
	);
}

// ---------- banners ----------

const BANNERS = { menu: "Главное меню", shop: "Тарифы" };

export async function showBannerList(ctx) {
	const banners = await getBanners(ctx.env);
	const rows = Object.entries(BANNERS).map(([key, title]) => [btn(`${banners[key] ? "✅" : "➕"} ${title}`, `a:im:${key}`)]);
	rows.push([btn("← Админка", "a:home")]);
	return show(ctx, "🖼 <b>Баннеры</b>\nКартинка, GIF или видео над сообщением бота. Выберите экран.", kb(rows));
}

async function showBannerCard(ctx, key) {
	if (!BANNERS[key]) {
		return showBannerList(ctx);
	}
	const banner = (await getBanners(ctx.env))[key];
	const rows = [[btn(banner ? "📤 Заменить" : "📤 Загрузить", `a:ims:${key}`)]];
	if (banner) {
		rows.push([btn("🗑 Убрать", `a:imd:${key}`)]);
	}
	rows.push([btn("← К баннерам", "a:im")]);
	return show(ctx, `🖼 <b>${BANNERS[key]}</b>\n${banner ? `Сейчас: ${{ photo: "картинка", animation: "GIF", video: "видео" }[banner.type]}.` : "Баннера нет."}\nЛучше всего горизонтальная картинка около 1280×720.`, kb(rows));
}

function extractBanner(message) {
	if (message.photo?.length) {
		return { type: "photo", fileId: message.photo[message.photo.length - 1].file_id };
	}
	if (message.animation) {
		return { type: "animation", fileId: message.animation.file_id };
	}
	if (message.video) {
		return { type: "video", fileId: message.video.file_id };
	}
	return null;
}

// ---------- router hooks ----------

/** Returns true when the callback belongs to this module. `parts` is the callback data without "a:". */
export async function visualsCallback(ctx, parts) {
	const [action, arg] = parts;
	switch (action) {
		case "em":
			await toast(ctx);
			if (arg === undefined) {
				await showEmojiList(ctx);
			} else {
				await showEmojiSlot(ctx, parseInt(arg, 10));
			}
			return true;
		case "emd": {
			const slot = EMOJI_SLOTS[parseInt(arg, 10)];
			if (slot) {
				const map = await getEmoji(ctx.env);
				delete map[slot];
				await saveEmoji(ctx.env, map);
			}
			await clearState(ctx.env, ctx.from.id);
			await toast(ctx, "Убрано");
			await showEmojiList(ctx);
			return true;
		}
		case "emr":
			await saveEmoji(ctx.env, {});
			await setEmojiError(ctx.env, null);
			await toast(ctx, "Сброшено");
			await showEmojiList(ctx);
			return true;
		case "emt":
			await testEmoji(ctx);
			return true;
		case "im":
			await toast(ctx);
			await (arg ? showBannerCard(ctx, arg) : showBannerList(ctx));
			return true;
		case "ims":
			if (!BANNERS[arg]) {
				return true;
			}
			await toast(ctx);
			await setState(ctx.env, ctx.from.id, { a: "banner_set", key: arg });
			await show(ctx, "Пришлите картинку (как фото), GIF или видео.", kb([[btn("✖️ Отмена", "a:im")]]));
			return true;
		case "imd": {
			const banners = await getBanners(ctx.env);
			delete banners[arg];
			await saveBanners(ctx.env, banners);
			await toast(ctx, "Убрано");
			await showBannerList(ctx);
			return true;
		}
		default:
			return false;
	}
}

/** Returns true when the admin's message answered one of this module's prompts. */
export async function visualsInput(ctx, state, message) {
	const plain = { ...ctx, callback: null };
	if (state.a === "emoji_set") {
		const ids = customEmojiIds(message);
		if (ids.length === 0) {
			await say(ctx, "Это не анимированный эмодзи. Выберите его в панели эмодзи Telegram Premium и отправьте одним сообщением.", BACK);
			return true;
		}
		const map = await getEmoji(ctx.env);
		let assigned = 0;
		ids.forEach((id, k) => {
			const slot = EMOJI_SLOTS[state.i + k];
			if (slot) {
				map[slot] = id;
				assigned++;
			}
		});
		await saveEmoji(ctx.env, map);
		await clearState(ctx.env, ctx.from.id);
		await say(ctx, `✅ Назначено: ${assigned}.`);
		await showEmojiList(plain);
		return true;
	}
	if (state.a === "banner_set") {
		const banner = extractBanner(message);
		if (!banner) {
			await say(ctx, "Это не картинка, GIF или видео. Пришлите именно фото (не файлом).", kb([[btn("✖️ Отмена", "a:im")]]));
			return true;
		}
		const banners = await getBanners(ctx.env);
		banners[state.key] = banner;
		await saveBanners(ctx.env, banners);
		await clearState(ctx.env, ctx.from.id);
		await showBannerCard(plain, state.key);
		return true;
	}
	return false;
}
