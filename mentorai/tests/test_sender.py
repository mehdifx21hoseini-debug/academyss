"""مسیر ارسال.

مهم‌ترین چیزی که اینجا سنجیده می‌شود: وقتی ارسال انجام نمی‌شود، هیچ اثری در تلگرام
گذاشته نمی‌شود — نه علامت خوانده‌شدن، نه نشانگر تایپ (ADR-009).

`push` عمداً هیچ نشستی نمی‌گیرد و چیزی نمی‌نویسد؛ ثبت نتیجه کار `record_sent` است
در تراکنشی جدا (ADR-030). صندوق خروج و ماشین حالتش در `test_delivery.py`.
"""

from __future__ import annotations

from datetime import UTC, datetime
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import Conversation, MentorAccount, Message, Sender
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.safety import AccountGate, TokenBucket
from mentorai.telegram.sender import (
    MAX_PARTS,
    FloodWait,
    SendStatus,
    push,
    record_sent,
    split_messages,
)
from mentorai.telegram.store import record_inbound

NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)


class FakeChannel:
    def __init__(self, *, fail_with: Exception | None = None) -> None:
        self.reads: list[tuple[int, int]] = []
        self.typing: list[int] = []
        self.sent: list[tuple[int, str]] = []
        # پیامی که هر قطعه‌ی رفته نقلش کرد (None = نقل نداشت)، هم‌ردیف با `sent`.
        self.quotes: list[int | None] = []
        self._fail_with = fail_with
        self._next_id = 900

    async def mark_read(self, chat_id: int, max_message_id: int) -> None:
        self.reads.append((chat_id, max_message_id))

    async def set_typing(self, chat_id: int) -> None:
        self.typing.append(chat_id)

    async def send(self, chat_id: int, body: str, reply_to: int | None = None) -> int:
        if self._fail_with is not None:
            raise self._fail_with
        self._next_id += 1
        self.sent.append((chat_id, body))
        self.quotes.append(reply_to)
        return self._next_id


TEHRAN = ZoneInfo("Asia/Tehran")


