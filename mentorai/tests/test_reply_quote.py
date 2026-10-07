"""نقل پیام دانشجو در پاسخ (ریپلای تلگرام، ADR-040).

شکستی که این فایل می‌بندد: سیستم هیچ‌وقت نمی‌توانست پیام را نقل کند. بعد از ساخته
شدنش سه خطر تازه هست و هر کدام جدا بسته می‌شود:

۱. **همه‌ی قطعه‌ها نقل بگیرند.** پاسخ چهارپیامی با چهار نقل شبیه رگبار ربات است.
۲. **نقل پیامِ پاک‌شده، پاسخ را بکشد.** دانشجو پیامش را پاک کرده و تلگرام رد می‌کند؛
   پاسخ باید بدون نقل برود، نه اینکه گم شود.
۳. **ادامه‌ی تلاشِ نیمه‌کاره دوباره نقل کند** و دانشجو یک پیام نقل‌شده‌ی اضافه ببیند.
"""

from __future__ import annotations

from datetime import timedelta
from typing import Any

import pytest
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession
from tests.test_sender import NOON, FakeChannel, PartiallyFailingChannel, _gate

from mentorai import delivery
from mentorai.config import get_settings
from mentorai.db.models import MentorAccount, Message, Sender
from mentorai.db.session import session_scope
from mentorai.telegram.channel import TelethonChannel
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.sender import FloodWait, SendStatus, push, reply_target
from mentorai.telegram.store import record_inbound
from mentorai.worker import deliver_claimed

# --- تصمیم: کدام پیام نقل شود ------------------------------------------------


@pytest.mark.parametrize(
    ("mode", "newer", "expected"),
    [
        ("always", False, 42),
        ("always", True, 42),
        ("smart", True, 42),
        ("smart", False, None),
        ("off", False, None),
        ("off", True, None),
    ],
)
def test_reply_target_follows_the_mode(mode: Any, newer: bool, expected: int | None) -> None:
    assert (
        reply_target(mode, answered_telegram_message_id=42, newer_student_message=newer)
        == expected
    )


# --- ارسال: فقط قطعه‌ی اول ---------------------------------------------------

THREE = "سلام وقتتون بخیر.\n\nاز ویدیوی اول شروع کنید.\n\nپرقدرت پیش برید."


async def test_only_the_first_part_quotes_the_message() -> None:
    channel = FakeChannel()
    result = await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body=THREE,
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
        reply_to_message_id=42,
    )

    assert result.status is SendStatus.sent and result.parts_sent == 3
    assert channel.quotes == [42, None, None], "فقط قطعه‌ی اول نقل می‌گیرد"


async def test_no_quote_requested_means_a_plain_message() -> None:
    channel = FakeChannel()
    await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body=THREE,
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
    )
    assert channel.quotes == [None, None, None]


async def test_a_resumed_attempt_never_quotes_again() -> None:
    """قطعه‌ی اول با نقلش قبلاً رفته؛ ادامه‌ی تلاش نباید نقلِ تازه بسازد."""
    channel = FakeChannel()
    await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body=THREE,
        gate=_gate(),
        channel=channel,
        now=NOON,
        sleep=False,
        start_at=1,
        reply_to_message_id=42,
    )

    assert [body for _, body in channel.sent] == ["از ویدیوی اول شروع کنید.", "پرقدرت پیش برید."]
    assert channel.quotes == [None, None]


async def test_a_blocked_first_part_keeps_its_quote_for_the_retry() -> None:
    """رد شدنِ قطعه‌ی اول چیزی نفرستاده؛ تلاش بعدی هنوز `start_at == 0` است و نقل می‌کند."""
    failing = PartiallyFailingChannel(succeed=0, then=FloodWait(30))
    result = await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body=THREE,
        gate=_gate(),
        channel=failing,
        now=NOON,
        sleep=False,
        reply_to_message_id=42,
    )
    assert result.status is SendStatus.blocked and result.parts_sent == 0

    retry = FakeChannel()
    await push(
        chat_id=700,
        answered_telegram_message_id=42,
        body=THREE,
        gate=_gate(),
        channel=retry,
        now=NOON + timedelta(minutes=5),
        sleep=False,
        start_at=result.parts_sent,
        reply_to_message_id=42,
    )
    assert retry.quotes == [42, None, None]


# --- کانال واقعی: پیامِ پاک‌شده --------------------------------------------


class _SentMessage:
    def __init__(self, message_id: int) -> None:
        self.id = message_id


