const MAX_VIDEO_URL_LENGTH = 2000;

function isHttpsVideoUrl(url) {
	if (typeof url !== "string" || url.length === 0 || url.length > MAX_VIDEO_URL_LENGTH) {
		return false;
	}
	let parsed;
	try {
		parsed = new URL(url);
	} catch {
		return false;
	}
	return parsed.protocol === "https:";
}

export function parseForceVideo(raw) {
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
	if (typeof payload.id !== "string" || !payload.id || !isHttpsVideoUrl(payload.url)) {
		return null;
	}
	return {
		id: payload.id.slice(0, 80),
		url: payload.url,
		loop: payload.loop !== false,
		dismissible: payload.dismissible === true,
		createdAt: Number(payload.createdAt) || 0,
	};
}

export async function readForceVideo(env, userIdString) {
	const [userRaw, globalRaw] = await Promise.all([
		env.SUBS.get(`forcevideo:user:${userIdString}`),
		env.SUBS.get("forcevideo:global"),
	]);
	return parseForceVideo(userRaw) || parseForceVideo(globalRaw);
}

export async function writeForceVideo(env, target, url, options = {}) {
	if (!isHttpsVideoUrl(url)) {
		return { ok: false, error: "invalid url" };
	}
	const video = {
		id: crypto.randomUUID(),
		url: url.trim(),
		loop: options.loop !== false,
		dismissible: options.dismissible === true,
		createdAt: Date.now(),
	};
	const body = JSON.stringify(video);
	if (target === "all") {
		await env.SUBS.put("forcevideo:global", body);
	} else {
		await env.SUBS.put(`forcevideo:user:${target}`, body);
	}
	return { ok: true, video };
}

export async function clearForceVideo(env, target) {
	if (target === "all") {
		await env.SUBS.delete("forcevideo:global");
		return { ok: true };
	}
	await env.SUBS.delete(`forcevideo:user:${target}`);
	return { ok: true };
}
