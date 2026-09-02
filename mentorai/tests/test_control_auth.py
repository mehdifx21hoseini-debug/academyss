"""مجوزدهی ربات کنترل.

این‌ها تست‌های همان سه یافته‌ی بازبینی امنیتی‌اند. ربات کنترل تنها جایی بود که قاعده‌ی
«بررسی دسترسی پیش از اولین خواندن» رعایت نشده بود.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.config import get_settings
from mentorai.control.auth import (
    ControlNotPermitted,
    authorise_draft,
    authorise_draft_by_control_message,
    is_operator,
)
from mentorai.db.models import AiRun, Conversation, Draft, MentorAccount, Message, Student

OPERATOR = 111
OUTSIDER = 222


@pytest.fixture(autouse=True)
def _allowlist(monkeypatch: pytest.MonkeyPatch) -> None:
    get_settings.cache_clear()
    monkeypatch.setenv("CONTROL_OPERATOR_IDS", str(OPERATOR))
    yield
    get_settings.cache_clear()


async def _draft(
    session: AsyncSession, account: MentorAccount, *, control_message_id: int = 500
) -> Draft:
    student = Student(display_name="دانشجو")
    session.add(student)
    await session.flush()
    conversation = Conversation(account_id=account.id, student_id=student.id, telegram_chat_id=900)
    session.add(conversation)
    await session.flush()
    message = Message(
        conversation_id=conversation.id,
        telegram_message_id=1,
        sender="student",
        text="سؤال",
        sent_at=datetime.now(UTC),
    )
    session.add(message)
    await session.flush()
    run = AiRun(
        conversation_id=conversation.id,
        message_id=message.id,
        outcome="answer",
        reason="ok",
        prompt_version="v1",
        retrieved=[],
    )
    session.add(run)
    await session.flush()
    draft = Draft(
        ai_run_id=run.id,
        conversation_id=conversation.id,
        proposed_text="پاسخ",
        control_message_id=control_message_id,
    )
    session.add(draft)
    await session.flush()
    return draft


def test_unknown_sender_is_not_an_operator() -> None:
    assert is_operator(OPERATOR) is True
    assert is_operator(OUTSIDER) is False
    assert is_operator(None) is False


def test_empty_allowlist_denies_everyone(monkeypatch: pytest.MonkeyPatch) -> None:
    """تنظیم‌نشده بودن نباید به دسترسی باز ختم شود."""
    get_settings.cache_clear()
    monkeypatch.setenv("CONTROL_OPERATOR_IDS", "")
    assert is_operator(OPERATOR) is False
    get_settings.cache_clear()


async def test_operator_in_the_linked_chat_is_allowed(
    session: AsyncSession, account: MentorAccount
) -> None:
    account.control_chat_id = 777
    draft = await _draft(session, account)
    await session.commit()

    got, got_account = await authorise_draft(session, draft.id, chat_id=777, sender_id=OPERATOR)
    assert got.id == draft.id
    assert got_account.id == account.id


async def test_non_operator_cannot_act_even_in_the_linked_chat(
    session: AsyncSession, account: MentorAccount
) -> None:
    account.control_chat_id = 777
    draft = await _draft(session, account)
    await session.commit()

    with pytest.raises(ControlNotPermitted):
        await authorise_draft(session, draft.id, chat_id=777, sender_id=OUTSIDER)


async def test_operator_cannot_act_from_another_chat(
    session: AsyncSession, account: MentorAccount
) -> None:
    """شناسه‌های پیش‌نویس پشت‌سرهم‌اند؛ حدس زدنشان نباید کافی باشد."""
    account.control_chat_id = 777
    draft = await _draft(session, account)
    await session.commit()

    with pytest.raises(ControlNotPermitted):
        await authorise_draft(session, draft.id, chat_id=999, sender_id=OPERATOR)


async def test_unlinked_account_allows_nothing(
    session: AsyncSession, account: MentorAccount
) -> None:
    account.control_chat_id = None
    draft = await _draft(session, account)
    await session.commit()

    with pytest.raises(ControlNotPermitted):
        await authorise_draft(session, draft.id, chat_id=777, sender_id=OPERATOR)


async def test_missing_draft_and_forbidden_draft_are_indistinguishable(
    session: AsyncSession, account: MentorAccount
) -> None:
    """پاسخ متفاوت به این دو، راهی برای شمردن شناسه‌های موجود می‌دهد."""
    account.control_chat_id = 777
    draft = await _draft(session, account)
    await session.commit()

    with pytest.raises(ControlNotPermitted) as missing:
        await authorise_draft(session, 999999, chat_id=777, sender_id=OPERATOR)
    with pytest.raises(ControlNotPermitted) as forbidden:
        await authorise_draft(session, draft.id, chat_id=999, sender_id=OPERATOR)
    assert str(missing.value).replace("999999", "X") == str(forbidden.value).replace(
        str(draft.id), "X"
    )


async def test_reply_lookup_is_scoped_to_the_chat(
    session: AsyncSession, account: MentorAccount
) -> None:
    """شناسه‌ی پیام تلگرام فقط داخل یک گفتگو یکتاست.

    بدون محدود کردن جستجو به گفتگو، ریپلای در گفتگوی دیگری روی پیامی با همان شناسه،
    پیش‌نویس واقعی یک منتور را ویرایش و ارسال می‌کرد.
    """
    account.control_chat_id = 777
    draft = await _draft(session, account, control_message_id=500)
    await session.commit()

    found, _ = await authorise_draft_by_control_message(
        session, 500, chat_id=777, sender_id=OPERATOR
    )
    assert found.id == draft.id

    with pytest.raises(ControlNotPermitted):
        await authorise_draft_by_control_message(session, 500, chat_id=999, sender_id=OPERATOR)


async def test_reply_lookup_requires_an_operator(
    session: AsyncSession, account: MentorAccount
) -> None:
    account.control_chat_id = 777
    await _draft(session, account, control_message_id=500)
    await session.commit()

    with pytest.raises(ControlNotPermitted):
        await authorise_draft_by_control_message(session, 500, chat_id=777, sender_id=OUTSIDER)
