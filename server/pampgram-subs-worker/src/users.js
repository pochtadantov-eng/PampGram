/**
 * User profiles: everything the admin sees about one Telegram account.
 *
 *   key "u:<id>" -> JSON profile, with a short summary in the KV *metadata* of the same key so
 *   a list() call returns "who, which version, when last seen" for every user without reading
 *   each profile (KV list() returns metadata for free; metadata must stay under 1 KB).
 *
 * Two sources feed a profile, and they share the Telegram account id:
 *   - the app, through /status (version, build, own username/name, last seen, sessions);
 *   - the bot, through any update (username/name as Telegram reports them, whether the user
 *     ever started the bot, purchases).
 * What the app reports about itself is unauthenticated (the route is public by design, see
 * index.js), so version/username from the app are informational, never a basis for access.
 */

import { readSubscription, listAllKeys } from "./core.js";

// A new "visit" starts when the app is seen after being quiet this long.
export const SESSION_GAP_MS = 30 * 60 * 1000;
const MAX_SESSIONS = 40;

export function newUser(id, now) {
	return {
		id: String(id),
		firstSeen: now,
		lastSeen: 0,
		sessions: [],
		username: "",
		name: "",
		appVersion: "",
		appBuild: "",
		bot: null,
		activatedAt: null,
		purchases: 0,
		note: "",
	};
}

export async function getUser(env, id) {
	const raw = await env.SUBS.get(`u:${id}`);
	if (!raw) {
		return null;
	}
	try {
		return { ...newUser(id, Date.now()), ...JSON.parse(raw) };
	} catch {
		return null;
	}
}

function clip(value, length) {
	return typeof value === "string" ? value.slice(0, length) : "";
}

export function summaryOf(user) {
	return {
		ls: user.lastSeen || 0,
		v: clip(user.appVersion, 16),
		un: clip(user.username, 40).toLowerCase(),
		nm: clip(user.name, 40),
		t: user.tier === "pro" ? "pro" : "standard",
		b: user.bot ? 1 : 0,
		a: user.activatedAt ? 1 : 0,
	};
}

export async function saveUser(env, user) {
	await env.SUBS.put(`u:${user.id}`, JSON.stringify(user), { metadata: summaryOf(user) });
}

export async function updateUser(env, id, mutate, now = Date.now()) {
	const user = (await getUser(env, id)) ?? newUser(id, now);
	mutate(user);
	await saveUser(env, user);
	return user;
}

function cleanText(value, length) {
	if (typeof value !== "string") {
		return "";
	}
	// Control characters never belong in a name; the rest is escaped at render time.
	return value.replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, length);
}

/**
 * Called on every /status. `info` is whatever the app chose to send: { version, build,
 * username, name }, each optional.
 */
export async function recordAppSeen(env, id, info, now = Date.now()) {
	return updateUser(
		env,
		id,
		(user) => {
			const previous = user.lastSeen || 0;
			if (previous === 0 || now - previous > SESSION_GAP_MS) {
				user.sessions = [...(user.sessions ?? []), now].slice(-MAX_SESSIONS);
			}
			user.lastSeen = now;
			const version = cleanText(info?.version, 16);
			if (version) {
				user.appVersion = version;
			}
			const build = cleanText(info?.build, 16);
			if (build) {
				user.appBuild = build;
			}
			const username = cleanText(info?.username, 40).replace(/^@/, "");
			if (username) {
				user.username = username;
			}
			const name = cleanText(info?.name, 80);
			if (name) {
				user.name = name;
			}
		},
		now
	);
}

/** Called for every bot update that has a sender. */
export async function recordBotSeen(env, from, now = Date.now()) {
	const id = String(from.id);
	return updateUser(
		env,
		id,
		(user) => {
			user.bot = { ...(user.bot ?? { startedAt: now }), lastAt: now, blocked: false, lang: cleanText(from.language_code, 8) };
			const username = cleanText(from.username, 40);
			if (username) {
				user.username = username;
			}
			const name = cleanText([from.first_name, from.last_name].filter(Boolean).join(" "), 80);
			if (name) {
				user.name = name;
			}
		},
		now
	);
}

