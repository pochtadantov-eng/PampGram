// In-memory stand-ins for Workers KV and the Telegram Bot API, so the Worker and the bot can be
// exercised end to end with `npm test` (Node's built-in runner, no dependencies).

export function createKV() {
	const map = new Map();
	return {
		map,
		async get(key) {
			return map.has(key) ? map.get(key).value : null;
		},
		async put(key, value, options = {}) {
			map.set(key, { value: String(value), metadata: options.metadata ?? null });
		},
		async delete(key) {
			map.delete(key);
		},
		async list({ prefix = "", cursor, limit = 1000 } = {}) {
			const names = [...map.keys()].filter((name) => name.startsWith(prefix)).sort();
			const start = cursor ? parseInt(cursor, 10) : 0;
			const page = names.slice(start, start + limit);
			const complete = start + limit >= names.length;
			return {
				keys: page.map((name) => ({ name, metadata: map.get(name).metadata ?? undefined })),
				list_complete: complete,
				cursor: complete ? undefined : String(start + limit),
			};
		},
	};
}

export function createEnv(extra = {}) {
	return {
		SUBS: createKV(),
		ADMIN_TOKEN: "admin-token",
		RESPONSE_SIGNING_KEY: "signing-key",
		BOT_TOKEN: "123:TEST",
		WEBHOOK_SECRET: "hook-secret",
		ADMIN_TG_IDS: "1000",
		...extra,
	};
}

export function createCtx() {
	const pending = [];
	return {
		pending,
		waitUntil(promise) {
			pending.push(promise);
		},
		async settle() {
			await Promise.all(pending.splice(0));
		},
	};
}

/**
 * A Telegram Bot API double: records every call, answers ok, and lets a test make a method
 * fail for a given chat (e.g. "the user never started the bot").
 */
export function createTelegram() {
	const calls = [];
	const failures = new Map();
	let nextMessageId = 100;
	const api = {
		calls,
		failNext(method, description, code = 403) {
			failures.set(method, { description, code });
		},
		async call(method, params = {}) {
			calls.push({ method, params });
			const failure = failures.get(method);
			if (failure) {
				failures.delete(method);
				const error = new Error(`telegram ${method}: ${failure.description}`);
				error.code = failure.code;
				error.description = failure.description;
				throw error;
			}
			if (method === "sendMessage" || method === "sendDocument") {
				return { message_id: nextMessageId++ };
			}
			return true;
		},
		sent(method) {
			return calls.filter((call) => call.method === method).map((call) => call.params);
		},
		texts() {
			return calls.filter((call) => call.method === "sendMessage").map((call) => call.params.text);
		},
		last(method) {
			const all = api.sent(method);
			return all[all.length - 1];
		},
		reset() {
			calls.length = 0;
		},
	};
	return api;
}

/** Sets the owner password (test value) and runs a guarded admin press through the password prompt. */
export const TEST_PASSWORD = "test-pass-7";
