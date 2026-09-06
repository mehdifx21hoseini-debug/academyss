from __future__ import annotations

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import drafts
from mentorai.db.models import AiRun, Conversation, DraftStatus, MentorAccount, Message, Student


@pytest.fixture
async def run(session: AsyncSession, account: MentorAccount) -> AiRun:
    student = Student(display_name="دانشجو")
    session.add(student)
    await session.flush()
    conversation = Conversation(account_id=account.id, student_id=student.id, telegram_chat_id=800)
    session.add(conversation)
    await session.flush()
    message = Message(
        conversation_id=conversation.id,
        telegram_message_id=1,
        sender="student",
        text="سؤال",
        sent_at=__import__("datetime").datetime.now(__import__("datetime").UTC),
    )
    session.add(message)
    await session.flush()
    ai_run = AiRun(
        conversation_id=conversation.id,
        message_id=message.id,
        outcome="answer",
        reason="ok",
        prompt_version="v1",
        retrieved=[],
    )
    session.add(ai_run)
    await session.flush()
    return ai_run


async def test_approve_uses_the_proposed_text(session: AsyncSession, run: AiRun) -> None:
    draft = await drafts.create(
        session,
        ai_run_id=run.id,
        conversation_id=run.conversation_id,
        proposed_text="پاسخ پیشنهادی",
    )
    approved = await drafts.approve(session, draft.id, by="mentor-a")

    assert approved.status == DraftStatus.approved.value
    assert approved.final_text == "پاسخ پیشنهادی"
    assert approved.decided_by == "mentor-a"


async def test_edit_keeps_the_mentor_text_and_is_distinguishable(
    session: AsyncSession, run: AiRun
) -> None:
    """تفاوت ویرایش و تأیید باید در ثبت بماند.

    نسبت ویرایش به تأیید بدون تغییر، همان عددی است که شرط خروج از حالت پیش‌نویس را
    تعیین می‌کند.
    """
    draft = await drafts.create(
        session, ai_run_id=run.id, conversation_id=run.conversation_id, proposed_text="نسخه مدل"
    )
    edited = await drafts.edit(session, draft.id, by="mentor-a", body="نسخه منتور")

    assert edited.status == DraftStatus.edited.value
    assert edited.final_text == "نسخه منتور"
    assert edited.proposed_text == "نسخه مدل"


async def test_reject_sends_nothing(session: AsyncSession, run: AiRun) -> None:
    draft = await drafts.create(
        session, ai_run_id=run.id, conversation_id=run.conversation_id, proposed_text="پاسخ"
    )
    rejected = await drafts.reject(session, draft.id, by="mentor-a")

    assert rejected.status == DraftStatus.rejected.value
    assert rejected.final_text is None


async def test_a_draft_can_only_be_decided_once(session: AsyncSession, run: AiRun) -> None:
    """دوبار زدن دکمه‌ی تأیید نباید دو پیام بفرستد."""
    draft = await drafts.create(
        session, ai_run_id=run.id, conversation_id=run.conversation_id, proposed_text="پاسخ"
    )
    await drafts.approve(session, draft.id, by="mentor-a")

    with pytest.raises(drafts.DraftNotPending):
        await drafts.approve(session, draft.id, by="mentor-a")
    with pytest.raises(drafts.DraftNotPending):
        await drafts.reject(session, draft.id, by="mentor-a")


async def test_edit_rejects_an_empty_body(session: AsyncSession, run: AiRun) -> None:
    draft = await drafts.create(
        session, ai_run_id=run.id, conversation_id=run.conversation_id, proposed_text="پاسخ"
    )
    with pytest.raises(ValueError):
        await drafts.edit(session, draft.id, by="mentor-a", body="   ")


async def test_deciding_a_missing_draft_raises(session: AsyncSession) -> None:
    with pytest.raises(drafts.DraftNotPending):
        await drafts.approve(session, 999999, by="mentor-a")
