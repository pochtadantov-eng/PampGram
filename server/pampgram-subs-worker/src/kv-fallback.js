/**
 * Emergency write path when Cloudflare's free KV daily put quota (1000/day) is exhausted.
 *
 * Reads still prefer real KV. On put/delete limit errors, values go into the Cache API instead
 * and an index key tracks them so list({ prefix }) keeps working (gift-transfer pickup, user
 * lists, etc.). Per-colo Cache is weaker than KV — fine as a bridge until 00:00 UTC reset or
 * Workers Paid — not a permanent store.
 *
 * Index entries are `{ k, m }` so list() can return metadata without an extra cache.match per
 * key (free plan: 50 subrequests/invocation — fetching every indexed key blew /users-list).
 */

const INDEX_KEY = "__pamp_fb_index__";
const CACHE_ORIGIN = "https://pampgram-kv-fallback.internal";

function isKvLimitError(error) {
	const message = String(error && error.message ? error.message : error);
	return /limit exceeded/i.test(message);
}

function cacheRequest(key) {
	return new Request(`${CACHE_ORIGIN}/${encodeURIComponent(key)}`);
}

/** In-memory Cache stand-in for Node unit tests (no global `caches`). */
function memoryCache() {
	const map = new Map();
	return {
		async match(request) {
			const key = typeof request === "string" ? request : request.url;
			const entry = map.get(key);
			return entry ? entry.clone() : undefined;
		},
		async put(request, response) {
			const key = typeof request === "string" ? request : request.url;
			map.set(key, response.clone());
		},
		async delete(request) {
			const key = typeof request === "string" ? request : request.url;
			return map.delete(key);
		},
	};
}

function defaultCache() {
	try {
		if (typeof caches !== "undefined" && caches.default) {
			return caches.default;
		}
	} catch {
		// Workers always have caches; Node tests do not.
	}
	return memoryCache();
}

function normalizeIndex(parsed) {
	if (!Array.isArray(parsed)) {
		return [];
	}
	const out = [];
	for (const item of parsed) {
		if (typeof item === "string") {
			out.push({ k: item, m: null });
		} else if (item && typeof item === "object" && typeof item.k === "string") {
			out.push({ k: item.k, m: item.m && typeof item.m === "object" ? item.m : null });
		}
	}
	return out;
}

/**
 * @param {KVNamespace} kv
 * @param {Cache} cache
 */
