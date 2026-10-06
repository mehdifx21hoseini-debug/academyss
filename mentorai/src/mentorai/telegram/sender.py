"""مسیر ارسال از حساب منتور.

تنها جایی در کل سیستم است که پیام خوانده علامت زده می‌شود، و این عمدی است. طبق
ADR-009 علامت خوانده‌شدن فقط تا شناسه‌ی پیامی می‌رود که واقعاً پاسخ گرفته؛ اگر ارسال
انجام نشود، هیچ اثری در تلگرام گذاشته نمی‌شود و پیام برای منتور خوانده‌نشده می‌ماند.

کانال به‌صورت پروتکل تزریق می‌شود تا این منطق بدون شبکه و بدون حساب واقعی تست شود.
"""

from __future__ import annotations

import asyncio
import enum
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import Conversation, Message, Sender
from mentorai.telegram.safety import AccountGate, human_delay_seconds

# سقف تعداد پیام یک پاسخ. از داده‌ی واقعی: در ۱۱۶ پاسخ منتور، ۹۵٪ چهار پیام یا
# کمتر بود. سقف هست تا یک پاسخ طولانی به رگبار ده‌پیامی تبدیل نشود — که هم سقف
# ارسال حساب را می‌خورد و هم خودش غیرعادی است.
MAX_PARTS = 4
# قطعه‌ی کوتاه‌تر از این، پیام جدا نمی‌شود. «باشه.» به‌تنهایی پیام نیست.
MIN_PART_CHARS = 2


def split_messages(body: str, *, max_parts: int = MAX_PARTS) -> list[str]:
    """یک پاسخ را به همان پیام‌هایی تقسیم کن که منتور می‌فرستاد.

    مرز، **خط خالی** است. این انتخاب عمدی است و دو دلیل دارد. اول اینکه مدل خودش
    جای شکستن را انتخاب می‌کند، نه کد — شکستن مکانیکی روی تعداد کاراکتر، جمله را
    از وسط نصف می‌کند. دوم اینکه متن پیش‌نویس همان متن قابل ویرایش می‌ماند: منتور
    با گذاشتن یا برداشتن یک خط خالی، جای شکستن را خودش عوض می‌کند و لازم نیست
    نشانه‌گذاری تازه‌ای یاد بگیرد.

    پاسخی که خط خالی ندارد، یک پیام می‌شود — یعنی رفتار پیشین، دست‌نخورده.

    قطعه‌های اضافه‌تر از سقف دور ریخته نمی‌شوند؛ به قطعه‌ی آخر چسبانده می‌شوند. دور
    ریختن یعنی بریده شدن پاسخ، و آن از یک پیام بلندتر بدتر است.
    """
    parts = [p.strip() for p in re.split(r"\n\s*\n", body.strip())]
    parts = [p for p in parts if len(p) >= MIN_PART_CHARS]
    if not parts:
        return []
    if len(parts) <= max_parts:
        return parts
    head = parts[: max_parts - 1]
    return [*head, "\n\n".join(parts[max_parts - 1 :])]


class SendStatus(enum.StrEnum):
    sent = "sent"
    blocked = "blocked"
    failed = "failed"


@dataclass(frozen=True)
class SendResult:
    status: SendStatus
    reason: str | None = None
    telegram_message_id: int | None = None
    # چند قطعه در **این** تلاش رفت. برای پاسخ یک‌پیامی همیشه ۰ یا ۱ است.
    #
    # این عدد دور ریخته نمی‌شود: اگر قطعه‌ی اول برود و قطعه‌ی دوم رد شود، تلاش
    # دوباره باید از قطعه‌ی سوم شروع کند، نه از اول. بدون این، چندپیامی شدن یک راه
    # تازه برای رسیدن دو پیام یکسان به دانشجو باز می‌کرد.
    parts_sent: int = 0


class FloodWait(Exception):
    """تلگرام خواسته صبر کنیم. مقدار ثانیه در seconds است."""

    def __init__(self, seconds: int) -> None:
        super().__init__(f"flood wait {seconds}s")
        self.seconds = seconds


class OutboundChannel(Protocol):
    async def mark_read(self, chat_id: int, max_message_id: int) -> None: ...
    async def set_typing(self, chat_id: int) -> None: ...
    async def send(self, chat_id: int, body: str) -> int: ...


