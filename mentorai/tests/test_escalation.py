"""ارجاع و بازگشت.

مرکز این تست‌ها تفکیک دو نوع سکوت است: نتوانستن در یک پیام، در برابر موضوعی که اصلاً
کار دستیار نیست.
"""

from __future__ import annotations

import csv
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession
from tests.test_sender import FakeChannel

from mentorai import escalation
from mentorai.ai.client import ScriptedClient
from mentorai.ai.schema import ModelAnswer
from mentorai.conversation import assistant_may_answer
from mentorai.db.models import (
    Conversation,
    ConversationStatus,
    Escalation,
    MentorAccount,
    Message,
    Sender,
)
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.ingest import ingest_csv
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound
from mentorai.worker import process_message

NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)


@pytest.fixture
def embedder() -> HashingEmbedder:
    return HashingEmbedder()


@pytest.fixture
async def kb(session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder) -> None:
    path = tmp_path / "kb.csv"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "source_class",
                "category",
                "question",
                "answer",
                "authority",
                "valid_until",
                "owner",
                "notes",
            ]
        )
        writer.writerow(
            [
                "official",
                "دوره‌ها",
                "دوره مقدماتی چیست؟",
                "شامل شانزده جلسه است.",
                "fact",
                "",
                "",
                "",
            ]
        )
    await ingest_csv(session, path, embedder=embedder)
    await session.commit()


async def _msg(
    session: AsyncSession,
    account: MentorAccount,
    body: str,
    *,
    message_id: int,
    sender: Sender = Sender.student,
    at: datetime = NOON,
) -> Message:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=950,
        message_id=message_id,
        sender_user_id=950,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text=body,
        media_type=None,
        reply_to_message_id=None,
        sent_at=at,
        is_private=True,
        is_outgoing=sender is Sender.mentor,
    )
    result = await record_inbound(session, account, inbound, sender=sender)
    await session.commit()
    assert result.message_id is not None
    return await session.get_one(Message, result.message_id)


def _answer() -> ModelAnswer:
    return ModelAnswer(
        answer="شانزده جلسه.", confidence=0.95, needs_human=False, reason="منبع رسمی"
    )


def _unsure() -> ModelAnswer:
    """سکوت موردی، مستقل از اینکه بازیابی چه برگرداند.

    استفاده از پرسشی که «هیچ سندی ندارد» تست را به رفتار بازیابی گره می‌زند و شکننده
    می‌کند؛ اطمینان پایین همان مسیر را قطعی تولید می‌کند.
    """
    return ModelAnswer(answer="شاید", confidence=0.2, needs_human=False, reason="اطمینان کافی نبود")


async def _run(  # type: ignore[no-untyped-def]
    session: AsyncSession,
    message: Message,
    embedder: HashingEmbedder,
    answer: ModelAnswer | None = None,
):
    return await process_message(
        session,
        message.id,
        model_client=ScriptedClient(answer or _answer()),
        embedder=embedder,
        channels={"mentor-a": FakeChannel()},
        gates={},
        notifier=None,
        sleep=False,
    )