class _FakeTelethonClient:
    """کلاینتی که فقط `send_message` را دارد و هر فراخوانی را ثبت می‌کند."""

    def __init__(self, *errors: Exception) -> None:
        self.calls: list[dict[str, Any]] = []
        self._errors = list(errors)

    async def send_message(self, chat_id: int, body: str, **kwargs: Any) -> _SentMessage:
        self.calls.append({"chat_id": chat_id, "body": body, **kwargs})
        if self._errors:
            raise self._errors.pop(0)
        return _SentMessage(500 + len(self.calls))


async def test_the_quote_reaches_telegram() -> None:
    client = _FakeTelethonClient()
    message_id = await TelethonChannel(client).send(700, "پاسخ", reply_to=42)

    assert message_id == 501
    assert client.calls == [{"chat_id": 700, "body": "پاسخ", "reply_to": 42}]


async def test_a_plain_send_does_not_quote() -> None:
    client = _FakeTelethonClient()
    await TelethonChannel(client).send(700, "پاسخ")
    assert client.calls[0].get("reply_to") is None


def _rpc(message: str) -> Exception:
    from telethon.errors import RPCError

    return RPCError(None, message, 400)


def _typed_message_id_invalid() -> Exception:
    from telethon.errors import MessageIdInvalidError

    return MessageIdInvalidError(request=None)


@pytest.mark.parametrize(
    "error",
    [_typed_message_id_invalid(), _rpc("REPLY_MESSAGE_ID_INVALID"), _rpc("MESSAGE_ID_INVALID")],
    ids=["typed", "reply-message-id-invalid", "message-id-invalid"],
)
async def test_a_deleted_target_falls_back_to_a_plain_message(error: Exception) -> None:
    """دانشجو پیامش را پاک کرده. پاسخ باید برود، فقط بدون نقل."""
    client = _FakeTelethonClient(error)

    message_id = await TelethonChannel(client).send(700, "پاسخ", reply_to=42)

    assert message_id == 502
    assert len(client.calls) == 2
    assert client.calls[0]["reply_to"] == 42
    assert client.calls[1].get("reply_to") is None, "تلاش دوم نباید دوباره نقل کند"


async def test_an_unrelated_rpc_error_is_not_retried() -> None:
    """هر خطای دیگر نتیجه‌اش نامعلوم است؛ دوباره فرستادن ممکن است پیام را دوبار برساند."""
    client = _FakeTelethonClient(_rpc("CHAT_WRITE_FORBIDDEN"))

    with pytest.raises(Exception, match="CHAT_WRITE_FORBIDDEN"):
        await TelethonChannel(client).send(700, "پاسخ", reply_to=42)

    assert len(client.calls) == 1


async def test_a_plain_send_never_retries_on_message_id_invalid() -> None:
    client = _FakeTelethonClient(_typed_message_id_invalid())

    with pytest.raises(Exception, match="message ID is invalid"):
        await TelethonChannel(client).send(700, "پاسخ")

    assert len(client.calls) == 1


async def test_flood_wait_on_the_fallback_is_still_a_flood_wait() -> None:
    from telethon.errors import FloodWaitError

    flood = FloodWaitError(request=None, capture=30)
    client = _FakeTelethonClient(_typed_message_id_invalid(), flood)

    with pytest.raises(FloodWait) as info:
        await TelethonChannel(client).send(700, "پاسخ", reply_to=42)
    assert info.value.seconds == 30


# --- پایگاه داده: آیا بعد از آن پیام، پیام تازه‌ای آمده؟ ----------------------


async def _record(
    session: AsyncSession,
    account: MentorAccount,
    message_id: int,
    *,
    sender: Sender = Sender.student,
    outgoing: bool = False,
) -> Message:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=700,
        message_id=message_id,
        sender_user_id=700,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text=f"پیام {message_id}",
        media_type=None,
        reply_to_message_id=None,
        sent_at=NOON + timedelta(seconds=message_id),
        is_private=True,
        is_outgoing=outgoing,
    )
    result = await record_inbound(session, account, inbound, sender=sender)
    await session.commit()
    assert result.message_id is not None
    return await session.get_one(Message, result.message_id)


async def _claim(session: AsyncSession, answered: Message) -> delivery.Claimed:
    await delivery.enqueue(
        session,
        conversation_id=answered.conversation_id,
        answered_message_id=answered.id,
        body="پاسخ",
    )
    await session.commit()
    claimed = await delivery.claim_next(session)
    await session.commit()
    assert claimed is not None
    return claimed