export async function noteTier(env, id, tier, now = Date.now()) {
	await updateUser(env, id, (user) => {
		user.tier = tier === "pro" ? "pro" : "standard";
		user.tierChangedAt = now;
	}, now);
}

export function displayName(user) {
	const handle = user.username ? `@${user.username}` : "";
	return [handle, user.name].filter(Boolean).join(" · ") || `id ${user.id}`;
}

/** Every known user as { id, ...summary }, newest activity first. Reads no profile bodies. */
export async function listUserSummaries(env) {
	const keys = await listAllKeys(env, "u:");
	const users = keys.map((key) => ({ id: key.name.slice(2), ...(key.metadata ?? {}) }));
	users.sort((a, b) => (b.ls || 0) - (a.ls || 0));
	return users;
}

/**
 * Users the app has seen before profiles existed (only "seen:<id>" keys) get a profile on first
 * need. Safe to run repeatedly.
 */
export async function importLegacyUsers(env) {
	const [seenKeys, subKeys] = await Promise.all([listAllKeys(env, "seen:"), listAllKeys(env, "sub:")]);
	const existing = new Set((await listAllKeys(env, "u:")).map((key) => key.name.slice(2)));
	let imported = 0;
	const ids = new Set([...seenKeys.map((k) => k.name.slice(5)), ...subKeys.map((k) => k.name.slice(4))]);
	for (const id of ids) {
		if (existing.has(id)) {
			continue;
		}
		const lastSeen = parseInt(await env.SUBS.get(`seen:${id}`), 10);
		const subscription = await readSubscription(env, id);
		const user = newUser(id, Number.isInteger(lastSeen) ? lastSeen : Date.now());
		user.lastSeen = Number.isInteger(lastSeen) ? lastSeen : 0;
		user.tier = subscription.tier;
		if (user.lastSeen) {
			user.sessions = [user.lastSeen];
		}
		await saveUser(env, user);
		imported++;
	}
	return imported;
}

// Local ledger is capped at 2000 ops on device; return the whole synced journal to the admin.
const MAX_ADMIN_LEDGER_OPS = 2000;

const GIFT_OP_TITLES = new Set([
	"Покупка подарка",
	"Подарок мне",
	"Улучшение подарка",
	"Продажа подарка",
	"Передача подарка",
	"Комиссия за передачу",
	"Продажа на маркете",
	"Подарок Premium",
]);

function ledgerField(value) {
	if (value && typeof value === "object" && typeof value.value === "string") {
		return value.value;
	}
	return typeof value === "string" ? value : "";
}

function ledgerGiftId(value) {
	if (value === null || value === undefined || value === "") {
		return null;
	}
	const n = Number(value);
	return Number.isFinite(n) ? n : null;
}

function isGiftOperation(title, giftId) {
	return giftId !== null || GIFT_OP_TITLES.has(title);
}

/**
 * Turns the opaque ledgersync:<id> JSON (fake Stars/TON + local operations) into totals and the
 * full ops list the admin panel can show — including NFT/gift rows (giftId + gift name in
 * details). Returns null when nothing useful is stored.
 */
