"""مسیر ارسال.

مهم‌ترین چیزی که اینجا سنجیده می‌شود: وقتی ارسال انجام نمی‌شود، هیچ اثری در تلگرام
گذاشته نمی‌شود — نه علامت خوانده‌شدن، نه نشانگر تایپ (ADR-009).
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import Conversation, MentorAccount, Message, Sender
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.safety import AccountGate, TokenBucket
from mentorai.telegram.sender import FloodWait, SendStatus, deliver_answer
from mentorai.telegram.store import record_inbound

NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)


class FakeChannel:
    def __init__(self, *, fail_with: Exception | None = None) -> None:
        self.reads: list[tuple[int, int]] = []
        self.typing: list[int] = []
        self.sent: list[tuple[int, str]] = []
        self._fail_with = fail_with
        self._next_id = 900

    async def mark_read(self, chat_id: int, max_message_id: int) -> None:
        self.reads.append((chat_id, max_message_id))

    async def set_typing(self, chat_id: int) -> None:
        self.typing.append(chat_id)

    async def send(self, chat_id: int, body: str) -> int:
        if self._fail_with is not None:
            raise self._fail_with
        self._next_id += 1
        self.sent.append((chat_id, body))
        return self._next_id


def _gate(**kw: object) -> AccountGate:
    defaults = {
        "slug": "mentor-a",
        "bucket": TokenBucket(rate_per_minute=60, burst=5),
        "quiet_start": 23,
        "quiet_end": 8,
    }
    return AccountGate(**{**defaults, **kw})  # type: ignore[arg-type]


@pytest.fixture
async def scenario(session: AsyncSession, account: MentorAccount):  # type: ignore[no-untyped-def]
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=700,
        message_id=42,
        sender_user_id=700,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text="دوره مقدماتی چند جلسه است؟",
        media_type=None,
        reply_to_message_id=None,
        sent_at=NOON,
        is_private=True,
        is_outgoing=False,
    )
    result = await record_inbound(session, account, inbound, sender=Sender.student)
    await session.commit()
    assert result.message_id is not None
    message = await session.get_one(Message, result.message_id)
    conversation = await session.get_one(Conversation, result.conversation_id)
    return account, conversation, message


async def test_answer_is_sent_and_recorded(session: AsyncSession, scenario) -> None:  # type: ignore[no-untyped-def]
    account, conversation, message = scenario
    channel = FakeChannel()

    result = await deliver_answer(
        session,
        account=account,
        conversation=conversation,
        answered_message=message,
        body="شانزده جلسه.",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
    )
    await session.commit()

    assert result.status is SendStatus.sent
    assert channel.sent == [(700, "شانزده جلسه.")]
    senders = list(
        (await session.execute(text("select sender from messages order by id"))).scalars()
    )
    assert senders == ["student", "assistant"]


async def test_read_receipt_stops_at_the_answered_message(session: AsyncSession, scenario) -> None:  # type: ignore[no-untyped-def]
    """پیام‌های بعدی که هنوز جواب نگرفته‌اند باید خوانده‌نشده بمانند."""
    account, conversation, message = scenario
    channel = FakeChannel()

    await deliver_answer(
        session,
        account=account,
        conversation=conversation,
        answered_message=message,
        body="پاسخ",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
    )
    await session.commit()

    assert channel.reads == [(700, 42)]
    assert conversation.last_answered_message_id == 42


@pytest.mark.parametrize(
    ("gate_kwargs", "at", "expected"),
    [
        ({"send_paused": True}, NOON, "send_paused"),
        ({}, datetime(2026, 9, 2, 3, 0, tzinfo=UTC), "quiet_hours"),
    ],
)
async def test_blocked_account_leaves_no_trace_in_telegram(
    session: AsyncSession, scenario, gate_kwargs: dict[str, object], at: datetime, expected: str
) -> None:  # type: ignore[no-untyped-def]
    account, conversation, message = scenario
    channel = FakeChannel()

    result = await deliver_answer(
        session,
        account=account,
        conversation=conversation,
        answered_message=message,
        body="پاسخ",
        gate=_gate(**gate_kwargs),
        channel=channel,
        now=at,
        sleep=False,
    )

    assert result.status is SendStatus.blocked
    assert result.reason == expected
    assert channel.reads == [], "پیام نباید خوانده علامت بخورد"
    assert channel.typing == [], "نشانگر تایپ نباید نشان داده شود"
    assert channel.sent == []


async def test_flood_wait_backs_off_the_whole_account(session: AsyncSession, scenario) -> None:  # type: ignore[no-untyped-def]
    account, conversation, message = scenario
    gate = _gate()
    channel = FakeChannel(fail_with=FloodWait(30))

    result = await deliver_answer(
        session,
        account=account,
        conversation=conversation,
        answered_message=message,
        body="پاسخ",
        gate=gate,
        channel=channel,
        now=NOON,
        sleep=False,
    )

    assert result.status is SendStatus.blocked
    assert result.reason == "flood_wait"
    assert gate.blocked_reason(NOON) == "flood_wait"


async def test_send_failure_does_not_record_an_assistant_message(
    session: AsyncSession, scenario
) -> None:  # type: ignore[no-untyped-def]
    """اگر ارسال شکست بخورد، نباید در تاریخچه بنویسیم پیامی رفته."""
    account, conversation, message = scenario
    channel = FakeChannel(fail_with=RuntimeError("network"))

    result = await deliver_answer(
        session,
        account=account,
        conversation=conversation,
        answered_message=message,
        body="پاسخ",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
    )
    await session.commit()

    assert result.status is SendStatus.failed
    count = (
        await session.execute(text("select count(*) from messages where sender = 'assistant'"))
    ).scalar_one()
    assert count == 0
    assert conversation.last_answered_message_id is None
