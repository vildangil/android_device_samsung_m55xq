#!/usr/bin/env bash
# Adapted from kernel_builder's Telegram notifications.
# The BOT_TOKEN and CHAT_ID environment variables are only available to caller steps.
# This helper is intentionally non-fatal when Telegram is unavailable.
set -uo pipefail

if [[ -z "${BOT_TOKEN:-}" || -z "${CHAT_ID:-}" ]]; then
  echo "::notice::Telegram disabled: configure BOT_TOKEN and CHAT_ID in repository Actions secrets."
  exit 0
fi

if [[ $# -lt 1 || -z "$1" ]]; then
  echo "::warning::Telegram notification was empty; skipping."
  exit 0
fi

# Avoid exposing bot credentials, message content, or API responses to CI logs.
if ! response=$(curl --silent --fail --max-time 20 --retry 2 \
  --request POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT_ID}" \
  --data-urlencode "text=$1" \
  --data-urlencode "parse_mode=HTML" \
  --data-urlencode "disable_web_page_preview=true" 2>/dev/null); then
  echo "::warning::Telegram request failed. Build will continue."
  exit 0
fi

if ! python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") is True else 1)' <<< "$response" 2>/dev/null; then
  echo "::warning::Telegram API rejected the message. Check BOT_TOKEN, CHAT_ID and bot permissions."
fi
exit 0
