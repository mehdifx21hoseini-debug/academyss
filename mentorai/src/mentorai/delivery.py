"""صندوق خروج پیام‌های خروجی.

**مسئله.** ارسال به تلگرام برگشت‌ناپذیر است. تا پیش از این داخل همان تراکنشی
انجام می‌شد که پاسخ و کار صف را ثبت می‌کرد؛ اگر تثبیت آن تراکنش پس از ارسال موفق
شکست می‌خورد، همه چیز برمی‌گشت: دانشجو پیام را گرفته بود، پایگاه داده هیچ ردی
نداشت، و کار دو دقیقه بعد دوباره اجرا می‌شد و همان پاسخ را **دوباره** می‌فرستاد.

**راه‌حل.** تصمیم در تراکنش اول تثبیت می‌شود و فقط یک سطر «در انتظار» می‌سازد.
ارسال بیرون از هر تراکنشی انجام می‌شود. نتیجه در تراکنش دوم ثبت می‌شود.

سه چیز اینجا عمدی است:

۱. **`sending` یک حالت پایدار است، نه لحظه‌ای.** پیش از تماس با تلگرام تثبیت
   می‌شود. اگر فرایند وسط ارسال بمیرد، سطر در همین حالت می‌ماند و هیچ‌وقت دوباره
   فرستاده نمی‌شود — چون نمی‌دانیم تلگرام آن را گرفت یا نه، و حدس زدن یعنی
   احتمال دو پیام برای دانشجو.

۲. **فقط شکستی دوباره تلاش می‌شود که بدانیم ارسال نشده.** `FloodWait` یعنی
   تلگرام صریحاً رد کرده، پس امن است. هر شکست دیگری «نامعلوم» است و به
   `abandoned` می‌رود، نه به صف دوباره.

۳. **یکتایی روی `answered_message_id` در خود پایگاه داده است.** دو تلاش هم‌زمان
   برای ساختن تحویل، دومی را با شکست درج مواجه می‌کند — همان روشی که تشخیص پیام
   تکراری ورودی کار می‌کند.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import DeliveryStatus

log = structlog.get_logger(__name__)

# سطری که این‌قدر در حالت `sending` مانده، فرایندش مرده است.
STALE_AFTER = timedelta(minutes=10)
RETRY_AFTER = timedelta(minutes=2)


@dataclass(frozen=True)
class Claimed:
    """تحویلی که برای ارسال برداشته شده."""

    id: int
    conversation_id: int
    answered_message_id: int
    body: str
    attempts: int
    max_attempts: int
    telegram_chat_id: int
    answered_telegram_message_id: int
    account_slug: str


async def enqueue(
    session: AsyncSession,
    *,
    conversation_id: int,
    answered_message_id: int,
    body: str,
) -> int | None:
    """یک تحویل در انتظار بساز. `None` یعنی از قبل وجود داشت.

    بی‌همتاسازی با قید یکتایی انجام می‌شود، نه با «اول بخوان بعد بنویس»: آن روش
    بین دو کارگر هم‌زمان مسابقه دارد و هر دو نتیجه می‌گیرند که تحویلی نیست.
    """
    row = await session.execute(
        text(
            """
            insert into deliveries (conversation_id, answered_message_id, body)
            values (:conversation_id, :answered_message_id, :body)
            on conflict (answered_message_id) do nothing
            returning id
            """
        ),
        {
            "conversation_id": conversation_id,
            "answered_message_id": answered_message_id,
            "body": body,
        },
    )
    record = row.first()
    return int(record.id) if record is not None else None


async def claim_next(session: AsyncSession) -> Claimed | None:
    """یک تحویل در انتظار را بردار و به `sending` ببر.

    این تغییر حالت باید **پیش از** تماس با تلگرام تثبیت شود. فراخوانی‌کننده باید
    تراکنش را ببندد و بعد بفرستد.
    """
    row = await session.execute(
        text(
            """
            update deliveries d
            set status = 'sending',
                attempts = d.attempts + 1,
                claimed_at = now()
            where d.id = (
                select id from deliveries
                where status = 'pending' and run_after <= now()
                order by run_after, id
                limit 1
                for update skip locked
            )
            returning d.id, d.conversation_id, d.answered_message_id, d.body,
                      d.attempts, d.max_attempts
            """
        )
    )
    record = row.first()
    if record is None:
        return None
    return await _with_context(session, record)


async def _with_context(session: AsyncSession, record: object) -> Claimed | None:
    """شناسه‌های تلگرامی لازم برای ارسال را کنار سطر تحویل بگذار."""
    context = (
        await session.execute(
            text(
                """
                select c.telegram_chat_id, m.telegram_message_id, a.slug
                from conversations c
                join messages m on m.id = :answered_message_id
                join mentor_accounts a on a.id = c.account_id
                where c.id = :conversation_id
                """
            ),
            {
                "answered_message_id": record.answered_message_id,  # type: ignore[attr-defined]
                "conversation_id": record.conversation_id,  # type: ignore[attr-defined]
            },
        )
    ).first()
    if context is None:
        # مکالمه یا پیام دیگر نیست. تحویل بی‌معنی است و نباید در صف بماند.
        await abandon(session, record.id, "مکالمه یا پیام پاسخ‌شده پیدا نشد")  # type: ignore[attr-defined]
        return None

    return Claimed(
        id=record.id,  # type: ignore[attr-defined]
        conversation_id=record.conversation_id,  # type: ignore[attr-defined]
        answered_message_id=record.answered_message_id,  # type: ignore[attr-defined]
        body=record.body,  # type: ignore[attr-defined]
        attempts=record.attempts,  # type: ignore[attr-defined]
        max_attempts=record.max_attempts,  # type: ignore[attr-defined]
        telegram_chat_id=context.telegram_chat_id,
        answered_telegram_message_id=context.telegram_message_id,
        account_slug=context.slug,
    )


async def claim(session: AsyncSession, delivery_id: int) -> Claimed | None:
    """همان `claim_next` ولی برای یک تحویل مشخص.

    مسیر تأیید پیش‌نویس از این استفاده می‌کند تا منتور بلافاصله نتیجه‌ی واقعی را
    ببیند، نه «در صف گذاشته شد». اگر کارگر زودتر برش داشته باشد، اینجا `None`
    برمی‌گردد و فراخوانی‌کننده وضعیت نهایی را می‌خواند.
    """
    row = await session.execute(
        text(
            """
            update deliveries d
            set status = 'sending', attempts = d.attempts + 1, claimed_at = now()
            where d.id = (
                select id from deliveries
                where id = :id and status = 'pending'
                for update skip locked
            )
            returning d.id, d.conversation_id, d.answered_message_id, d.body,
                      d.attempts, d.max_attempts
            """
        ),
        {"id": delivery_id},
    )
    record = row.first()
    if record is None:
        return None
    return await _with_context(session, record)


async def status_of(session: AsyncSession, delivery_id: int) -> str | None:
    row = await session.execute(
        text("select status from deliveries where id = :id"), {"id": delivery_id}
    )
    record = row.first()
    return str(record.status) if record is not None else None


async def mark_sent(
    session: AsyncSession, delivery_id: int, *, telegram_message_id: int
) -> None:
    await session.execute(
        text(
            """
            update deliveries
            set status = 'sent', telegram_message_id = :tg, sent_at = now(), last_error = null
            where id = :id
            """
        ),
        {"id": delivery_id, "tg": telegram_message_id},
    )


async def retry_later(
    session: AsyncSession, delivery_id: int, *, error: str, retry_in: timedelta = RETRY_AFTER
) -> None:
    """فقط برای شکستی که **می‌دانیم** ارسال نشده.

    اگر تلاش‌ها تمام شده باشد به صف مرده می‌رود، نه اینکه بی‌صدا ناپدید شود.
    """
    await session.execute(
        text(
            """
            update deliveries
            set status = case when attempts >= max_attempts then 'failed' else 'pending' end,
                last_error = :error,
                run_after = now() + cast(:retry_in as interval),
                claimed_at = null
            where id = :id
            """
        ),
        {"id": delivery_id, "error": error[:4000], "retry_in": retry_in},
    )


async def abandon(session: AsyncSession, delivery_id: int, error: str) -> None:
    """نتیجه نامعلوم است. هرگز دوباره فرستاده نمی‌شود.

    این محافظه‌کارانه‌ترین حالت ممکن است و عمدی: شاید دانشجو پیام را گرفته باشد.
    فرستادن دوباره یعنی دو پیام یکسان، و آن از سکوت بدتر است. مکالمه به منتور
    سپرده می‌شود تا آدمی نگاه کند.
    """
    await session.execute(
        text(
            "update deliveries set status = 'abandoned', last_error = :error, claimed_at = null "
            "where id = :id"
        ),
        {"id": delivery_id, "error": error[:4000]},
    )


async def abandon_stale(
    session: AsyncSession, *, older_than: timedelta = STALE_AFTER
) -> list[int]:
    """سطرهایی که کارگرشان وسط ارسال مرده است.

    عمداً به `pending` برنمی‌گردند. نمی‌دانیم تلگرام پیام را گرفت یا نه، و تنها
    پاسخ امن این است که دیگر نفرستیم و به آدم بسپاریم.
    """
    result = await session.execute(
        text(
            """
            update deliveries
            set status = 'abandoned',
                last_error = 'فرایند وسط ارسال متوقف شد؛ نتیجه نامعلوم است',
                claimed_at = null
            where status = 'sending' and claimed_at < now() - cast(:older_than as interval)
            returning id
            """
        ),
        {"older_than": older_than},
    )
    ids = [int(r.id) for r in result.fetchall()]
    if ids:
        log.error("deliveries_abandoned", count=len(ids), delivery_ids=ids)
    return ids


async def counts_by_status(session: AsyncSession) -> dict[str, int]:
    """برای مشاهده‌پذیری. صف مرده باید دیده شود، نه اینکه بی‌صدا پر شود."""
    rows = await session.execute(
        text("select status, count(*) as n from deliveries group by status")
    )
    return {r.status: int(r.n) for r in rows.all()}


def utcnow() -> datetime:
    return datetime.now(UTC)


__all__ = [
    "Claimed",
    "claim",
    "status_of",
    "DeliveryStatus",
    "abandon",
    "abandon_stale",
    "claim_next",
    "counts_by_status",
    "enqueue",
    "mark_sent",
    "retry_later",
]