export function summarizeLedger(raw) {
	if (!raw || typeof raw !== "string") {
		return null;
	}
	let payload;
	try {
		payload = JSON.parse(raw);
	} catch {
		return null;
	}
	if (!payload || typeof payload !== "object") {
		return null;
	}
	const starsBalance = Number(payload.starsBalance) || 0;
	const tonBalanceNanos = Number(payload.tonBalanceNanos) || 0;
	const rublesBalanceKopecks = Number(payload.rublesBalanceKopecks) || 0;
	const operationsIn = Array.isArray(payload.operations) ? payload.operations : [];
	let starsSpent = 0;
	let starsReceived = 0;
	let tonSpentNanos = 0;
	let tonReceivedNanos = 0;
	let rublesSpent = 0;
	let rublesReceived = 0;
	let nftReceived = 0;
	let nftBought = 0;
	let nftSold = 0;
	let nftTransferred = 0;
	const operations = [];
	const nfts = [];
	for (const op of operationsIn) {
		if (!op || typeof op !== "object") {
			continue;
		}
		const currency = ledgerField(op.currency);
		const kind = ledgerField(op.kind);
		const amount = Number(op.amount) || 0;
		const title = typeof op.title === "string" ? op.title.slice(0, 120) : "";
		const details = typeof op.details === "string" ? op.details.slice(0, 200) : "";
		const giftId = ledgerGiftId(op.giftId);
		if (currency === "stars") {
			if (amount < 0) {
				starsSpent += -amount;
			} else {
				starsReceived += amount;
			}
		} else if (currency === "ton") {
			if (amount < 0) {
				tonSpentNanos += -amount;
			} else {
				tonReceivedNanos += amount;
			}
		} else if (currency === "rubles") {
			if (amount < 0) {
				rublesSpent += -amount;
			} else {
				rublesReceived += amount;
			}
		}
		const row = {
			id: Number(op.id) || 0,
			currency,
			kind,
			amount,
			date: Number(op.date) || 0,
			title,
			details,
			giftId,
			isGift: isGiftOperation(title, giftId),
		};
		operations.push(row);
		if (row.isGift) {
			if (title === "Подарок мне") {
				nftReceived += 1;
			} else if (title === "Покупка подарка" || title === "Улучшение подарка") {
				nftBought += 1;
			} else if (title === "Продажа подарка" || title === "Продажа на маркете") {
				nftSold += 1;
			} else if (title === "Передача подарка") {
				nftTransferred += 1;
			}
			nfts.push({
				name: details || title || "Gift",
				action: title || kind,
				currency,
				amount,
				date: row.date,
				giftId,
			});
		}
	}
	operations.sort((a, b) => b.date - a.date || b.id - a.id);
	nfts.sort((a, b) => b.date - a.date);
	return {
		starsBalance,
		tonBalanceNanos,
		rublesBalanceKopecks,
		starsSpent,
		starsReceived,
		tonSpentNanos,
		tonReceivedNanos,
		rublesSpent,
		rublesReceived,
		nftReceived,
		nftBought,
		nftSold,
		nftTransferred,
		nfts: nfts.slice(0, MAX_ADMIN_LEDGER_OPS),
		operations: operations.slice(0, MAX_ADMIN_LEDGER_OPS),
		operationCount: operationsIn.length,
	};
}

const MAX_ADMIN_REAL_TX = 400;

const GIFT_FLAG_SET = new Set([
	"gift",
	"gift_upgrade",
	"gift_resale",
	"gift_prepaid_upgrade",
	"gift_drop_details",
	"gift_auction",
	"gift_offer",
]);

function isRealGiftTx(flags, giftTitle, title, description) {
	if (giftTitle) {
		return true;
	}
	if (flags.some((f) => GIFT_FLAG_SET.has(f))) {
		return true;
	}
	return /gift|подар|nft|star gift/i.test(`${title} ${description}`);
}

/** Human-readable gift direction for the admin card. */
function realGiftAction(flags, amount, title, description) {
	const text = `${title} ${description}`;
	if (flags.includes("refund")) {
		return "Возврат";
	}
	if (flags.includes("gift_resale")) {
		return amount < 0 ? "Покупка (ресейл)" : "Продажа (ресейл)";
	}
	if (flags.includes("gift_upgrade") || flags.includes("gift_prepaid_upgrade")) {
		return "Апгрейд";
	}
	if (flags.includes("gift_drop_details")) {
		return "Сброс деталей";
	}
	if (flags.includes("gift_auction")) {
		return amount < 0 ? "Ставка на аукционе" : "Аукцион";
	}
	if (flags.includes("gift_offer")) {
		return amount < 0 ? "Оффер отправлен" : "Оффер получен";
	}
	if (/продаж|sale|sold|resale/i.test(text)) {
		return "Продажа";
	}
	if (/перевод|transfer|отправ|sent|send/i.test(text)) {
		return amount < 0 ? "Отправка" : "Получение";
	}
	if (/покуп|buy|purchase|bought/i.test(text)) {
		return "Покупка";
	}
	if (/получен|received|incoming|подар.*мне|to me/i.test(text)) {
		return "Получение";
	}
	if (amount < 0) {
		return "Покупка / отправка";
	}
	if (amount > 0) {
		return "Получение / продажа";
	}
	return "Подарок";
}

