/**
 * Emergency write path when Cloudflare's free KV daily put quota (1000/day) is exhausted.
 *
 * Reads still prefer real KV. On put/delete limit errors, values go into the Cache API instead
 * and an index key tracks them so list({ prefix }) keeps working (gift-transfer pickup, user
 * lists, etc.). Per-colo Cache is weaker than KV — fine as a bridge until 00:00 UTC reset or
 * Workers Paid — not a permanent store.
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
			const parsed = await hit.json();
			return Array.isArray(parsed) ? parsed.filter((item) => typeof item === "string") : [];
		} catch {
			return [];
		}
	}

	async function writeIndex(keys) {
		await cache.put(
			cacheRequest(INDEX_KEY),
			new Response(JSON.stringify(keys), {
				headers: { "Cache-Control": "max-age=86400", "content-type": "application/json" },
			})
		);
	}

	async function addToIndex(key) {
		const keys = await readIndex();
		if (!keys.includes(key)) {
			keys.push(key);
			await writeIndex(keys);
		}
	}

	async function removeFromIndex(key) {
		const keys = await readIndex();
		const next = keys.filter((item) => item !== key);
		if (next.length !== keys.length) {
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
		if (options?.metadata && typeof options.metadata === "object") {
			headers["X-Pamp-Metadata"] = JSON.stringify(options.metadata);
		}
		const body = typeof value === "string" ? value : String(value);
		await cache.put(cacheRequest(key), new Response(body, { headers }));
		await addToIndex(key);
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
					// Prefer the durable copy; drop any stale cache entry.
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
			// Inject fallback keys only on the first page so listAllKeys does not duplicate them.
			if (options.cursor) {
				return result;
			}
			const fallbackKeys = (await readIndex()).filter((name) => name.startsWith(prefix));
			const seen = new Set(result.keys.map((entry) => entry.name));
			for (const name of fallbackKeys) {
				if (seen.has(name)) {
					continue;
				}
				let metadata = null;
				const hit = await cacheGetRaw(name);
				if (hit) {
					const rawMeta = hit.headers.get("X-Pamp-Metadata");
					if (rawMeta) {
						try {
							metadata = JSON.parse(rawMeta);
						} catch {
							metadata = null;
						}
					}
				}
				result.keys.push({ name, metadata });
				seen.add(name);
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