async def test_the_latest_message_has_no_newer_student_message(
    session: AsyncSession, account: MentorAccount
) -> None:
    answered = await _record(session, account, 42)
    claimed = await _claim(session, answered)

    assert claimed.newer_student_message is False


async def test_a_later_student_message_is_noticed(
    session: AsyncSession, account: MentorAccount
) -> None:
    answered = await _record(session, account, 42)
    await _record(session, account, 43)
    claimed = await _claim(session, answered)

    assert claimed.newer_student_message is True


async def test_only_student_messages_count_as_newer(
    session: AsyncSession, account: MentorAccount
) -> None:
    """پیام خودِ منتور یا دستیار بعد از آن، دلیل نقل نیست."""
    answered = await _record(session, account, 42)
    await _record(session, account, 43, sender=Sender.mentor, outgoing=True)
    claimed = await _claim(session, answered)

    assert claimed.newer_student_message is False


async def test_an_earlier_student_message_does_not_count(
    session: AsyncSession, account: MentorAccount
) -> None:
    await _record(session, account, 41)
    answered = await _record(session, account, 42)
    claimed = await _claim(session, answered)

    assert claimed.newer_student_message is False


# --- کارگر: از تنظیم تا پیام رفته -------------------------------------------


async def _deliver(
    session: AsyncSession,
    account: MentorAccount,
    monkeypatch: pytest.MonkeyPatch,
    *,
    mode: str | None,
    newer: bool,
    body: str = THREE,
) -> FakeChannel:
    if mode is None:
        monkeypatch.delenv("REPLY_QUOTE", raising=False)
    else:
        monkeypatch.setenv("REPLY_QUOTE", mode)
    get_settings.cache_clear()
    try:
        answered = await _record(session, account, 42)
        if newer:
            await _record(session, account, 43)
        await delivery.enqueue(
            session,
            conversation_id=answered.conversation_id,
            answered_message_id=answered.id,
            body=body,
        )
        await session.commit()
        async with session_scope() as claim_session:
            claimed = await delivery.claim_next(claim_session)
        assert claimed is not None

        channel = FakeChannel()
        status = await deliver_claimed(
            claimed,
            channels={account.slug: channel},
            gates={account.slug: _gate(quiet_start=0, quiet_end=0)},
            sleep=False,
        )
        assert status is SendStatus.sent
        return channel
    finally:
        get_settings.cache_clear()


async def test_default_quotes_the_first_part_of_the_answer(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    channel = await _deliver(session, account, monkeypatch, mode=None, newer=False)
    assert channel.quotes == [42, None, None]


async def test_off_never_quotes(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    channel = await _deliver(session, account, monkeypatch, mode="off", newer=True)
    assert channel.quotes == [None, None, None]


async def test_smart_quotes_only_when_a_newer_student_message_exists(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    channel = await _deliver(session, account, monkeypatch, mode="smart", newer=True)
    assert channel.quotes == [42, None, None]


async def test_smart_stays_plain_for_the_latest_message(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    channel = await _deliver(session, account, monkeypatch, mode="smart", newer=False)
    assert channel.quotes == [None, None, None]


async def test_the_recorded_answer_is_unchanged_by_quoting(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    """نقل فقط شکل ارسال است؛ متن ثبت‌شده و شمارش قطعه‌ها همان می‌ماند."""
    await _deliver(session, account, monkeypatch, mode="always", newer=False)
    session.expire_all()

    row = (await session.execute(text("select status, sent_parts from deliveries"))).one()
    assert (row.status, row.sent_parts) == ("sent", 3)
    assistant = (
        await session.execute(select(Message).where(Message.sender == Sender.assistant.value))
    ).scalar_one()
    assert assistant.text == THREE


def test_the_setting_rejects_unknown_values(monkeypatch: pytest.MonkeyPatch) -> None:
    from pydantic import ValidationError

    monkeypatch.setenv("REPLY_QUOTE", "sometimes")
    get_settings.cache_clear()
    try:
        with pytest.raises(ValidationError):
            get_settings()
    finally:
        monkeypatch.delenv("REPLY_QUOTE", raising=False)
        get_settings.cache_clear()


def test_the_default_is_always(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REPLY_QUOTE", raising=False)
    get_settings.cache_clear()
    try:
        assert get_settings().reply_quote == "always"
    finally:
        get_settings.cache_clear()

