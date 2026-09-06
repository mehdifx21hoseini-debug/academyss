"""پیاده‌سازی واقعی کانال خروجی روی Telethon.

منطق ارسال در sender.py است و اینجا فقط ترجمه‌ی آن به فراخوانی‌های Telethon انجام
می‌شود. همین جدایی باعث می‌شود قواعد ADR-009 بدون شبکه قابل تست باشند.
"""

from __future__ import annotations

from typing import Any

from telethon.errors import FloodWaitError
from telethon.tl.functions.messages import SetTypingRequest
from telethon.tl.types import SendMessageTypingAction

from mentorai.telegram.sender import FloodWait


class TelethonChannel:
    def __init__(self, client: Any) -> None:
        self._client = client

    async def mark_read(self, chat_id: int, max_message_id: int) -> None:
        """تا همین شناسه خوانده علامت بخورد، نه جلوتر.

        اگر دانشجو سه پیام فرستاده و فقط دوتای اول جواب گرفته‌اند، سومی باید
        خوانده‌نشده بماند تا منتور در تلگرام خودش ببیندش (ADR-009).
        """
        try:
            await self._client.send_read_acknowledge(chat_id, max_id=max_message_id)
        except FloodWaitError as exc:
            raise FloodWait(int(exc.seconds)) from exc

    async def set_typing(self, chat_id: int) -> None:
        try:
            await self._client(SetTypingRequest(peer=chat_id, action=SendMessageTypingAction()))
        except FloodWaitError as exc:
            raise FloodWait(int(exc.seconds)) from exc

    async def send(self, chat_id: int, body: str) -> int:
        try:
            message = await self._client.send_message(chat_id, body)
        except FloodWaitError as exc:
            raise FloodWait(int(exc.seconds)) from exc
        return int(message.id)
