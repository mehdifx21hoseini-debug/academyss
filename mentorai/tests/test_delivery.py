"""صندوق خروج.

شکستی که این فایل می‌بندد یک چیز است و بزرگ است: **پیام دو بار به دانشجو نرود**.

پیش از ADR-030 ارسال به تلگرام داخل همان تراکنشی بود که پاسخ و کار صف را ثبت
می‌کرد. اگر تثبیت آن تراکنش پس از ارسال موفق شکست می‌خورد، همه چیز برمی‌گشت —
دانشجو پیام را گرفته بود، پایگاه داده هیچ ردی نداشت، و دو دقیقه بعد همان پاسخ
دوباره فرستاده می‌شد.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import delivery
from mentorai.db.models import MentorAccount, Message, Sender
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound

NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)


@pytest.fixture
async def answered(session: AsyncSession, account: MentorAccount) -> Message:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=700,
        message_id=42,
        sender_user_id=700,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text="سؤال",
        media_type=None,
        reply_to_message_id=None,
        sent_at=NOON,
        is_private=True,
        is_outgoing=False,
    )
    result = await record_inbound(session, account, inbound, sender=Sender.student)
    await session.commit()
    assert result.message_id is not None
    return await session.get_one(Message, result.message_id)


async def _enqueue(session: AsyncSession, answered: Message, body: str = "پاسخ") -> int | None:
    return await delivery.enqueue(
        session,
        conversation_id=answered.conversation_id,
        answered_message_id=answered.id,
        body=body,
    )


async def _status(session: AsyncSession, delivery_id: int) -> str | None:
    return await delivery.status_of(session, delivery_id)


# ---------------------------------------------------------------------------
# تضمین اصلی: هیچ ارسال دوباره‌ای
# ---------------------------------------------------------------------------


async def test_a_delivery_left_mid_send_is_never_picked_up_again(
    session: AsyncSession, answered: Message
) -> None:
    """مهم‌ترین تست این پروژه.

    سناریو: تحویل برداشته شد و به `sending` رفت، بعد فرایند وسط ارسال مرد. ما
    نمی‌دانیم تلگرام پیام را گرفت یا نه.

    اگر `claim_next` دوباره برش دارد، دانشجو ممکن است دو پیام یکسان بگیرد. حالت
    `sending` عمداً پایدار است تا این ممکن نباشد.
    """
    delivery_id = await _enqueue(session, answered)
    assert delivery_id is not None
    claimed = await delivery.claim_next(session)
    await session.commit()
    assert claimed is not None and claimed.id == delivery_id

    # فرایند اینجا مرد: هیچ نتیجه‌ای ثبت نشد.
    again = await delivery.claim_next(session)
    assert again is None, "تحویلِ نیمه‌تمام دوباره برداشته شد — احتمال ارسال دوم"
    assert await _status(session, delivery_id) == "sending"


async def test_a_stale_send_is_abandoned_not_retried(
    session: AsyncSession, answered: Message
) -> None:
    """سطر جامانده رها می‌شود، نه اینکه به صف برگردد.

    برگرداندنش به `pending` راحت‌تر بود و دقیقاً همان اشتباهی است که این طراحی
    برای جلوگیری از آن ساخته شده: نتیجه نامعلوم است، پس تنها کار امن نفرستادن
    دوباره و سپردن به آدم است.
    """
    delivery_id = await _enqueue(session, answered)
    assert delivery_id is not None
    await delivery.claim_next(session)
    await session.execute(
        text("update deliveries set claimed_at = now() - interval '1 hour' where id = :id"),
        {"id": delivery_id},
    )
    await session.commit()

    abandoned = await delivery.abandon_stale(session, older_than=timedelta(minutes=10))
    await session.commit()

    assert abandoned == [delivery_id]
    assert await _status(session, delivery_id) == "abandoned"
    assert await delivery.claim_next(session) is None, "سطر رهاشده دوباره برداشته شد"


async def test_two_answers_for_the_same_message_cannot_both_be_queued(
    session: AsyncSession, answered: Message
) -> None:
    """بی‌همتاسازی در خود پایگاه داده است، نه در کد.

    اگر کاری دو بار اجرا شود — که صف صریحاً تلاش دوباره دارد — نباید دو پیام
    برای یک سؤال ساخته شود.
    """
    first = await _enqueue(session, answered, "پاسخ اول")
    second = await _enqueue(session, answered, "پاسخ دوم")
    await session.commit()

    assert first is not None
    assert second is None, "برای یک پیام دو تحویل ساخته شد"
    total = (await session.execute(text("select count(*) from deliveries"))).scalar_one()
    assert total == 1


# ---------------------------------------------------------------------------
# جهت شکست
# ---------------------------------------------------------------------------


async def test_a_known_rejection_goes_back_to_the_queue(
    session: AsyncSession, answered: Message
) -> None:
    """`FloodWait` و ساعات سکوت یعنی **می‌دانیم** چیزی نرفته. تلاش دوباره امن است."""
    delivery_id = await _enqueue(session, answered)
    assert delivery_id is not None
    await delivery.claim_next(session)
    await delivery.retry_later(session, delivery_id, error="flood_wait", retry_in=timedelta(0))
    await session.commit()

    assert await _status(session, delivery_id) == "pending"
    assert (await delivery.claim_next(session)) is not None


async def test_an_unknown_failure_is_abandoned_not_retried(
    session: AsyncSession, answered: Message
) -> None:
    """خطای شبکه یعنی شاید پیام رفته باشد. تلاش دوباره یعنی احتمال دو پیام."""
    delivery_id = await _enqueue(session, answered)
    assert delivery_id is not None
    await delivery.claim_next(session)
    await delivery.abandon(session, delivery_id, "TimeoutError")
    await session.commit()

    assert await _status(session, delivery_id) == "abandoned"
    assert await delivery.claim_next(session) is None


async def test_exhausted_retries_land_in_a_dead_state_not_silence(
    session: AsyncSession, answered: Message
) -> None:
    """کاری که تلاش‌هایش تمام شده باید دیده شود، نه اینکه بی‌صدا ناپدید شود."""
    delivery_id = await _enqueue(session, answered)
    assert delivery_id is not None
    await session.execute(
        text("update deliveries set attempts = max_attempts where id = :id"), {"id": delivery_id}
    )
    await delivery.retry_later(session, delivery_id, error="flood_wait", retry_in=timedelta(0))
    await session.commit()

    assert await _status(session, delivery_id) == "failed"
    assert await delivery.claim_next(session) is None


# ---------------------------------------------------------------------------
# مرز تراکنش
# ---------------------------------------------------------------------------


async def test_a_rolled_back_decision_leaves_nothing_to_send(
    session: AsyncSession, answered: Message
) -> None:
    """اگر تراکنش تصمیم برگردد، تحویلی هم نمی‌ماند.

    این همان نیمه‌ی دیگر تضمین است: نه پیامی بدون رد در پایگاه داده می‌رود، و نه
    ردی بدون پیام می‌ماند.
    """
    await _enqueue(session, answered)
    await session.rollback()

    total = (await session.execute(text("select count(*) from deliveries"))).scalar_one()
    assert total == 0


async def test_counts_by_status_sees_the_dead_queue(
    session: AsyncSession, answered: Message
) -> None:
    """صف مرده باید قابل دیدن باشد، وگرنه بی‌صدا پر می‌شود."""
    delivery_id = await _enqueue(session, answered)
    assert delivery_id is not None
    await delivery.claim_next(session)
    await delivery.abandon(session, delivery_id, "TimeoutError")
    await session.commit()

    assert (await delivery.counts_by_status(session)).get("abandoned") == 1