def _gate(**kw: object) -> AccountGate:
    defaults = {
        "slug": "mentor-a",
        "bucket": TokenBucket(rate_per_minute=60, burst=5),
        "quiet_start": 23,
        "quiet_end": 8,
        "tz": TEHRAN,
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

    result = await push(
        chat_id=conversation.telegram_chat_id,
        answered_telegram_message_id=message.telegram_message_id,
        body="شانزده جلسه.",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
    )
    assert result.status is SendStatus.sent
    assert result.telegram_message_id is not None
    record_sent(
        session,
        conversation=conversation,
        answered_message=message,
        body="شانزده جلسه.",
        telegram_message_id=result.telegram_message_id,
        now=NOON,
    )
    await session.commit()

    assert channel.sent == [(700, "شانزده جلسه.")]
    senders = list(
        (await session.execute(text("select sender from messages order by id"))).scalars()
    )
    assert senders == ["student", "assistant"]


async def test_read_receipt_stops_at_the_answered_message(session: AsyncSession, scenario) -> None:  # type: ignore[no-untyped-def]
    """پیام‌های بعدی که هنوز جواب نگرفته‌اند باید خوانده‌نشده بمانند."""
    account, conversation, message = scenario
    channel = FakeChannel()

    result = await push(
        chat_id=conversation.telegram_chat_id,
        answered_telegram_message_id=message.telegram_message_id,
        body="پاسخ",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
    )
    assert result.telegram_message_id is not None
    record_sent(
        session,
        conversation=conversation,
        answered_message=message,
        body="پاسخ",
        telegram_message_id=result.telegram_message_id,
        now=NOON,
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

    result = await push(
        chat_id=conversation.telegram_chat_id,
        answered_telegram_message_id=message.telegram_message_id,
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

    result = await push(
        chat_id=conversation.telegram_chat_id,
        answered_telegram_message_id=message.telegram_message_id,
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

    result = await push(
        chat_id=conversation.telegram_chat_id,
        answered_telegram_message_id=message.telegram_message_id,
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


# ---------------------------------------------------------------------------
# پاسخ چندپیامی
# ---------------------------------------------------------------------------


class PartiallyFailingChannel(FakeChannel):
    """کانالی که پس از n پیام موفق، رد می‌کند.

    حالتی را می‌سازد که چندپیامی شدن تازه ممکنش کرده: نیمی از پاسخ رفته و نیمی نه.
    """

    def __init__(self, *, succeed: int, then: Exception) -> None:
        super().__init__()
        self._succeed = succeed
        self._then = then

    async def send(self, chat_id: int, body: str, reply_to: int | None = None) -> int:
        if len(self.sent) >= self._succeed:
            raise self._then
        self._next_id += 1
        self.sent.append((chat_id, body))
        self.quotes.append(reply_to)
        return self._next_id


@pytest.mark.parametrize(
    ("body", "expected"),
    [
        ("یک جمله.", ["یک جمله."]),
        ("اول.\n\nدوم.", ["اول.", "دوم."]),
        # خط خالی با فاصله هم خط خالی است؛ مدل همیشه تمیز نمی‌نویسد.
        ("اول.\n   \nدوم.", ["اول.", "دوم."]),
        # شکست تک‌خطی پیام جدا نیست: بند همان بند است.
        ("خط اول\nخط دوم", ["خط اول\nخط دوم"]),
        ("  \n\n  ", []),
        ("", []),
    ],
)
def test_the_blank_line_is_the_message_boundary(body: str, expected: list[str]) -> None:
    """مرز، خط خالی است — نه تعداد کاراکتر.

    شکستن مکانیکی روی طول، جمله را از وسط نصف می‌کند. خط خالی یعنی مدل خودش گفته
    «اینجا پیام تمام شد»، و منتور هم با همان خط خالی جایش را عوض می‌کند.
    """
    assert split_messages(body) == expected


def test_too_many_parts_are_joined_not_dropped() -> None:
    """پاسخ بریده، از پیام بلند بدتر است."""
    body = "\n\n".join(f"تکه {i}" for i in range(1, 8))
    parts = split_messages(body)

    assert len(parts) == MAX_PARTS
    assert "تکه 7" in parts[-1], "تکه‌های اضافه دور ریخته شدند"
    for i in range(1, 8):
        assert f"تکه {i}" in "\n\n".join(parts)


async def test_a_three_part_answer_arrives_as_three_messages() -> None:
    """شکستی که می‌بندد: یک پاراگراف مرتب، جایی که منتور سه جمله‌ی کوتاه می‌فرستد.

    در ۱۱۶ پاسخ واقعی منتورهای آکادمی، ۴۸٪ بیش از یک پیام بود. سیستم همیشه یک پیام
    می‌فرستاد، و این از هر انتخاب کلمه‌ای بیشتر لو می‌داد.
    """
    channel = FakeChannel()
    result = await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body="سلام وقتتون بخیر.\n\nاز ویدیوی اول شروع کنید.\n\nپرقدرت پیش برید.",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
    )

    assert result.status is SendStatus.sent
    assert result.parts_sent == 3
    assert [body for _, body in channel.sent] == [
        "سلام وقتتون بخیر.",
        "از ویدیوی اول شروع کنید.",
        "پرقدرت پیش برید.",
    ]
    # علامت خوانده‌شدن یک بار، نشانگر تایپ پیش از هر پیام: تایپِ تلگرام چند ثانیه‌ای
    # منقضی می‌شود، پس برای پیام سوم باید دوباره فرستاده شود.
    assert len(channel.reads) == 1
    assert len(channel.typing) == 3


async def test_an_answer_without_a_blank_line_is_still_one_message() -> None:
    """رفتار پیشین باید دست‌نخورده بماند."""
    channel = FakeChannel()
    result = await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body="دوره مقدماتی پانزده جلسه دارد.",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
    )

    assert result.parts_sent == 1
    assert channel.sent == [(700, "دوره مقدماتی پانزده جلسه دارد.")]


async def test_a_flood_wait_mid_burst_reports_what_already_went() -> None:
    """مهم‌ترین تست چندپیامی شدن.

    سناریو: پیام اول رفت، پیام دوم `FloodWait` خورد. اگر `parts_sent` گزارش نشود،
    تلاش دوباره از اول شروع می‌کند و دانشجو پیام اول را **دو بار** می‌گیرد — همان
    شکستی که کل صندوق خروج برای جلوگیری از آن ساخته شده (`ADR-030`).
    """
    channel = PartiallyFailingChannel(succeed=1, then=FloodWait(30))
    result = await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body="تکه یک.\n\nتکه دو.\n\nتکه سه.",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
    )

    assert result.status is SendStatus.blocked
    assert result.reason == "flood_wait"
    assert result.parts_sent == 1, "تعداد قطعه‌های رفته گزارش نشد"
    assert [body for _, body in channel.sent] == ["تکه یک."]


async def test_the_retry_resumes_and_never_repeats_a_sent_part() -> None:
    """نیمه‌ی دوم همان تضمین: ادامه از قطعه‌ی بعدی، نه از اول."""
    channel = FakeChannel()
    result = await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body="تکه یک.\n\nتکه دو.\n\nتکه سه.",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
        start_at=1,
    )

    assert result.status is SendStatus.sent
    assert result.parts_sent == 2
    assert [body for _, body in channel.sent] == ["تکه دو.", "تکه سه."]
    assert "تکه یک." not in [body for _, body in channel.sent], "قطعه‌ی رفته دوباره فرستاده شد"
    # علامت خوانده‌شدن در تلاش اول زده شده؛ دوباره زدنش کار بی‌خودِ شبکه است.
    assert channel.reads == []


async def test_a_resume_past_the_end_sends_nothing() -> None:
    """اگر همه‌ی قطعه‌ها رفته باشند، تلاش دوباره نباید چیزی بفرستد."""
    channel = FakeChannel()
    result = await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body="تکه یک.\n\nتکه دو.",
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
        start_at=2,
    )

    assert result.parts_sent == 0
    assert channel.sent == [], "پس از رفتن همه‌ی قطعه‌ها دوباره فرستاده شد"


async def test_a_blocked_gate_sends_no_part_at_all() -> None:
    """دروازه پیش از تقسیم بررسی می‌شود: ساعت سکوت یعنی هیچ قطعه‌ای، نه قطعه‌ی اول."""
    channel = FakeChannel()
    quiet = datetime(2026, 9, 2, 1, 0, tzinfo=TEHRAN)

    result = await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body="تکه یک.\n\nتکه دو.",
        gate=_gate(),
        channel=channel,
        now=quiet,
        sleep=False,
    )

    assert result.status is SendStatus.blocked
    assert result.parts_sent == 0
    assert channel.sent == []
    assert channel.reads == [], "در ساعت سکوت پیام خوانده علامت خورد"
