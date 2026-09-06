"""کارگر: از پیام تا تحویل."""

from __future__ import annotations

import csv
from datetime import UTC, datetime
from pathlib import Path

import pytest
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession
from tests.test_sender import FakeChannel

from mentorai import drafts
from mentorai.ai.client import ScriptedClient
from mentorai.ai.schema import ModelAnswer
from mentorai.conversation import escalate
from mentorai.db.models import Conversation, Draft, MentorAccount, Message, ReplyMode, Sender
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.ingest import ingest_csv
from mentorai.media import store as media_store
from mentorai.media.extract import Extraction
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.safety import AccountGate, TokenBucket
from mentorai.telegram.store import record_inbound
from mentorai.worker import process_message, send_approved_draft

NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)


class RecordingNotifier:
    def __init__(self) -> None:
        self.sent: list[tuple[str, str]] = []
        # پرسشی که کنار پیش‌نویس به منتور نشان داده می‌شود، جدا نگه داشته می‌شود:
        # منتور نباید پاسخی را تأیید کند که سؤالش را ندیده است.
        self.questions: list[str] = []

    async def notify(self, *, account: MentorAccount, draft: Draft, question: str) -> int | None:
        self.sent.append((account.slug, draft.proposed_text))
        self.questions.append(question)
        return 12345


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


@pytest.fixture
async def incoming(session: AsyncSession, account: MentorAccount) -> Message:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=900,
        message_id=7,
        sender_user_id=900,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text="دوره مقدماتی چیست؟",
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


def _answer() -> ModelAnswer:
    return ModelAnswer(
        answer="دوره مقدماتی شانزده جلسه دارد.",
        confidence=0.95,
        needs_human=False,
        reason="منبع رسمی",
    )


def _gate() -> AccountGate:
    return AccountGate(
        slug="mentor-a",
        bucket=TokenBucket(rate_per_minute=60, burst=5),
        quiet_start=23,
        quiet_end=8,
    )


async def test_draft_mode_creates_a_draft_and_sends_nothing(
    session: AsyncSession,
    account: MentorAccount,
    kb: None,
    incoming: Message,
    embedder: HashingEmbedder,
) -> None:
    channel = FakeChannel()
    notifier = RecordingNotifier()

    outcome = await process_message(
        session,
        incoming.id,
        model_client=ScriptedClient(_answer()),
        embedder=embedder,
        channels={"mentor-a": channel},
        gates={"mentor-a": _gate()},
        notifier=notifier,
        sleep=False,
    )
    await session.commit()

    assert outcome.outcome == "drafted"
    assert channel.sent == [], "در حالت پیش‌نویس هیچ چیزی به دانشجو نمی‌رود"
    assert channel.reads == [], "و پیام خوانده علامت نمی‌خورد"
    assert notifier.sent == [("mentor-a", "دوره مقدماتی شانزده جلسه دارد.")]


async def test_the_mentor_sees_what_was_heard_in_a_voice_message(
    session: AsyncSession,
    account: MentorAccount,
    kb: None,
    embedder: HashingEmbedder,
) -> None:
    """ویس متن ندارد. بدون رونویسی، منتور پیش‌نویسی می‌بیند بدون سؤالش."""
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=901,
        message_id=8,
        sender_user_id=901,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text=None,
        media_type="voice",
        reply_to_message_id=None,
        sent_at=NOON,
        is_private=True,
        is_outgoing=False,
    )
    stored = await record_inbound(session, account, inbound, sender=Sender.student)
    assert stored.message_id is not None
    await media_store.record(
        session,
        message_id=stored.message_id,
        extraction=Extraction(kind="voice", text="دوره مقدماتی چیست؟"),
    )
    await session.commit()

    notifier = RecordingNotifier()
    outcome = await process_message(
        session,
        stored.message_id,
        model_client=ScriptedClient(_answer()),
        embedder=embedder,
        channels={"mentor-a": FakeChannel()},
        gates={"mentor-a": _gate()},
        notifier=notifier,
        sleep=False,
    )
    await session.commit()

    assert outcome.outcome == "drafted"
    assert "دوره مقدماتی چیست؟" in notifier.questions[0]
    assert "ویس دانشجو" in notifier.questions[0]


async def test_auto_mode_sends_directly(
    session: AsyncSession,
    account: MentorAccount,
    kb: None,
    incoming: Message,
    embedder: HashingEmbedder,
) -> None:
    account.reply_mode = ReplyMode.auto.value
    await session.commit()
    channel = FakeChannel()

    outcome = await process_message(
        session,
        incoming.id,
        model_client=ScriptedClient(_answer()),
        embedder=embedder,
        channels={"mentor-a": channel},
        gates={"mentor-a": _gate()},
        notifier=None,
        sleep=False,
    )
    await session.commit()

    assert outcome.outcome == "sent"
    assert channel.sent == [(900, "دوره مقدماتی شانزده جلسه دارد.")]
    assert channel.reads == [(900, 7)]


