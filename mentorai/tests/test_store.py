"""تشخیص پیام تکراری و هم‌زمانی.

تلگرام تحویل «حداقل یک بار» است. این تست‌ها همان چیزی را می‌سنجند که در سیستم قبلی
شکسته بود.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import MentorAccount, Sender
from mentorai.db.session import get_sessionmaker
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import excluded_peer_ids, record_inbound


def _msg(message_id: int = 1, chat_id: int = 100, text_: str | None = "سلام"):  # type: ignore[no-untyped-def]
    return build_inbound(
        account_slug="mentor-a",
        chat_id=chat_id,
        message_id=message_id,
        sender_user_id=chat_id,
        username="student",
        first_name="سبحان",
        last_name=None,
        raw_text=text_,
        media_type=None,
        reply_to_message_id=None,
        sent_at=datetime(2026, 9, 2, 12, 0, tzinfo=UTC),
        is_private=True,
        is_outgoing=False,
    )


async def _count(session: AsyncSession, table: str) -> int:
    return int((await session.execute(text(f"select count(*) from {table}"))).scalar_one())


async def test_first_delivery_is_stored(session: AsyncSession, account: MentorAccount) -> None:
    result = await record_inbound(session, account, _msg(), sender=Sender.student)
    await session.commit()

    assert result.is_duplicate is False
    assert result.message_id is not None
    assert await _count(session, "messages") == 1


async def test_repeated_delivery_stores_exactly_one_message(
    session: AsyncSession, account: MentorAccount
) -> None:
    first = await record_inbound(session, account, _msg(), sender=Sender.student)
    await session.commit()
    second = await record_inbound(session, account, _msg(), sender=Sender.student)
    await session.commit()

    assert first.is_duplicate is False
    assert second.is_duplicate is True
    assert await _count(session, "messages") == 1


async def test_duplicate_is_recorded_not_silently_dropped(
    session: AsyncSession, account: MentorAccount
) -> None:
    """بدون این ثبت، نرخ تکرار هرگز قابل اندازه‌گیری نیست."""
    await record_inbound(session, account, _msg(), sender=Sender.student)
    await session.commit()
    await record_inbound(session, account, _msg(), sender=Sender.student)
    await session.commit()

    assert await _count(session, "duplicate_deliveries") == 1


async def test_out_of_order_redelivery_is_still_caught(
    session: AsyncSession, account: MentorAccount
) -> None:
    """پیام ۱، بعد ۲، بعد دوباره ۱.

    روش «فقط آخرین شناسه را نگه دار» دقیقاً اینجا شکست می‌خورد و پیام اول را دوباره
    پردازش می‌کند.
    """
    await record_inbound(session, account, _msg(message_id=1), sender=Sender.student)
    await record_inbound(session, account, _msg(message_id=2), sender=Sender.student)
    await session.commit()

    again = await record_inbound(session, account, _msg(message_id=1), sender=Sender.student)
    await session.commit()

    assert again.is_duplicate is True
    assert await _count(session, "messages") == 2


async def test_concurrent_delivery_of_the_same_message_stores_one(
    account: MentorAccount,
) -> None:
    """دو کارگر هم‌زمان، یک پیام.

    این حالتی است که «اول بخوان بعد بنویس» را می‌شکند: هر دو مقدار قدیمی را می‌بینند.
    قید یکتایی پایگاه داده چنین پنجره‌ای ندارد.
    """
    maker = get_sessionmaker()

    async def worker() -> bool:
        async with maker() as s:
            acc = await s.get_one(MentorAccount, account.id)
            try:
                result = await record_inbound(s, acc, _msg(message_id=7), sender=Sender.student)
                await s.commit()
            except Exception:
                await s.rollback()
                return True
            return result.is_duplicate

    outcomes = await asyncio.gather(worker(), worker(), worker())

    async with maker() as s:
        assert await _count(s, "messages") == 1
    assert outcomes.count(False) == 1, "دقیقاً یکی باید موفق شود و بقیه تکراری باشند"


async def test_same_student_on_two_accounts_gets_two_conversations(
    session: AsyncSession, account: MentorAccount
) -> None:
    """طبق ADR-007 منتور از روی حساب تعیین می‌شود، پس هر حساب مکالمه‌ی خودش را دارد."""
    other = MentorAccount(
        slug="mentor-b",
        mentor_name="منتور ب",
        phone="+989000000002",
        device_model="Desktop",
        system_version="Linux",
        app_version="1.0",
    )
    session.add(other)
    await session.flush()

    a = await record_inbound(session, account, _msg(message_id=1), sender=Sender.student)
    b = await record_inbound(session, other, _msg(message_id=1), sender=Sender.student)
    await session.commit()

    assert a.conversation_id != b.conversation_id
    assert await _count(session, "students") == 1, "یک نفر، یک دانشجو"
    assert await _count(session, "conversations") == 2


async def test_mentor_reply_is_stored_with_mentor_sender(
    session: AsyncSession, account: MentorAccount
) -> None:
    await record_inbound(session, account, _msg(message_id=1), sender=Sender.student)
    await record_inbound(session, account, _msg(message_id=2), sender=Sender.mentor)
    await session.commit()

    senders = (await session.execute(text("select sender from messages order by id"))).scalars()
    assert list(senders) == ["student", "mentor"]


async def test_excluded_peer_ids_are_scoped_to_the_account(
    session: AsyncSession, account: MentorAccount
) -> None:
    await session.execute(
        text("insert into excluded_chats (account_id, telegram_peer_id) values (:a, :p)"),
        {"a": account.id, "p": 999},
    )
    await session.commit()

    assert await excluded_peer_ids(session, account.id) == frozenset({999})
    assert await excluded_peer_ids(session, account.id + 1000) == frozenset()
