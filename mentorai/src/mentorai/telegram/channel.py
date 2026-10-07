"""پیاده‌سازی واقعی کانال خروجی روی Telethon.

منطق ارسال در sender.py است و اینجا فقط ترجمه‌ی آن به فراخوانی‌های Telethon انجام
می‌شود. همین جدایی باعث می‌شود قواعد ADR-009 بدون شبکه قابل تست باشند.
"""

from __future__ import annotations

from typing import Any

from telethon.errors import FloodWaitError, MessageIdInvalidError, RPCError
from telethon.tl.functions.messages import SetTypingRequest
from telethon.tl.types import SendMessageTypingAction

from mentorai.telegram.sender import FloodWait


def _is_bad_reply_target(exc: RPCError) -> bool:
    """تلگرام می‌گوید پیامی که قرار بود نقل شود وجود ندارد.

    دو شکل دارد: خطای نوع‌دار `MessageIdInvalidError` (که `.message`اش فقط
    `BAD_REQUEST` است، نه نام خطا)، و خطای عمومی با متن `REPLY_MESSAGE_ID_INVALID`
    وقتی Telethon نوعی برایش ندارد. هر دو را باید دید.
    """
    return isinstance(exc, MessageIdInvalidError) or "MESSAGE_ID_INVALID" in str(exc.message)


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

    async def send(self, chat_id: int, body: str, reply_to: int | None = None) -> int:
        try:
            try:
                message = await self._client.send_message(chat_id, body, reply_to=reply_to)
            except RPCError as exc:
                if reply_to is None or not _is_bad_reply_target(exc):
                    raise
                # دانشجو پیامش را پاک کرده؛ نقلِ پیام ناموجود ممکن نیست. تلگرام
                # درخواست را همان لحظه رد کرده، پس چیزی نرفته و فرستادن بدون نقل
                # دوبار فرستادن نیست. پاسخ نباید به‌خاطر یک نقل از دست برود.
                message = await self._client.send_message(chat_id, body)
        except FloodWaitError as exc:
            raise FloodWait(int(exc.seconds)) from exc
        return int(message.id)
