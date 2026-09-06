"""مسیر ارسال از حساب منتور.

تنها جایی در کل سیستم است که پیام خوانده علامت زده می‌شود، و این عمدی است. طبق
ADR-009 علامت خوانده‌شدن فقط تا شناسه‌ی پیامی می‌رود که واقعاً پاسخ گرفته؛ اگر ارسال
انجام نشود، هیچ اثری در تلگرام گذاشته نمی‌شود و پیام برای منتور خوانده‌نشده می‌ماند.

کانال به‌صورت پروتکل تزریق می‌شود تا این منطق بدون شبکه و بدون حساب واقعی تست شود.
"""

from __future__ import annotations

import asyncio
import enum
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import Conversation, MentorAccount, Message, Sender
from mentorai.telegram.safety import AccountGate, human_delay_seconds


class SendStatus(enum.StrEnum):
    sent = "sent"
    blocked = "blocked"
    failed = "failed"


@dataclass(frozen=True)
class SendResult:
    status: SendStatus
    reason: str | None = None
    telegram_message_id: int | None = None


class FloodWait(Exception):
    """تلگرام خواسته صبر کنیم. مقدار ثانیه در seconds است."""

    def __init__(self, seconds: int) -> None:
        super().__init__(f"flood wait {seconds}s")
        self.seconds = seconds


class OutboundChannel(Protocol):
    async def mark_read(self, chat_id: int, max_message_id: int) -> None: ...
    async def set_typing(self, chat_id: int) -> None: ...
    async def send(self, chat_id: int, body: str) -> int: ...


async def deliver_answer(
    session: AsyncSession,
    *,
    account: MentorAccount,
    conversation: Conversation,
    answered_message: Message,
    body: str,
    gate: AccountGate,
    channel: OutboundChannel,
    now: datetime | None = None,
    sleep: bool = True,
) -> SendResult:
    """پاسخ را بفرست، یا اگر اجازه نیست هیچ کاری نکن.

    ترتیب عمدی است: اول دروازه، بعد سقف نرخ، بعد علامت خوانده‌شدن، بعد تایپ و تأخیر،
    و آخر ارسال. اگر در هر مرحله‌ی پیش از ارسال متوقف شویم، دانشجو هیچ چیزی ندیده.

    نشانگر تایپ فقط وقتی نشان داده می‌شود که واقعاً قرار است پیامی برود؛ تایپ کردن و
    بعد سکوت، بدترین حالت ممکن است.
    """
    moment = now or datetime.now(UTC)

    blocked = gate.blocked_reason(moment)
    if blocked is not None:
        return SendResult(status=SendStatus.blocked, reason=blocked)

    await gate.bucket.wait() if sleep else gate.bucket.consume()

    try:
        # علامت خوانده‌شدن دقیقاً تا همین پیام. پیام‌های بعدی که هنوز جواب نگرفته‌اند
        # خوانده‌نشده می‌مانند و منتور در تلگرام خودش می‌بیندشان.
        await channel.mark_read(conversation.telegram_chat_id, answered_message.telegram_message_id)
        await channel.set_typing(conversation.telegram_chat_id)
        if sleep:
            await asyncio.sleep(human_delay_seconds(len(body)))
        telegram_message_id = await channel.send(conversation.telegram_chat_id, body)
    except FloodWait as exc:
        gate.note_flood_wait(exc.seconds, now=moment)
        return SendResult(status=SendStatus.blocked, reason="flood_wait")
    except Exception as exc:  # noqa: BLE001 - شکست ارسال نباید کارگر را بکشد
        return SendResult(status=SendStatus.failed, reason=f"{type(exc).__name__}: {exc}")

    session.add(
        Message(
            conversation_id=conversation.id,
            telegram_message_id=telegram_message_id,
            sender=Sender.assistant.value,
            text=body,
            sent_at=moment,
        )
    )
    conversation.last_answered_message_id = answered_message.telegram_message_id
    return SendResult(status=SendStatus.sent, telegram_message_id=telegram_message_id)
