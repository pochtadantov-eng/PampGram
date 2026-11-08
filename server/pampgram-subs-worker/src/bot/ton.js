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
	return Boolean(method && method.kind === "manual" && method.tonAddress && String(method.currency).toUpperCase() === "TON");
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


