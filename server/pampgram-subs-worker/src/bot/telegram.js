/** Thin Telegram Bot API client. `fetchImpl` is injectable so tests never touch the network. */

export function createTelegram(env, fetchImpl = fetch) {
	async function call(method, params = {}) {
		const response = await fetchImpl(`https://api.telegram.org/bot${env.BOT_TOKEN}/${method}`, {
			method: "POST",
			headers: { "content-type": "application/json" },
			body: JSON.stringify(params),
		});
		let data = null;
		try {
			data = await response.json();
		} catch {
			// handled below
		}
		if (!data || !data.ok) {
			const error = new Error(`telegram ${method}: ${data?.description ?? response.status}`);
			error.code = data?.error_code ?? response.status;
			error.description = data?.description ?? "";
			throw error;
		}
		return data.result;
	}
	return { call };
}

/** Sends, ignoring "can't reach this user" style failures; returns true when delivered. */
export async function trySend(tg, chatId, text, extra = {}) {
	try {
		await tg.call("sendMessage", { chat_id: chatId, text, parse_mode: "HTML", disable_web_page_preview: true, ...extra });
		return true;
	} catch {
		return false;
	}
}