function realStarsAction(amount, peer, title) {
	const text = `${peer} ${title}`;
	if (/refund|возврат/i.test(text) || amount > 0 && /refund/i.test(text)) {
		return amount >= 0 ? "Возврат" : "Списание";
	}
	if (amount > 0) {
		if (/app store|play market|fragment|premium bot/i.test(text)) {
			return "Пополнение";
		}
		return "Пополнение";
	}
	if (amount < 0) {
		return "Списание";
	}
	return "Операция";
}

/**
 * Real Telegram Stars/TON history pushed by the install via /sync-real-ledger
 * (`payments.getStarsTransactions` on that account). Separate from the local fake ledger.
 *
 * Returns three admin lists (real Telegram only — no visual/mod ledger):
 * - `gifts` — gift/NFT-related ops (buy/sell/send/receive/upgrade/…) in Stars or TON
 * - `stars` — plain Stars top-ups and debits (no gifts)
 * - `ton` — plain TON transfers / top-ups / debits (no gifts)
 */
export function summarizeRealLedger(raw) {
	if (!raw || typeof raw !== "string") {
		return null;
	}
	let payload;
	try {
		payload = JSON.parse(raw);
	} catch {
		return null;
	}
	if (!payload || typeof payload !== "object") {
		return null;
	}
	const starsBalance = Number(payload.starsBalance) || 0;
	const tonBalanceNanos = Number(payload.tonBalanceNanos) || 0;
	const updatedAt = Number(payload.updatedAt) || 0;
	const transactionsIn = Array.isArray(payload.transactions) ? payload.transactions : [];
	let starsSpent = 0;
	let starsReceived = 0;
	let tonSpentNanos = 0;
	let tonReceivedNanos = 0;
	let giftOps = 0;
	const transactions = [];
	const gifts = [];
	const stars = [];
	const ton = [];
	for (const tx of transactionsIn) {
		if (!tx || typeof tx !== "object") {
			continue;
		}
		const currency = typeof tx.currency === "string" ? tx.currency : "stars";
		const amount = Number(tx.amount) || 0;
		const title = typeof tx.title === "string" ? tx.title.slice(0, 160) : "";
		const description = typeof tx.description === "string" ? tx.description.slice(0, 240) : "";
		const peer = typeof tx.peer === "string" ? tx.peer.slice(0, 120) : "";
		const giftTitle = typeof tx.giftTitle === "string" ? tx.giftTitle.slice(0, 160) : "";
		const flags = Array.isArray(tx.flags) ? tx.flags.filter((f) => typeof f === "string").slice(0, 20) : [];
		if (currency === "ton") {
			if (amount < 0) {
				tonSpentNanos += -amount;
			} else {
				tonReceivedNanos += amount;
			}
		} else if (currency === "stars") {
			if (amount < 0) {
				starsSpent += -amount;
			} else {
				starsReceived += amount;
			}
		}
		const gift = isRealGiftTx(flags, giftTitle, title, description);
		const action = gift
			? realGiftAction(flags, amount, title, description)
			: currency === "stars"
				? realStarsAction(amount, peer, title)
				: amount < 0
					? "Списание"
					: "Пополнение";
		const row = {
			id: typeof tx.id === "string" ? tx.id.slice(0, 80) : String(tx.id ?? ""),
			currency,
			amount,
			date: Number(tx.date) || 0,
			title,
			description,
			peer,
			giftTitle,
			flags,
			action,
		};
		transactions.push(row);
		if (gift) {
			giftOps += 1;
			gifts.push(row);
		} else if (currency === "stars") {
			stars.push(row);
		} else if (currency === "ton") {
			ton.push(row);
		}
	}
	transactions.sort((a, b) => b.date - a.date);
	gifts.sort((a, b) => b.date - a.date);
	stars.sort((a, b) => b.date - a.date);
	ton.sort((a, b) => b.date - a.date);
	return {
		starsBalance,
		tonBalanceNanos,
		updatedAt,
		starsSpent,
		starsReceived,
		tonSpentNanos,
		tonReceivedNanos,
		giftOps,
		transactions: transactions.slice(0, MAX_ADMIN_REAL_TX),
		gifts: gifts.slice(0, MAX_ADMIN_REAL_TX),
		stars: stars.slice(0, MAX_ADMIN_REAL_TX),
		ton: ton.slice(0, MAX_ADMIN_REAL_TX),
		transactionCount: transactionsIn.length,
	};
}
