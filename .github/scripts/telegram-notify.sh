#!/usr/bin/env bash
# Telegram helper compatible with kernel_builder's "msg"/"up" interface.
# BOT_TOKEN and CHAT_ID must come from Actions secrets, never from source.
# TG_RECIPENT can override CHAT_ID for a single manual workflow run.
# Telegram errors are reported as CI warnings, without failing the build.
set -uo pipefail

mode="msg"
case "${1:-}" in
  msg) mode="msg"; shift ;;
  up|upload) mode="up"; shift ;;
  escape) shift; python3 -c 'import html,sys; print(html.escape(sys.argv[1], quote=False))' "${1:-}"; exit $? ;;
esac

if [[ -z "${BOT_TOKEN:-}" ]]; then
  echo "::notice::Telegram disabled: missing BOT_TOKEN Actions secret."
  exit 0
fi

recipient="${TG_RECIPENT:-${CHAT_ID:-}}"
if [[ -z "$recipient" ]]; then
  echo "::notice::Telegram disabled: configure CHAT_ID secret or TG_RECIPENT input."
  exit 0
fi

check_reply() {
  local reply="$1"
  if ! python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") is True else 1)' \
       <<< "$reply" 2>/dev/null; then
    echo "::warning::Telegram API rejected a notification; check chat ID and bot permissions."
  fi
}

send_message() {
  local msg="${1:-}"
  [[ -n "$msg" ]] || return 0
  local reply
  if ! reply=$(curl --silent --fail --retry 2 --max-time 25 \
    -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$recipient" \
    --data-urlencode "text=$msg" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" 2>/dev/null); then
    echo "::warning::Could not send Telegram status (build continues)."
    return 0
  fi
  check_reply "$reply"
}

send_single_document() {
  local path="$1" caption="$2"
  local reply
  if ! reply=$(curl --silent --fail --retry 2 --retry-delay 2 --max-time 300 \
    -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
    -F "chat_id=$recipient" \
    -F "document=@$path" \
    -F "caption=$caption" \
    -F "parse_mode=HTML" 2>/dev/null); then
    echo "::warning::Could not upload $(basename "$path") to Telegram (build continues)."
    return 0
  fi
  check_reply "$reply"
}

upload_document() {
  local path="${1:-}" caption="${2:-}"
  if [[ ! -f "$path" ]]; then
    echo "::warning::Telegram upload skipped: file not found: $path"
    return 0
  fi
  local size parts_dir part total i
  size=$(stat -c %s "$path")
  if (( size <= 49000000 )); then
    send_single_document "$path" "$caption"
    return 0
  fi

  # Telegram's hosted Bot API limits document uploads; split oversized files.
  # Download every part and reassemble with: cat filename.part-* > filename
  parts_dir=$(mktemp -d)
  if ! split -b 45000000 -d -a 3 "$path" "$parts_dir/$(basename "$path").part-"; then
    echo "::warning::Could not split Telegram upload."
    rm -rf "$parts_dir"
    return 0
  fi
  local -a parts=( "$parts_dir"/* )
  total="${#parts[@]}"
  i=0
  for part in "${parts[@]}"; do
    i=$((i+1))
    send_single_document "$part" "$caption (part $i/$total)"
  done
  rm -rf "$parts_dir"
  send_message "<b>Split upload:</b> combine the parts in filename order with <code>cat $(basename "$path").part-* &gt; $(basename "$path")</code>. Verify SHA256SUMS."
}

case "$mode" in
  msg) send_message "${1:-}" ;;
  up) upload_document "${1:-}" "${2:-}" ;;
esac
exit 0
