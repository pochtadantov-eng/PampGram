#!/usr/bin/env bash
# One-shot deploy for the PampGram subscription backend.
#
# Does everything by hand that the README's step-by-step otherwise spells out:
# installs wrangler, creates the KV namespace, patches wrangler.toml with its id,
# generates a fresh ADMIN_TOKEN, sets it as a Cloudflare secret, deploys, and
# prints exactly what you need to paste back into the app and into chat.
#
# The one thing this script can't do for you: `wrangler login` opens a browser
# for you to approve access to your own Cloudflare account. Everything else is
# non-interactive.
#
# Usage:
#   cd server/pampgram-subs-worker
#   bash deploy.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "== 1/7: checking for npm =="
if ! command -v npm >/dev/null 2>&1; then
	echo "npm not found. Install Node.js from https://nodejs.org first, then re-run this script." >&2
	exit 1
fi

echo "== 2/7: installing wrangler (via npx, no global install needed) =="
WRANGLER="npx --yes wrangler"

echo "== 3/7: Cloudflare login =="
echo "A browser window will open — click Allow. If you're already logged in, this is instant."
$WRANGLER login

echo "== 4/7: creating the KV namespace and patching wrangler.toml =="
if grep -q "REPLACE_WITH_KV_NAMESPACE_ID" wrangler.toml; then
	KV_OUTPUT="$($WRANGLER kv namespace create SUBS 2>&1)"
	echo "$KV_OUTPUT"
	KV_ID="$(echo "$KV_OUTPUT" | grep -oE '"[0-9a-f]{32}"' | head -1 | tr -d '"')"
	if [ -z "$KV_ID" ]; then
		echo "Couldn't auto-detect the KV namespace id from wrangler's output above." >&2
		echo "Open wrangler.toml, replace REPLACE_WITH_KV_NAMESPACE_ID with the id shown above yourself, then re-run this script." >&2
		exit 1
	fi
	sed -i.bak "s/REPLACE_WITH_KV_NAMESPACE_ID/$KV_ID/" wrangler.toml
	rm -f wrangler.toml.bak
	echo "wrangler.toml updated with KV namespace id $KV_ID"
else
	echo "wrangler.toml already has a KV namespace id — skipping creation."
fi

echo "== 5/7: generating ADMIN_TOKEN and setting it as a Cloudflare secret =="
ADMIN_TOKEN="$(openssl rand -hex 32)"
echo "$ADMIN_TOKEN" | $WRANGLER secret put ADMIN_TOKEN

echo "== 6/7: setting RESPONSE_SIGNING_KEY =="
# Fixed, not randomly generated: this exact value is already baked into every copy of the
# app (PampGramSubscriptionAPI.swift's `responseSigningKey` constant) -- it has to match
# byte-for-byte, not be freshly minted per deploy, or every /status, /ban-status and
# /min-version response's signature check fails on every single install, and the app falls
# back to its safe default (STANDARD) even for accounts the admin actually granted PRO.
# Previously this step was missing from this script entirely (only documented as a separate
# manual step in README.md's "Подпись ответов" section), which is exactly the bug this fixes.
echo "00b78acae40c265d6b68038d5922283d153e7a18f8b150e27b84e02804b605b1" | $WRANGLER secret put RESPONSE_SIGNING_KEY

echo "== 7/7: deploying =="
DEPLOY_OUTPUT="$($WRANGLER deploy 2>&1)"
echo "$DEPLOY_OUTPUT"
WORKER_URL="$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[a-zA-Z0-9.-]+\.workers\.dev' | head -1)"

echo ""
echo "================================================================"
echo "Готово. Сохрани эти два значения — они больше нигде не хранятся:"
echo ""
echo "  Адрес сервера (для Claude — вставить в PampGramSubscriptionAPI.swift):"
echo "  ${WORKER_URL:-<не удалось определить — смотри вывод wrangler deploy выше>}"
echo ""
echo "  ADMIN_TOKEN (для приложения — PampGram → Админ-панель → Админ-токен):"
echo "  $ADMIN_TOKEN"
echo ""
echo "Пришли адрес сервера в чат Claude — токен вводить в чат НЕ нужно,"
echo "его нужно ввести только в самом приложении."
echo "================================================================"
