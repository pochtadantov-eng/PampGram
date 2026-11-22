/**
 * TON payments straight to the owner's own wallet (Tonkeeper or any other), checked on-chain.
 *
 * A manual payment method becomes "auto-checked" once the owner sets `tonAddress` on it (and its
 * currency is TON). The buyer sends `order.amount` TON to that address with the comment
 * `PMP-<orderId>`; the bot reads the address's recent incoming transactions from toncenter.com
 * and, on a match (same comment, at least the amount, after the order was created, not used
 * before), releases the key exactly like an admin's confirmation would. Nothing custodial: the
 * money never passes through anyone but the blockchain.
 *
 *   "tonwait:<orderId>" -> "1" (24 h TTL)   orders the cron re-checks every 10 minutes
 *   "tontx:<txHash>"    -> orderId           a transaction can pay for one order only
 */

import { getUser } from "../users.js";
import { getOrder, getPayMethods } from "./store.js";
import { fulfillOrder } from "./shop.js";
import { listAllKeys } from "../core.js";

export const TONCENTER = "https://toncenter.com/api/v2/getTransactions";
const WAIT_TTL_SECONDS = 24 * 60 * 60;
const MAX_CHECKS_PER_RUN = 10;

/** Friendly (EQ…/UQ…, 48 chars) or raw (0:<64 hex>) address. */
export function isTonAddress(text) {
	return /^[A-Za-z0-9_-]{48}$/.test(text) || /^-?\d:[0-9a-fA-F]{64}$/.test(text);
}

export const tonComment = (order) => `PMP-${order.id}`;

export const toNano = (amount) => BigInt(Math.round(Number(amount) * 1e9));

export function tonkeeperLink(address, order) {
	return `https://app.tonkeeper.com/transfer/${encodeURIComponent(address)}?amount=${toNano(order.amount)}&text=${encodeURIComponent(tonComment(order))}`;
}

export function isAutoTon(method) {
	return Boolean(method && method.tonAddress && (method.kind === "ton" || (method.kind === "manual" && String(method.currency).toUpperCase() === "TON")));
}

const RATE_KEY = "tonrate:rub";
const RATE_FRESH_MS = 5 * 60 * 1000;
const RATE_STALE_OK_MS = 6 * 60 * 60 * 1000;

async function fetchRubRate(fetchImpl) {
	try {
		const response = await fetchImpl("https://tonapi.io/v2/rates?tokens=ton&currencies=rub");
		const data = await response.json();
		const rate = Number(data?.rates?.TON?.prices?.RUB);
		if (rate > 0) {
			return rate;
		}
	} catch {
		// fall through to the second source
	}
	try {
		const response = await fetchImpl("https://api.coingecko.com/api/v3/simple/price?ids=the-open-network&vs_currencies=rub");
		const data = await response.json();
		const rate = Number(data?.["the-open-network"]?.rub);
		if (rate > 0) {
			return rate;
		}
	} catch {
		// no source answered
	}
	return null;
}

/**
 * Price of 1 TON in rubles: tonapi.io, falling back to CoinGecko; cached 5 minutes in KV. If
 * both are down, a cached value up to 6 hours old is still used; otherwise null.
 */
export async function tonRubRate(env, fetchImpl = fetch, now = Date.now()) {
	let cached = null;
	try {
		cached = JSON.parse((await env.SUBS.get(RATE_KEY)) ?? "null");
	} catch {
		cached = null;
	}
	if (cached && cached.rate > 0 && now - cached.at < RATE_FRESH_MS) {
		return cached.rate;
	}
	const rate = await fetchRubRate(fetchImpl);
	if (rate) {
		await env.SUBS.put(RATE_KEY, JSON.stringify({ rate, at: now }));
		return rate;
	}
	if (cached && cached.rate > 0 && now - cached.at < RATE_STALE_OK_MS) {
		return cached.rate;
	}
	return null;
}

