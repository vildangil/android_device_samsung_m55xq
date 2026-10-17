#!/usr/bin/env bash
# Telegram helper modeled on vildangil/kernel_builder's msg/up commands.
# Never log credentials, split archives, or fail the TWRP build.
set -uo pipefail

mode="msg"
case "${1:-}" in
  msg) shift ;;
  up|upload) mode="up"; shift ;;
  escape)
    shift
    python3 -c 'import html,sys; print(html.escape(sys.argv[1], quote=False))' "${1:-}"
    exit $?
    ;;
esac

if [[ -z "${BOT_TOKEN:-}" ]]; then
  echo "::notice::Telegram notifications disabled: missing BOT_TOKEN."
  exit 0
fi
recipient="${TG_RECIPENT:-${CHAT_ID:-}}"
if [[ -z "$recipient" ]]; then
  echo "::notice::Telegram notifications disabled: missing CHAT_ID/TG_RECIPENT."
  exit 0
fi

check_reply() {
  local reply="$1"
  if ! python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") is True else 1)' <<< "$reply" 2>/dev/null; then
    echo "::warning::Telegram API rejected notification (check chat ID/bot permissions)."
  fi
}

send_message() {
  local msg="${1:-}" nl reply
  printf -v nl '\012'
  msg="${msg//%nl/$nl}"
  [[ -n "$msg" ]] || return 0
  if ! reply=$(curl --silent --fail --retry 2 --max-time 25 \
    -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$recipient" \
    --data-urlencode "text=$msg" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" 2>/dev/null); then
    echo "::warning::Telegram sendMessage failed (build continues)."
    return 0
  fi
  check_reply "$reply"
}

send_single_document() {
  local path="$1" caption="$2" nl reply
  printf -v nl '\012'
  caption="${caption//%nl/$nl}"
  if ! reply=$(curl --silent --fail --retry 2 --max-time 300 \
    -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
    -F "chat_id=$recipient" \
    -F "document=@$path" \
    -F "caption=$caption" \
    -F "parse_mode=HTML" 2>/dev/null); then
    echo "::warning::Telegram sendDocument failed for $(basename "$path") (build continues)."
    return 0
  fi
  check_reply "$reply"
}

upload_document() {
  local path="${1:-}" caption="${2:-}" size
  if [[ ! -f "$path" ]]; then
    echo "::warning::Telegram upload skipped: missing file $path"
    return 0
  fi
  size=$(stat -c %s "$path")
  if (( size <= 49000000 )); then
    send_single_document "$path" "$caption"
    return 0
  fi

  # The hosted Bot API has a 50 MB document limit. MTProto supports large files.
  if [[ -n "${TG_API_ID:-}" && -n "${TG_API_HASH:-}" ]]; then
    if python3 -m pip install --user --disable-pip-version-check --quiet \
      'telethon==1.45.0' >/dev/null 2>&1; then
      local uploader
      uploader="$(dirname "${BASH_SOURCE[0]}")/telegram-mtproto-upload.py"
      if python3 "$uploader" "$path" "$caption"; then
        return 0
      fi
    else
      echo "::warning::Could not install Telethon for one-file upload."
    fi
  else
    echo "::notice::Large file needs TG_API_ID and TG_API_HASH repository secrets."
  fi

  # No split files. The complete Odin TAR stays in GitHub Actions artifacts.
  local link="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
  send_message "gh ${RUN_NUM:-?}: original Odin TAR exceeds hosted Bot API 50 MB limit%nlgh ${RUN_NUM:-?}: <a href=\"$link\">download one full archive from GitHub Actions</a>%nlgh ${RUN_NUM:-?}: add TG_API_ID and TG_API_HASH secrets for direct one-file Telegram uploads"
}

case "$mode" in
  msg) send_message "${1:-}" ;;
  up) upload_document "${1:-}" "${2:-}" ;;
esac
exit 0