async def test_sensitive_topic_hands_the_whole_conversation_over(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    """پول کار دستیار نیست، پس پیام بعدی هم کار دستیار نیست."""
    message = await _msg(session, account, "رسید واریزم رو فرستادم", message_id=1)
    await _run(session, message, embedder)
    await session.commit()

    conversation = await session.get_one(Conversation, message.conversation_id)
    assert conversation.status == ConversationStatus.awaiting_mentor.value
    assert assistant_may_answer(conversation) is False


async def test_ordinary_failure_leaves_the_conversation_active(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    """نتوانستن در یک سؤال نباید کل مکالمه را از کار بیندازد."""
    message = await _msg(session, account, "دوره مقدماتی چیست؟", message_id=1)
    outcome = await _run(session, message, embedder, _unsure())
    await session.commit()

    assert outcome.outcome == "silence"
    conversation = await session.get_one(Conversation, message.conversation_id)
    assert conversation.status == ConversationStatus.active.value
    assert assistant_may_answer(conversation) is True


async def test_assistant_still_answers_the_next_question_after_a_soft_silence(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    first = await _msg(session, account, "دوره مقدماتی چیست؟", message_id=1)
    await _run(session, first, embedder, _unsure())
    second = await _msg(session, account, "دوره مقدماتی چیست؟", message_id=2)
    outcome = await _run(session, second, embedder)
    await session.commit()

    assert outcome.outcome in {"drafted", "sent"}


async def test_mentor_reply_takes_over_and_closes_open_escalations(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    student = await _msg(session, account, "دوره مقدماتی چیست؟", message_id=1)
    await _run(session, student, embedder, _unsure())
    await session.commit()

    conversation = await session.get_one(Conversation, student.conversation_id)
    await escalation.on_mentor_message(session, conversation)
    await session.commit()

    assert conversation.status == ConversationStatus.awaiting_mentor.value
    row = (await session.execute(select(Escalation))).scalar_one()
    assert row.resolved_at is not None
    assert row.resolved_by == "mentor"


async def test_assistant_stays_quiet_while_the_mentor_is_mid_conversation(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    """اگر منتور همین حالا جواب داده، دستیار نباید وسط حرفش بپرد."""
    await _msg(session, account, "سلام", message_id=1)
    mentor_reply = await _msg(
        session, account, "سلام، بفرمایید", message_id=2, sender=Sender.mentor, at=NOON
    )
    conversation = await session.get_one(Conversation, mentor_reply.conversation_id)
    await escalation.on_mentor_message(session, conversation)
    await session.commit()

    resumed = await escalation.maybe_resume(
        session, conversation, after=timedelta(hours=12), now=NOON + timedelta(hours=1)
    )
    assert resumed is False
    assert conversation.status == ConversationStatus.awaiting_mentor.value


async def test_assistant_returns_once_the_mentor_has_been_quiet_long_enough(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    """بدون این، هر مکالمه‌ای که یک‌بار سپرده شد برای همیشه سپرده می‌ماند."""
    await _msg(session, account, "سلام", message_id=1)
    mentor_reply = await _msg(
        session, account, "سلام، بفرمایید", message_id=2, sender=Sender.mentor, at=NOON
    )
    conversation = await session.get_one(Conversation, mentor_reply.conversation_id)
    await escalation.on_mentor_message(session, conversation)
    await session.commit()

    resumed = await escalation.maybe_resume(
        session, conversation, after=timedelta(hours=12), now=NOON + timedelta(hours=20)
    )
    await session.commit()

    assert resumed is True
    assert conversation.status == ConversationStatus.active.value
    assert assistant_may_answer(conversation) is True


async def test_manual_resume_does_not_wait(session: AsyncSession, account: MentorAccount) -> None:
    message = await _msg(session, account, "سلام", message_id=1)
    conversation = await session.get_one(Conversation, message.conversation_id)
    await escalation.hand_off(session, conversation, reason="rule_money")
    await session.commit()

    assert await escalation.resume_now(session, conversation, by="mentor-a") is True
    assert conversation.status == ConversationStatus.active.value


async def test_resume_never_reopens_a_closed_conversation(
    session: AsyncSession, account: MentorAccount
) -> None:
    message = await _msg(session, account, "سلام", message_id=1)
    conversation = await session.get_one(Conversation, message.conversation_id)
    conversation.status = ConversationStatus.closed.value
    await session.commit()

    assert await escalation.maybe_resume(session, conversation) is False
    assert await escalation.resume_now(session, conversation, by="mentor-a") is False
    assert conversation.status == ConversationStatus.closed.value


async def test_handed_off_conversation_stays_frozen_until_the_mentor_replies(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    """اگر منتور هنوز جواب نداده، دستیار برنمی‌گردد.

    برگشتن در این حالت یعنی همان سؤال مالی که به منتور سپرده شده بود، عملاً به دستیار
    برگردد. شیر اطمینانِ نماندنِ ابدی، فهرست ارجاع‌های باز است نه بازگشت خودکار.
    """
    first = await _msg(session, account, "رسید واریزم", message_id=1)
    await _run(session, first, embedder)
    await session.commit()
    conversation = await session.get_one(Conversation, first.conversation_id)
    assert conversation.status == ConversationStatus.awaiting_mentor.value

    later = await _msg(session, account, "دوره مقدماتی چیست؟", message_id=2)
    outcome = await _run(session, later, embedder)
    await session.commit()

    assert outcome.outcome == "assistant_disabled"
    assert conversation.status == ConversationStatus.awaiting_mentor.value


async def test_worker_resumes_once_the_mentor_replied_long_enough_ago(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    """حلقه‌ی کامل: سپرده شد، منتور جواب داد، وقت گذشت، دستیار برگشت."""
    first = await _msg(session, account, "رسید واریزم", message_id=1)
    await _run(session, first, embedder)
    await session.commit()
    conversation = await session.get_one(Conversation, first.conversation_id)

    await _msg(
        session,
        account,
        "پیگیری کردم، درست شد",
        message_id=2,
        sender=Sender.mentor,
        at=NOON - timedelta(days=2),
    )
    await session.commit()

    later = await _msg(session, account, "دوره مقدماتی چیست؟", message_id=3)
    outcome = await _run(session, later, embedder)
    await session.commit()

    assert outcome.outcome in {"drafted", "sent"}
    assert conversation.status == ConversationStatus.active.value


async def test_open_escalations_are_listed_oldest_first_and_scoped(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    for i in (1, 2):
        message = await _msg(session, account, "دوره مقدماتی چیست؟", message_id=i)
        await _run(session, message, embedder, _unsure())
    await session.commit()

    listed = await escalation.open_escalations(session)
    assert len(listed) == 2
    assert listed[0][0].created_at <= listed[1][0].created_at
    assert await escalation.open_escalations(session, account_id=account.id + 999) == []


async def test_resolving_twice_is_harmless(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    message = await _msg(session, account, "دوره مقدماتی چیست؟", message_id=1)
    await _run(session, message, embedder, _unsure())
    await session.commit()

    assert await escalation.resolve_open(session, message.conversation_id, by="a") == 1
    assert await escalation.resolve_open(session, message.conversation_id, by="b") == 0
    await session.commit()

    remaining = (
        await session.execute(text("select count(*) from escalations where resolved_at is null"))
    ).scalar_one()
    assert remaining == 0


async def test_no_mentor_reply_means_no_automatic_resume(
    session: AsyncSession, account: MentorAccount
) -> None:
    message = await _msg(session, account, "سلام", message_id=1)
    conversation = await session.get_one(Conversation, message.conversation_id)
    await escalation.hand_off(session, conversation, reason="rule_money")
    await session.commit()

    assert (
        await escalation.maybe_resume(
            session, conversation, after=timedelta(hours=1), now=NOON + timedelta(days=30)
        )
        is False
    )
    assert conversation.status == ConversationStatus.awaiting_mentor.value