/** Rubles -> TON at `rate` (₽ per TON), rounded up to 0.01 TON. */
export function rubToTon(rub, rate) {
	return Math.ceil((rub / rate) * 100 - 1e-9) / 100;
}

async function fetchIncoming(address, fetchImpl) {
	const response = await fetchImpl(`${TONCENTER}?address=${encodeURIComponent(address)}&limit=50`);
	const data = await response.json();
	if (!data || !data.ok || !Array.isArray(data.result)) {
		return [];
	}
	return data.result
		.filter((tx) => tx && tx.in_msg && tx.in_msg.source)
		.map((tx) => ({
			hash: String(tx.transaction_id?.hash ?? ""),
			utime: Number(tx.utime ?? 0),
			value: String(tx.in_msg.value ?? "0"),
			comment: String(tx.in_msg.message ?? "").trim(),
		}));
}

/** The matching, still unused incoming transaction for `order`, or null. */
export async function findTonPayment(env, address, order, fetchImpl = fetch, incoming = null) {
	const list = incoming ?? (await fetchIncoming(address, fetchImpl));
	const comment = tonComment(order);
	const need = toNano(order.amount);
	for (const tx of list) {
		if (!tx.hash || tx.comment !== comment || tx.utime * 1000 < order.createdAt - 60_000) {
			continue;
		}
		let value = 0n;
		try {
			value = BigInt(tx.value);
		} catch {
			continue;
		}
		if (value < need) {
			continue;
		}
		const usedBy = await env.SUBS.get(`tontx:${tx.hash}`);
		if (usedBy && usedBy !== order.id) {
			continue;
		}
		return tx;
	}
	return null;
}

export async function markTonWaiting(env, order) {
	await env.SUBS.put(`tonwait:${order.id}`, "1", { expirationTtl: WAIT_TTL_SECONDS });
}

/** Releases the order if its payment is on-chain. Returns true when it was paid now. */
export async function confirmIfPaid(env, tg, order, method, now, fetchImpl = fetch, incoming = null) {
	if (!order || order.status !== "awaiting" || !isAutoTon(method)) {
		return false;
	}
	const tx = await findTonPayment(env, method.tonAddress, order, fetchImpl, incoming);
	if (!tx) {
		return false;
	}
	await env.SUBS.put(`tontx:${tx.hash}`, order.id);
	await env.SUBS.delete(`tonwait:${order.id}`);
	order.tonTx = tx.hash;
	const user = await getUser(env, order.userId);
	const buyer = { id: order.userId, username: user?.username ?? "" };
	const buyerCtx = { env, tg, now, chatId: order.userId, callback: null, from: buyer };
	await fulfillOrder(buyerCtx, order, buyer, true);
	return true;
}

/** Cron: re-check every order still waiting for a TON transfer. */
export async function checkTonOrders(env, tg, now, fetchImpl = fetch) {
	const waiting = (await listAllKeys(env, "tonwait:")).slice(0, MAX_CHECKS_PER_RUN);
	if (waiting.length === 0) {
		return 0;
	}
	const methods = await getPayMethods(env);
	const cache = new Map();
	let paid = 0;
	for (const key of waiting) {
		const order = await getOrder(env, key.name.slice("tonwait:".length));
		if (!order || order.status !== "awaiting") {
			await env.SUBS.delete(key.name);
			continue;
		}
		const method = methods.find((item) => item.id === order.method);
		if (!isAutoTon(method)) {
			continue;
		}
		try {
			if (!cache.has(method.tonAddress)) {
				cache.set(method.tonAddress, await fetchIncoming(method.tonAddress, fetchImpl));
			}
			if (await confirmIfPaid(env, tg, order, method, now, fetchImpl, cache.get(method.tonAddress))) {
				paid += 1;
			}
		} catch {
			// toncenter unavailable: the next run tries again
		}
	}
	return paid;
}


