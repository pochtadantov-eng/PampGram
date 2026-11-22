#!/usr/bin/env bash
# Adds the Telegram bot to the ALREADY DEPLOYED PampGram worker.
#
# Unlike deploy.sh this never creates a new worker, never touches ADMIN_TOKEN or
# RESPONSE_SIGNING_KEY, and reuses the existing KV namespace, so the app keeps working
# unchanged. It:
#   1. finds your worker's KV namespace (the one titled "...SUBS"),
#   2. writes a local wrangler.bot.toml (git-ignored) for the worker name below,
#   3. stores BOT_TOKEN and a fresh webhook secret as Cloudflare secrets,
#   4. deploys the new code,
#   5. points the bot's Telegram webhook at the worker.
#
# Before running: create the bot with @BotFather (/newbot) and keep its token.
#
# Usage:
#   cd server/pampgram-subs-worker
#   BOT_TOKEN='123456:ABC...' bash setup-bot.sh
#
# Optional environment:
#   WORKER_NAME   name of the deployed worker            (default: pampgram)
#   WORKER_URL    its public address                     (default: https://pampgram.pochtadantov.workers.dev)
#   ADMIN_TG_IDS  Telegram ids allowed in /admin, comma-separated (default: 8557314630)
#   KV_ID         KV namespace id, if auto-detection can't pick one
#   COMPAT_DATE   Workers compatibility_date to deploy with (default: 2024-11-01)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

WORKER_NAME="${WORKER_NAME:-pampgram}"
WORKER_URL="${WORKER_URL:-https://pampgram.pochtadantov.workers.dev}"
ADMIN_TG_IDS="${ADMIN_TG_IDS:-8557314630}"
COMPAT_DATE="${COMPAT_DATE:-2024-11-01}"

if [ -z "${BOT_TOKEN:-}" ]; then
	read -rsp "Токен бота от @BotFather: " BOT_TOKEN
	echo
fi
if ! [[ "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]{20,}$ ]]; then
	echo "Токен выглядит неправильно (ожидается вид 123456:ABC...)." >&2
	exit 1
fi
command -v npm >/dev/null 2>&1 || { echo "Нужен Node.js (npm): https://nodejs.org" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "Нужен Node.js: https://nodejs.org" >&2; exit 1; }
WRANGLER="npx --yes wrangler"

echo "== 1/6: проверяю токен бота =="
ME="$(curl -fsS "https://api.telegram.org/bot${BOT_TOKEN}/getMe")" || { echo "Telegram не принял токен." >&2; exit 1; }
BOT_USERNAME="$(printf '%s' "$ME" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>console.log(JSON.parse(d).result.username))')"
echo "Бот: @${BOT_USERNAME}"

echo "== 2/6: вход в Cloudflare =="
$WRANGLER whoami >/dev/null 2>&1 || $WRANGLER login

echo "== 3/6: ищу KV-хранилище воркера =="
if [ -z "${KV_ID:-}" ]; then
	KV_JSON="$($WRANGLER kv namespace list 2>/dev/null)"
	KV_ID="$(printf '%s' "$KV_JSON" | node -e '
let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
  const list=JSON.parse(d).filter(n=>/SUBS$/i.test(n.title));
  if(list.length===1){console.log(list[0].id);}
  else{console.error(list.length===0?"NONE":"MANY:"+list.map(n=>n.title+"="+n.id).join(", "));process.exit(2);}
})')" || {
		echo "Не удалось однозначно выбрать KV-хранилище. Запусти с KV_ID=<id> (видно в Cloudflare → Workers KV)." >&2
		exit 1
	}
fi
echo "KV: ${KV_ID}"

cat > wrangler.bot.toml <<TOML
name = "${WORKER_NAME}"
main = "src/index.js"
compatibility_date = "${COMPAT_DATE}"

kv_namespaces = [
  { binding = "SUBS", id = "${KV_ID}" }
]

[vars]
ADMIN_TG_IDS = "${ADMIN_TG_IDS}"

[triggers]
crons = ["*/10 * * * *"]
TOML

echo "== 4/6: сохраняю секреты =="
WEBHOOK_SECRET="$(openssl rand -hex 24)"
printf '%s' "$BOT_TOKEN" | $WRANGLER secret put BOT_TOKEN -c wrangler.bot.toml
printf '%s' "$WEBHOOK_SECRET" | $WRANGLER secret put WEBHOOK_SECRET -c wrangler.bot.toml

echo "== 5/6: деплой =="
$WRANGLER deploy -c wrangler.bot.toml

echo "== 6/6: подключаю вебхук Telegram =="
curl -fsS "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook" \
	--data-urlencode "url=${WORKER_URL}/tg" \
	--data-urlencode "secret_token=${WEBHOOK_SECRET}" \
	--data-urlencode 'allowed_updates=["message","callback_query","pre_checkout_query","my_chat_member"]' \
	--data-urlencode "drop_pending_updates=true"
echo
curl -fsS "https://api.telegram.org/bot${BOT_TOKEN}/setMyCommands" \
	--data-urlencode 'commands=[{"command":"start","description":"Меню"},{"command":"privacy","description":"Какие данные собираются"}]' >/dev/null

echo ""
echo "================================================================"
echo "Готово. Бот: https://t.me/${BOT_USERNAME}"
echo "Открой его с аккаунта, чей id указан в ADMIN_TG_IDS (${ADMIN_TG_IDS}), и отправь /admin."
echo "Дальше в админ-панели: «Тарифы» (поставь свои цены) и «Выдача» (пришли боту"
echo "IPA, сертификат и ссылки на установщик)."
echo "================================================================"
