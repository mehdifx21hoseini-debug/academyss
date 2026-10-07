"""ربات کنترل نباید هیچ فایلی بنویسد.

کانتینر با کاربر غیر روت اجرا می‌شود و پوشه‌ی کاری‌اش (`/app`) برای او قابل‌نوشتن نیست.
ربات کنترل با `TelegramClient("control-bot", ...)` یک فایل SQLite در همان پوشه می‌ساخت
و در اولین اجرای واقعی روی سرور با `sqlite3.OperationalError: unable to open database
file` می‌افتاد؛ چون سرویس `restart: unless-stopped` دارد، کرش تکرار می‌شد و هر بار
حساب واقعی (که پیش از ربات وصل می‌شود) هم دوباره به تلگرام وصل می‌شد.

هیچ آزمونی نگرفتش، چون آزمون‌ها `TelegramClient` را با یک کلاینت ساختگی عوض می‌کنند که
فایل نمی‌نویسد. این‌جا کلاینت واقعی ساخته می‌شود (ساختنش به شبکه وصل نمی‌شود).
"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest
from telethon.sessions import StringSession

from mentorai.config import get_settings

SRC = Path(__file__).resolve().parent.parent / "src" / "mentorai"


def test_the_control_bot_keeps_its_session_in_memory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("CONTROL_BOT_TOKEN", "123456:test-token-not-real")
    get_settings.cache_clear()
    try:
        from mentorai.control.bot import ControlBot

        bot = ControlBot(channels={}, gates={})
    finally:
        get_settings.cache_clear()

    assert list(tmp_path.iterdir()) == [], "ربات کنترل در پوشه‌ی کاری فایل ساخت"
    assert isinstance(bot._client.session, StringSession)


def test_every_telegram_client_in_the_code_uses_an_in_memory_session() -> None:
    """هر جای دیگری هم که کلاینت ساخته شود، نباید فایل نشست بسازد."""
    offenders: list[str] = []
    seen = 0
    for path in sorted(SRC.rglob("*.py")):
        for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
            if not (isinstance(node, ast.Call) and _name(node.func) == "TelegramClient"):
                continue
            seen += 1
            first = node.args[0] if node.args else None
            if not (isinstance(first, ast.Call) and _name(first.func) == "StringSession"):
                offenders.append(f"{path.relative_to(SRC)}:{node.lineno}")

    assert seen >= 3, "کلاینت‌های تلگرام پیدا نشدند؛ این آزمون دیگر چیزی نمی‌سنجد"
    assert not offenders, f"TelegramClient بدون StringSession: {offenders}"


def _name(node: ast.expr) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return ""
