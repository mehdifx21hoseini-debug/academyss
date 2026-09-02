"""محدودسازی دسترسی منتور.

تست‌های منفی اینجا مهم‌ترین بخش‌اند: اثبات اینکه منتور الف از هیچ مسیری به دانشجوی
منتور ب نمی‌رسد. تست مثبت به‌تنهایی چیزی درباره‌ی امنیت ثابت نمی‌کند.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.access import (
    NotPermitted,
    Principal,
    Role,
    get_conversation,
    get_student,
    list_conversations,
    list_identities,
    list_messages,
)
from mentorai.db.models import MentorAccount, Sender
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound


def _msg(chat_id: int, message_id: int = 1):  # type: ignore[no-untyped-def]
    return build_inbound(
        account_slug="x",
        chat_id=chat_id,
        message_id=message_id,
        sender_user_id=chat_id,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text="سلام",
        media_type=None,
        reply_to_message_id=None,
        sent_at=datetime(2026, 9, 2, 12, 0, tzinfo=UTC),
        is_private=True,
        is_outgoing=False,
    )


@pytest.fixture
async def two_mentors(session: AsyncSession, account: MentorAccount):  # type: ignore[no-untyped-def]
    """منتور الف با دانشجوی خودش، منتور ب با دانشجوی خودش."""
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

    a = await record_inbound(session, account, _msg(chat_id=111), sender=Sender.student)
    b = await record_inbound(session, other, _msg(chat_id=222), sender=Sender.student)
    await session.commit()

    return {
        "account_a": account,
        "account_b": other,
        "conv_a": a.conversation_id,
        "conv_b": b.conversation_id,
        "principal_a": Principal(role=Role.mentor, account_id=account.id, label="mentor-a"),
        "principal_b": Principal(role=Role.mentor, account_id=other.id, label="mentor-b"),
        "admin": Principal(role=Role.admin, label="admin"),
    }


async def test_mentor_sees_only_their_own_conversations(session: AsyncSession, two_mentors) -> None:  # type: ignore[no-untyped-def]
    listed = await list_conversations(session, two_mentors["principal_a"])
    assert [c.id for c in listed] == [two_mentors["conv_a"]]


async def test_mentor_cannot_open_another_mentors_conversation(
    session: AsyncSession, two_mentors
) -> None:  # type: ignore[no-untyped-def]
    with pytest.raises(NotPermitted):
        await get_conversation(session, two_mentors["principal_a"], two_mentors["conv_b"])


async def test_mentor_cannot_read_another_mentors_messages(
    session: AsyncSession, two_mentors
) -> None:  # type: ignore[no-untyped-def]
    """مسیر پیام هم باید بسته باشد، نه فقط مسیر مکالمه."""
    with pytest.raises(NotPermitted):
        await list_messages(session, two_mentors["principal_a"], two_mentors["conv_b"])


async def test_mentor_cannot_read_another_mentors_student(
    session: AsyncSession, two_mentors
) -> None:  # type: ignore[no-untyped-def]
    conv_b = await get_conversation(session, two_mentors["admin"], two_mentors["conv_b"])
    with pytest.raises(NotPermitted):
        await get_student(session, two_mentors["principal_a"], conv_b.student_id)


async def test_mentor_cannot_list_another_students_identities(
    session: AsyncSession, two_mentors
) -> None:  # type: ignore[no-untyped-def]
    conv_b = await get_conversation(session, two_mentors["admin"], two_mentors["conv_b"])
    with pytest.raises(NotPermitted):
        await list_identities(session, two_mentors["principal_a"], conv_b.student_id)


async def test_admin_sees_every_conversation(session: AsyncSession, two_mentors) -> None:  # type: ignore[no-untyped-def]
    listed = await list_conversations(session, two_mentors["admin"])
    assert {c.id for c in listed} == {two_mentors["conv_a"], two_mentors["conv_b"]}


async def test_mentor_can_reach_their_own_data(session: AsyncSession, two_mentors) -> None:  # type: ignore[no-untyped-def]
    conv = await get_conversation(session, two_mentors["principal_a"], two_mentors["conv_a"])
    assert conv.id == two_mentors["conv_a"]
    assert len(await list_messages(session, two_mentors["principal_a"], conv.id)) == 1
    assert (await get_student(session, two_mentors["principal_a"], conv.student_id)) is not None


async def test_shared_student_is_visible_to_both_mentors_separately(
    session: AsyncSession, two_mentors
) -> None:  # type: ignore[no-untyped-def]
    """یک نفر که به هر دو منتور پیام داده.

    هر منتور فقط از راه مکالمه‌ی خودش به او می‌رسد، ولی هر دو می‌رسند.
    """
    shared = await record_inbound(
        session, two_mentors["account_a"], _msg(chat_id=333), sender=Sender.student
    )
    await record_inbound(
        session, two_mentors["account_b"], _msg(chat_id=333), sender=Sender.student
    )
    await session.commit()

    conv = await get_conversation(session, two_mentors["principal_a"], shared.conversation_id)
    assert await get_student(session, two_mentors["principal_a"], conv.student_id)
    assert await get_student(session, two_mentors["principal_b"], conv.student_id)


async def test_reading_a_conversation_is_audited(session: AsyncSession, two_mentors) -> None:  # type: ignore[no-untyped-def]
    await get_conversation(session, two_mentors["principal_a"], two_mentors["conv_a"])
    await session.commit()

    rows = list(
        (
            await session.execute(
                text(
                    "select actor, action, target from audit_log where action = 'read_conversation'"
                )
            )
        ).all()
    )
    assert rows == [("mentor-a", "read_conversation", str(two_mentors["conv_a"]))]


async def test_mentor_principal_requires_an_account() -> None:
    """نقش منتور بدون حساب یعنی دامنه‌ی نامشخص، که همان دسترسی کامل است."""
    with pytest.raises(ValueError):
        Principal(role=Role.mentor, account_id=None)