async def push(
    *,
    chat_id: int,
    answered_telegram_message_id: int,
    body: str,
    gate: AccountGate,
    channel: OutboundChannel,
    now: datetime | None = None,
    sleep: bool = True,
    start_at: int = 0,
) -> SendResult:
    """پاسخ را بفرست، یا اگر اجازه نیست هیچ کاری نکن.

    **هیچ نشست پایگاه داده‌ای نمی‌گیرد و هیچ چیزی نمی‌نویسد.** این عمدی است: ارسال
    به تلگرام برگشت‌ناپذیر است و نباید داخل تراکنشی باشد که ممکن است برگردد
    (`ADR-030`). ثبت نتیجه کار فراخوانی‌کننده است، در تراکنشی جدا.

    ترتیب عمدی است: اول دروازه، بعد سقف نرخ، بعد علامت خوانده‌شدن، بعد تایپ و تأخیر،
    و آخر ارسال. اگر در هر مرحله‌ی پیش از ارسال متوقف شویم، دانشجو هیچ چیزی ندیده.

    نشانگر تایپ فقط وقتی نشان داده می‌شود که واقعاً قرار است پیامی برود؛ تایپ کردن و
    بعد سکوت، بدترین حالت ممکن است.

    **پاسخ می‌تواند چند پیام باشد.** مرزش خط خالی است (`split_messages`). هر قطعه
    سهم خودش را از سقف ارسال می‌گیرد، نشانگر تایپ خودش را دارد — که در تلگرام چند
    ثانیه‌ای منقضی می‌شود — و تأخیر خودش را به تناسب طولش.

    `start_at` قطعه‌ای است که از آن شروع می‌کنیم. اگر تلاش قبلی وسط کار رد شده
    باشد، قطعه‌های رفته دوباره فرستاده نمی‌شوند؛ `parts_sent` در نتیجه می‌گوید این
    تلاش چند قطعه پیش رفت تا فراخوانی‌کننده بتواند ثبتش کند.
    """
    moment = now or datetime.now(UTC)

    blocked = gate.blocked_reason(moment)
    if blocked is not None:
        return SendResult(status=SendStatus.blocked, reason=blocked)

    parts = split_messages(body)
    remaining = parts[start_at:]
    if not remaining:
        # چیزی برای فرستادن نیست: یا متن خالی بود، یا همه‌ی قطعه‌ها قبلاً رفته‌اند.
        # هر دو حالت یعنی نباید پیامی برود.
        return SendResult(status=SendStatus.sent, parts_sent=0)

    first_message_id: int | None = None
    sent = 0
    for index, part in enumerate(remaining):
        try:
            await gate.bucket.wait() if sleep else gate.bucket.consume()
            if index == 0 and start_at == 0:
                # علامت خوانده‌شدن دقیقاً تا همین پیام، و فقط یک بار. پیام‌های
                # بعدی که هنوز جواب نگرفته‌اند خوانده‌نشده می‌مانند و منتور در
                # تلگرام خودش می‌بیندشان.
                await channel.mark_read(chat_id, answered_telegram_message_id)
            await channel.set_typing(chat_id)
            if sleep:
                await asyncio.sleep(human_delay_seconds(len(part)))
            message_id = await channel.send(chat_id, part)
        except FloodWait as exc:
            # تلگرام صریحاً رد کرده، پس **می‌دانیم** این قطعه نرفته. تنها شکستی که
            # تلاش دوباره‌اش امن است — ولی فقط از همین قطعه به بعد.
            gate.note_flood_wait(exc.seconds, now=moment)
            return SendResult(
                status=SendStatus.blocked, reason="flood_wait", parts_sent=sent
            )
        except Exception as exc:  # noqa: BLE001 - شکست ارسال نباید کارگر را بکشد
            # نتیجه نامعلوم است: شاید تلگرام پیام را گرفته و پاسخش به ما نرسیده.
            return SendResult(
                status=SendStatus.failed,
                reason=f"{type(exc).__name__}: {exc}",
                parts_sent=sent,
            )
        sent += 1
        if first_message_id is None:
            first_message_id = message_id

    return SendResult(
        status=SendStatus.sent, telegram_message_id=first_message_id, parts_sent=sent
    )


def record_sent(
    session: AsyncSession,
    *,
    conversation: Conversation,
    answered_message: Message,
    body: str,
    telegram_message_id: int,
    now: datetime | None = None,
) -> None:
    """اثر یک ارسال موفق در پایگاه داده. در تراکنشی جدا از خود ارسال."""
    session.add(
        Message(
            conversation_id=conversation.id,
            telegram_message_id=telegram_message_id,
            sender=Sender.assistant.value,
            text=body,
            sent_at=now or datetime.now(UTC),
        )
    )
    conversation.last_answered_message_id = answered_message.telegram_message_id
