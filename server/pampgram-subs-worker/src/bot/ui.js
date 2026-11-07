/** Formatting and keyboard helpers shared by the bot's user and admin flows. */

export function esc(value) {
	return String(value ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

export const btn = (text, data) => ({ text, callback_data: data });
export const urlBtn = (text, url) => ({ text, url });
export const kb = (rows) => ({ reply_markup: { inline_keyboard: rows } });

export function fmtTime(ms, tz = "Europe/Moscow") {
	if (!ms) {
		return "—";
	}
	return new Intl.DateTimeFormat("ru-RU", {
		timeZone: tz,
		day: "2-digit",
		month: "2-digit",
		year: "numeric",
		hour: "2-digit",
		minute: "2-digit",
	}).format(new Date(ms));
}

export function fmtAgo(ms, now = Date.now()) {
	if (!ms) {
		return "никогда";
	}
	const seconds = Math.max(0, Math.floor((now - ms) / 1000));
	if (seconds < 90) {
		return "только что";
	}
	const minutes = Math.floor(seconds / 60);
	if (minutes < 60) {
		return `${minutes} мин назад`;
	}
	const hours = Math.floor(minutes / 60);
	if (hours < 24) {
		return `${hours} ч назад`;
	}
	const days = Math.floor(hours / 24);
	return `${days} дн назад`;
}

export function fmtHours(hours) {
	if (!hours || hours <= 0) {
		return "навсегда";
	}
	if (hours % 24 === 0) {
		const days = hours / 24;
		return `${days} дн`;
	}
	return `${hours} ч`;
}

export const tierLabel = (tier) => (tier === "pro" ? "Premium" : "Standard");

/** "1 234" style grouping for money-like numbers. */
export const fmtNumber = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
