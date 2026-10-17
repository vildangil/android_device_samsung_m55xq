#!/usr/bin/env python3
"""Upload a single Telegram document with MTProto (no archive splitting).

Runs as the existing bot, not a personal Telegram account.
Requires BOT_TOKEN, TG_API_ID, TG_API_HASH, CHAT_ID/TG_RECIPENT.
Ephemeral in-memory session, no credentials persisted to runner/artifacts.
"""
import asyncio
import os
import sys
from pathlib import Path

from telethon import TelegramClient
from telethon.sessions import MemorySession


async def upload(path: Path, caption: str) -> None:
    api_id = int(os.environ["TG_API_ID"])
    api_hash = os.environ["TG_API_HASH"]
    bot_token = os.environ["BOT_TOKEN"]
    destination = os.environ.get("TG_RECIPENT") or os.environ["CHAT_ID"]
    chat = int(destination) if destination.lstrip("-").isdigit() else destination

    client = TelegramClient(
        MemorySession(), api_id, api_hash,
        request_retries=5, connection_retries=5, timeout=30,
    )
    try:
        await client.start(bot_token=bot_token)
        # Telethon resolves known chat IDs or public @usernames for the bot.
        # Supergroups without a known access hash may need a public username
        # or a previous bot interaction to be resolvable via MTProto.
        peer = await client.get_input_entity(chat)
        # Keep an Odin-compatible, unmodified TAR as ONE document.
        await client.send_file(
            peer,
            str(path),
            caption=caption.replace("%nl", "\n"),
            parse_mode="html",
            force_document=True,
        )
        print(f"Telegram MTProto: sent one file: {path.name} ({path.stat().st_size} bytes)")
    finally:
        await client.disconnect()


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: telegram-mtproto-upload.py FILE [CAPTION]", file=sys.stderr)
        return 2
    path = Path(sys.argv[1]).resolve()
    if not path.is_file():
        print(f"Telegram MTProto: missing file: {path}", file=sys.stderr)
        return 2
    if path.stat().st_size > 2_000_000_000:
        print("Telegram MTProto: document is larger than supported 2 GB", file=sys.stderr)
        return 2
    try:
        asyncio.run(upload(path, sys.argv[2] if len(sys.argv) > 2 else path.name))
    except Exception as exc:
        # No secrets, bot token or response bodies are printed here.
        print(f"Telegram MTProto upload did not complete: {type(exc).__name__}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