async def test_switching_mode_needs_no_code_change(
    session: AsyncSession,
    account: MentorAccount,
    kb: None,
    incoming: Message,
    embedder: HashingEmbedder,
) -> None:
    """ADR-010: برداشتن تأیید باید یک تنظیم باشد، نه بازنویسی."""
    assert account.reply_mode == ReplyMode.draft.value
    account.reply_mode = ReplyMode.auto.value
    await session.commit()

    outcome = await process_message(
        session,
        incoming.id,
        model_client=ScriptedClient(_answer()),
        embedder=embedder,
        channels={"mentor-a": FakeChannel()},
        gates={"mentor-a": _gate()},
        notifier=None,
        sleep=False,
    )
    assert outcome.outcome == "sent"


async def test_silence_leaves_no_trace_and_creates_no_draft(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=901,
        message_id=8,
        sender_user_id=901,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text="رسید واریزم رو فرستادم",
        media_type=None,
        reply_to_message_id=None,
        sent_at=NOON,
        is_private=True,
        is_outgoing=False,
    )
    result = await record_inbound(session, account, inbound, sender=Sender.student)
    await session.commit()
    assert result.message_id is not None
    channel = FakeChannel()

    outcome = await process_message(
        session,
        result.message_id,
        model_client=ScriptedClient(_answer()),
        embedder=embedder,
        channels={"mentor-a": channel},
        gates={"mentor-a": _gate()},
        notifier=RecordingNotifier(),
        sleep=False,
    )
    await session.commit()

    assert outcome.outcome == "silence"
    assert channel.reads == [] and channel.sent == []
    assert (await session.execute(text("select count(*) from drafts"))).scalar_one() == 0


async def test_escalated_conversation_is_skipped_even_if_already_queued(
    session: AsyncSession,
    account: MentorAccount,
    kb: None,
    incoming: Message,
    embedder: HashingEmbedder,
) -> None:
    """وضعیت ممکن است بین صف شدن و پردازش عوض شده باشد."""
    conversation = await session.get_one(Conversation, incoming.conversation_id)
    escalate(conversation)
    await session.commit()

    outcome = await process_message(
        session,
        incoming.id,
        model_client=ScriptedClient(_answer()),
        embedder=embedder,
        channels={"mentor-a": FakeChannel()},
        gates={"mentor-a": _gate()},
        notifier=None,
        sleep=False,
    )
    assert outcome.outcome == "assistant_disabled"


async def test_approved_draft_is_sent_from_the_mentor_account(
    session: AsyncSession,
    account: MentorAccount,
    kb: None,
    incoming: Message,
    embedder: HashingEmbedder,
) -> None:
    channel = FakeChannel()
    await process_message(
        session,
        incoming.id,
        model_client=ScriptedClient(_answer()),
        embedder=embedder,
        channels={"mentor-a": channel},
        gates={"mentor-a": _gate()},
        notifier=RecordingNotifier(),
        sleep=False,
    )
    await session.commit()

    draft = (await session.execute(select(Draft))).scalar_one()
    await drafts.approve(session, draft.id, by="mentor-a")
    outcome = await send_approved_draft(
        session,
        draft.id,
        channels={"mentor-a": channel},
        gates={"mentor-a": _gate()},
        sleep=False,
    )
    await session.commit()

    assert outcome.outcome == "sent"
    assert channel.sent == [(900, "دوره مقدماتی شانزده جلسه دارد.")]
    assert channel.reads == [(900, 7)], "علامت خوانده‌شدن تا همان پیام پاسخ‌داده‌شده"
    assert (await session.get_one(Draft, draft.id)).status == "sent"


async def test_edited_draft_sends_the_mentor_text(
    session: AsyncSession,
    account: MentorAccount,
    kb: None,
    incoming: Message,
    embedder: HashingEmbedder,
) -> None:
    channel = FakeChannel()
    await process_message(
        session,
        incoming.id,
        model_client=ScriptedClient(_answer()),
        embedder=embedder,
        channels={"mentor-a": channel},
        gates={"mentor-a": _gate()},
        notifier=RecordingNotifier(),
        sleep=False,
    )
    await session.commit()

    draft = (await session.execute(select(Draft))).scalar_one()
    await drafts.edit(session, draft.id, by="mentor-a", body="متن اصلاح‌شده منتور")
    await send_approved_draft(
        session, draft.id, channels={"mentor-a": channel}, gates={"mentor-a": _gate()}, sleep=False
    )
    await session.commit()

    assert channel.sent == [(900, "متن اصلاح‌شده منتور")]