export function wrapSubsWithCacheFallback(kv, cache = defaultCache()) {
	/** @type {boolean|null} */
	let writesBlocked = null;

	async function readIndex() {
		const hit = await cache.match(cacheRequest(INDEX_KEY));
		if (!hit) {
			return [];
		}
		try {
			return normalizeIndex(await hit.json());
		} catch {
			return [];
		}
	}

	async function writeIndex(entries) {
		await cache.put(
			cacheRequest(INDEX_KEY),
			new Response(JSON.stringify(entries), {
				headers: { "Cache-Control": "max-age=86400", "content-type": "application/json" },
			})
		);
	}

	async function addToIndex(key, metadata) {
		const entries = await readIndex();
		const nextMeta = metadata && typeof metadata === "object" ? metadata : null;
		const index = entries.findIndex((entry) => entry.k === key);
		if (index >= 0) {
			entries[index] = { k: key, m: nextMeta };
		} else {
			entries.push({ k: key, m: nextMeta });
		}
		await writeIndex(entries);
	}

	async function removeFromIndex(key) {
		const entries = await readIndex();
		const next = entries.filter((entry) => entry.k !== key);
		if (next.length !== entries.length) {
			await writeIndex(next);
		}
	}

	async function cacheGetRaw(key) {
		return cache.match(cacheRequest(key));
	}

	async function cachePutValue(key, value, options) {
		const maxAge = typeof options?.expirationTtl === "number" && options.expirationTtl > 0
			? Math.floor(options.expirationTtl)
			: 86400;
		const headers = {
			"Cache-Control": `max-age=${maxAge}`,
			"content-type": "text/plain; charset=utf-8",
		};
		const metadata = options?.metadata && typeof options.metadata === "object" ? options.metadata : null;
		if (metadata) {
			headers["X-Pamp-Metadata"] = JSON.stringify(metadata);
		}
		const body = typeof value === "string" ? value : String(value);
		await cache.put(cacheRequest(key), new Response(body, { headers }));
		await addToIndex(key, metadata);
	}

	async function cacheDeleteValue(key) {
		await cache.delete(cacheRequest(key));
		await removeFromIndex(key);
	}

	return {
		async get(key, typeOrOpts) {
			const fromKv = await kv.get(key, typeOrOpts);
			if (fromKv !== null && fromKv !== undefined) {
				return fromKv;
			}
			const hit = await cacheGetRaw(key);
			if (!hit) {
				return null;
			}
			const type = typeof typeOrOpts === "string" ? typeOrOpts : typeOrOpts?.type;
			if (type === "json") {
				return hit.json();
			}
			if (type === "arrayBuffer") {
				return hit.arrayBuffer();
			}
			if (type === "stream") {
				return hit.body;
			}
			return hit.text();
		},

		async getWithMetadata(key, typeOrOpts) {
			const fromKv = await kv.getWithMetadata(key, typeOrOpts);
			if (fromKv && fromKv.value !== null && fromKv.value !== undefined) {
				return fromKv;
			}
			const hit = await cacheGetRaw(key);
			if (!hit) {
				return { value: null, metadata: null };
			}
			let metadata = null;
			const rawMeta = hit.headers.get("X-Pamp-Metadata");
			if (rawMeta) {
				try {
					metadata = JSON.parse(rawMeta);
				} catch {
					metadata = null;
				}
			}
			const type = typeof typeOrOpts === "string" ? typeOrOpts : typeOrOpts?.type;
			let value;
			if (type === "json") {
				value = await hit.json();
			} else if (type === "arrayBuffer") {
				value = await hit.arrayBuffer();
			} else if (type === "stream") {
				value = hit.body;
			} else {
				value = await hit.text();
			}
			return { value, metadata };
		},

		async put(key, value, options) {
			if (writesBlocked !== true) {
				try {
					await kv.put(key, value, options);
					writesBlocked = false;
					await cacheDeleteValue(key).catch(() => {});
					return;
				} catch (error) {
					if (!isKvLimitError(error)) {
						throw error;
					}
					writesBlocked = true;
				}
			}
			await cachePutValue(key, value, options);
		},

		async delete(key) {
			try {
				await kv.delete(key);
			} catch (error) {
				if (!isKvLimitError(error)) {
					throw error;
				}
				writesBlocked = true;
			}
			await cacheDeleteValue(key).catch(() => {});
		},

		async list(options = {}) {
			const prefix = typeof options.prefix === "string" ? options.prefix : "";
			const limit = typeof options.limit === "number" ? options.limit : 1000;
			const result = await kv.list(options);
			if (options.cursor) {
				return result;
			}
			// Metadata comes from the index itself — no per-key cache.match (subrequest budget).
			const fallbackEntries = (await readIndex()).filter((entry) => entry.k.startsWith(prefix));
			const seen = new Set(result.keys.map((entry) => entry.name));
			for (const entry of fallbackEntries) {
				if (seen.has(entry.k)) {
					continue;
				}
				result.keys.push({ name: entry.k, metadata: entry.m });
				seen.add(entry.k);
				if (result.keys.length >= limit) {
					break;
				}
			}
			return result;
		},
	};
}

/** Returns a shallow env clone whose SUBS binding is wrapped with the cache fallback. */
export function withSubsFallback(env) {
	return {
		...env,
		SUBS: wrapSubsWithCacheFallback(env.SUBS),
	};
}
