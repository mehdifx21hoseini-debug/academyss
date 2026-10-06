"""ربات کنترل: همان جایی که منتور پاسخ‌ها را تأیید می‌کند.

`auth.py` جداگانه آزموده شده. آنچه اینجا آزموده می‌شود چیز دیگری است: **آیا خود
کنترل‌کننده‌ها آن بررسی‌ها را صدا می‌زنند؟** کنترل‌کننده‌ای که فراموش کند
`is_operator` را بپرسد، از همه‌ی تست‌های `auth.py` رد می‌شود و همچنان باز است —
و آن یعنی هر کسی که ربات را پیدا کند می‌تواند از حساب منتور به دانشجو پیام بدهد.

رویداد Telethon جعل می‌شود، چون سطحی که کنترل‌کننده‌ها لمس می‌کنند کوچک و مشخص
است: متن، فرستنده، گفتگو، و چند تابع پاسخ.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any

import pytest
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import drafts
from mentorai.ai.client import RawCall
from mentorai.config import get_settings
from mentorai.db.models import (
    AiRun,
    Conversation,
    ConversationStatus,
    Draft,
    MentorAccount,
    Message,
    Outcome,
    Sender,
)
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.safety import AccountGate, TokenBucket
from mentorai.telegram.store import record_inbound

OPERATOR = 555
STRANGER = 999
CONTROL_CHAT = 4242
NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)


class FakeEvent:
    """رویداد تلگرام، فقط با همان چیزی که کنترل‌کننده‌ها واقعاً لمس می‌کنند."""

    def __init__(
        self,
        *,
        text: str = "",
        sender_id: int | None = OPERATOR,
        chat_id: int = CONTROL_CHAT,
        data: bytes | None = None,
        reply_to: object | None = None,
    ) -> None:
        self.raw_text = text
        self.sender_id = sender_id
        self.chat_id = chat_id
        self.data = data
        self._reply_to = reply_to
        self.replies: list[str] = []
        self.edits: list[str] = []
        self.answers: list[tuple[str, bool]] = []

    async def reply(self, body: str, **_: Any) -> None:
        self.replies.append(body)

    async def edit(self, body: str, **_: Any) -> None:
        self.edits.append(body)

    async def answer(self, body: str = "", *, alert: bool = False) -> None:
        self.answers.append((body, alert))

    async def get_reply_message(self) -> object | None:
        return self._reply_to

    @property
    def said(self) -> str:
        return " ".join(self.replies + self.edits + [a for a, _ in self.answers])


class FakeControlMessage:
    def __init__(self, message_id: int) -> None:
        self.id = message_id


@pytest.fixture
def bot(monkeypatch: pytest.MonkeyPatch):  # type: ignore[no-untyped-def]
    """ربات واقعی، بدون اتصال به تلگرام."""
    import mentorai.control.bot as bot_module

    class _StubClient:
        def __init__(self, *a: object, **kw: object) -> None: ...

    monkeypatch.setattr(bot_module, "TelegramClient", _StubClient)
    monkeypatch.setenv("CONTROL_BOT_TOKEN", "test-token")
    monkeypatch.setenv("CONTROL_OPERATOR_IDS", str(OPERATOR))
    get_settings.cache_clear()

    gate = AccountGate(
        slug="mentor-a",
        bucket=TokenBucket(rate_per_minute=60, burst=5),
        # ساعت سکوت خاموش: این فایل درباره‌ی آن نیست و روشن بودنش تست را به ساعت
        # دیواری ماشین وابسته می‌کند.
        quiet_start=0,
        quiet_end=0,
        tz=UTC,
    )
    instance = bot_module.ControlBot(channels={"mentor-a": None}, gates={"mentor-a": gate})
    # ربات با کلاینت مدل، برای مسیر دستور کوتاه. همان دروازه و همان تنظیمات، تا
    # تفاوت دو تست فقط همان چیزی باشد که سنجیده می‌شود.
    instance.build_with_model = lambda client: bot_module.ControlBot(  # type: ignore[attr-defined]
        channels={"mentor-a": None}, gates={"mentor-a": gate}, model_client=client
    )
    yield instance
    get_settings.cache_clear()


@pytest.fixture
async def linked(session: AsyncSession, account: MentorAccount) -> MentorAccount:
    account.control_chat_id = CONTROL_CHAT
    await session.commit()
    return account


async def _conversation_with_draft(
    session: AsyncSession, account: MentorAccount
) -> tuple[Conversation, Draft]:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=700,
        message_id=1,
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
    stored = await record_inbound(session, account, inbound, sender=Sender.student)
    await session.flush()
    assert stored.message_id is not None
    run = AiRun(
        conversation_id=stored.conversation_id,
        message_id=stored.message_id,
        outcome=Outcome.answer.value,
        reason="answered",
        prompt_version="v1",
    )
    session.add(run)
    await session.flush()
    draft = await drafts.create(
        session,
        ai_run_id=run.id,
        conversation_id=stored.conversation_id,
        proposed_text="پاسخ پیشنهادی",
    )
    draft.control_message_id = 77
    await session.commit()
    conversation = await session.get_one(Conversation, stored.conversation_id)
    return conversation, draft


# ---------------------------------------------------------------------------
# مرز دسترسی — مهم‌ترین بخش
# ---------------------------------------------------------------------------


async def test_a_stranger_cannot_link_a_chat_to_an_account(
    session: AsyncSession, account: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """شکستی که می‌بندد: هر کسی که ربات را پیدا کند حساب آکادمی را در دست بگیرد.

    اگر `_on_link` بررسی اپراتور را فراموش کند، همه‌ی تست‌های `auth.py` همچنان
    سبز می‌مانند و این در باز است.
    """
    event = FakeEvent(text=f"/link {account.slug}", sender_id=STRANGER)
    await bot._on_link(event)

    await session.refresh(account)
    assert account.control_chat_id is None, "غریبه توانست گفتگو را به حساب وصل کند"


async def test_a_stranger_cannot_approve_a_draft(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """اگر این باز باشد، غریبه می‌تواند از حساب منتور به دانشجو پیام بفرستد."""
    _, draft = await _conversation_with_draft(session, linked)

    event = FakeEvent(data=f"approve:{draft.id}".encode(), sender_id=STRANGER)
    await bot._on_callback(event)

    await session.refresh(draft)
    assert draft.status == "pending", "پیش‌نویس با تأیید غریبه از حالت انتظار خارج شد"


async def test_an_operator_in_another_chat_cannot_act(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """اپراتور بودن کافی نیست؛ گفتگو هم باید همان گفتگوی وصل‌شده باشد.

    وگرنه اپراتوری که به یک حساب دسترسی دارد می‌تواند پیش‌نویس حساب دیگری را
    تأیید کند.
    """
    _, draft = await _conversation_with_draft(session, linked)

    event = FakeEvent(data=f"approve:{draft.id}".encode(), sender_id=OPERATOR, chat_id=1111)
    await bot._on_callback(event)

    await session.refresh(draft)
    assert draft.status == "pending"


async def test_unlink_from_a_different_chat_is_refused(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """وگرنه یک گفتگوی وصل‌شده می‌تواند اتصال حساب دیگری را قطع کند."""
    event = FakeEvent(text=f"/unlink {linked.slug}", sender_id=OPERATOR, chat_id=1111)
    await bot._on_unlink(event)

    await session.refresh(linked)
    assert linked.control_chat_id == CONTROL_CHAT, "اتصال از گفتگوی دیگری قطع شد"


async def test_pending_from_an_unlinked_chat_reveals_nothing(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    _, _ = await _conversation_with_draft(session, linked)

    event = FakeEvent(text="/pending", sender_id=OPERATOR, chat_id=1111)
    await bot._on_pending(event)

    assert "پاسخ پیشنهادی" not in event.said


# ---------------------------------------------------------------------------
# ورودی خراب
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "body",
    ["/link", "/link a b c", "/link "],
)
async def test_malformed_link_is_answered_not_crashed(body: str, bot) -> None:  # type: ignore[no-untyped-def]
    event = FakeEvent(text=body, sender_id=OPERATOR)
    await bot._on_link(event)
    assert event.said, "ورودی خراب بی‌پاسخ ماند"


async def test_link_to_an_unknown_account_does_not_reveal_whether_it_exists(
    session: AsyncSession, account: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """پاسخ برای حساب ناموجود و حساب موجود باید یکی باشد.

    وگرنه می‌شود با همین ربات فهرست slugهای واقعی را کشف کرد.
    """
    unknown = FakeEvent(text="/link does-not-exist", sender_id=OPERATOR)
    await bot._on_link(unknown)

    stranger = FakeEvent(text=f"/link {account.slug}", sender_id=STRANGER)
    await bot._on_link(stranger)

    assert unknown.said == stranger.said


@pytest.mark.parametrize("body", ["/resume", "/resume abc", "/resume 1 2"])
async def test_malformed_resume_is_answered_not_crashed(body: str, bot) -> None:  # type: ignore[no-untyped-def]
    event = FakeEvent(text=body, sender_id=OPERATOR)
    await bot._on_resume(event)
    assert event.said


async def test_a_callback_with_rubbish_data_is_ignored(bot) -> None:  # type: ignore[no-untyped-def]
    for payload in (b"", b"nonsense", b"approve:", b"approve:notanumber", b"delete:1"):
        event = FakeEvent(data=payload, sender_id=OPERATOR)
        await bot._on_callback(event)


# ---------------------------------------------------------------------------
# تصمیم تکراری
# ---------------------------------------------------------------------------


async def test_tapping_approve_twice_does_not_decide_twice(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """شکستی که می‌بندد: دو پیام یکسان برای دانشجو.

    دکمه در تلگرام می‌تواند دوبار زده شود — و در شبکه‌ی ضعیف اغلب می‌شود.
    """
    _, draft = await _conversation_with_draft(session, linked)
    draft_id = draft.id

    first = FakeEvent(data=f"reject:{draft_id}".encode(), sender_id=OPERATOR)
    await bot._on_callback(first)
    second = FakeEvent(data=f"reject:{draft_id}".encode(), sender_id=OPERATOR)
    await bot._on_callback(second)

    session.expire_all()
    stored = await session.get_one(Draft, draft_id)
    assert stored.status == "rejected"
    assert second.answers, "تصمیم دوم بی‌صدا پذیرفته شد"


async def test_rejecting_leaves_the_student_message_unanswered(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """رد کردن یعنی دانشجو چیزی نمی‌گیرد و پیامش خوانده‌نشده می‌ماند (ADR-009)."""
    _, draft = await _conversation_with_draft(session, linked)

    event = FakeEvent(data=f"reject:{draft.id}".encode(), sender_id=OPERATOR)
    await bot._on_callback(event)

    session.expire_all()
    sent = (
        await session.execute(
            text("select count(*) from messages where sender = 'assistant'")
        )
    ).scalar_one()
    assert sent == 0
    queued = (await session.execute(text("select count(*) from deliveries"))).scalar_one()
    assert queued == 0, "پیش‌نویس ردشده وارد صندوق خروج شد"


# ---------------------------------------------------------------------------
# بازگرداندن دستیار
# ---------------------------------------------------------------------------


async def test_resume_only_works_on_this_accounts_conversation(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """گفتگوی حساب دیگر نباید از این گفتگوی کنترلی قابل تغییر باشد."""
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
    foreign = Conversation(
        account_id=other.id,
        student_id=(await _conversation_with_draft(session, linked))[0].student_id,
        telegram_chat_id=888,
        status=ConversationStatus.awaiting_mentor.value,
    )
    session.add(foreign)
    await session.commit()

    # حمله‌ی واقعی: اپراتور شناسه‌ی گفتگوی تلگرامی حساب دیگر را می‌داند و همان را
    # می‌فرستد. محدودسازی باید روی `account_id` باشد، نه فقط روی وجود گفتگو.
    event = FakeEvent(text=f"/resume {foreign.telegram_chat_id}", sender_id=OPERATOR)
    await bot._on_resume(event)

    await session.refresh(foreign)
    assert foreign.status == ConversationStatus.awaiting_mentor.value


async def test_pending_lists_the_accounts_own_open_escalations(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    conversation, _ = await _conversation_with_draft(session, linked)
    message = (await session.execute(select(Message))).scalars().first()
    assert message is not None
    from mentorai.db.models import Escalation

    session.add(
        Escalation(
            conversation_id=conversation.id, message_id=message.id, reason="rule_money"
        )
    )
    await session.commit()

    event = FakeEvent(text="/pending", sender_id=OPERATOR)
    await bot._on_pending(event)

    assert str(conversation.telegram_chat_id) in event.said


# ---------------------------------------------------------------------------
# دستور کوتاه منتور
# ---------------------------------------------------------------------------


class _ExpandingClient:
    """کلاینت آزمایشی برای مسیر بسط. از `raw` استفاده می‌کند، نه `complete`."""

    model = "scripted-test-only"
    effort = "low"

    def __init__(self, answer: str | None = "متن کامل", *, error: str | None = None) -> None:
        self._answer = answer
        self._error = error
        self.calls: list[tuple[str, str]] = []

    async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> RawCall:
        self.calls.append((system, user))
        text = None if self._answer is None else json.dumps({"answer": self._answer})
        return RawCall(
            text=text,
            model=self.model,
            latency_ms=1,
            input_tokens=10,
            output_tokens=5,
            error=self._error,
        )

    async def complete(self, *, system: str, user: str) -> object:  # pragma: no cover
        raise AssertionError("مسیر بسط نباید complete را صدا بزند")


async def _instruct(
    bot,
    session: AsyncSession,
    linked: MentorAccount,
    text: str,
    *,
    client=None,
    sender=OPERATOR,
    chat=CONTROL_CHAT,
):  # type: ignore[no-untyped-def]
    _, draft = await _conversation_with_draft(session, linked)
    event = FakeEvent(text=text, sender_id=sender, chat_id=chat, reply_to=FakeControlMessage(77))
    instance = bot.build_with_model(client) if client is not None else bot
    await instance._on_reply(event)
    return event, draft


async def test_a_stranger_cannot_expand_an_instruction(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """مهم‌ترین تست این مسیر. دستور کوتاه یک راه تازه برای نوشتن از طرف منتور است.

    اگر اجازه چک نشود، هر کسی که ربات را پیدا کند می‌تواند متنی بسازد که از حساب
    منتور به دانشجو می‌رود.
    """
    client = _ExpandingClient()
    event, draft = await _instruct(
        bot, session, linked, "+ بگو از ویدیو ۱۰ شروع کنه", client=client, sender=STRANGER
    )

    assert client.calls == [], "برای غریبه مدل صدا زده شد"
    await session.refresh(draft)
    assert draft.proposed_text == "پاسخ پیشنهادی", "غریبه پیش‌نویس را عوض کرد"


async def test_an_operator_in_the_wrong_chat_cannot_expand(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """اپراتور بودن کافی نیست: گفتگو هم باید همان گفتگوی وصل‌شده باشد."""
    client = _ExpandingClient()
    event, draft = await _instruct(
        bot, session, linked, "+ بگو صبر کنه", client=client, chat=1111
    )

    assert client.calls == []
    await session.refresh(draft)
    assert draft.proposed_text == "پاسخ پیشنهادی"


async def test_an_instruction_is_expanded_and_comes_back_for_approval(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """شکستی که می‌بندد: منتور مجبور باشد کل متن را خودش تایپ کند.

    و نکته‌ی اصلی این مسیر: بسط دادن **ارسال نیست**. متن جای پیش‌نویس می‌نشیند و
    منتور همان‌طور که قبلاً تأیید می‌کرد تأیید می‌کند — آدم از مدار بیرون نمی‌رود.
    """
    client = _ExpandingClient("سلام وقتتون بخیر.\n\nاز ویدیوی دهم شروع کنید.")
    event, draft = await _instruct(
        bot, session, linked, "+ بگو از ویدیو ۱۰ شروع کنه", client=client
    )

    assert len(client.calls) == 1, "مدل یک بار صدا زده نشد"
    _, user = client.calls[0]
    assert "بگو از ویدیو ۱۰ شروع کنه" in user, "دستور منتور به مدل نرسید"

    await session.refresh(draft)
    assert draft.proposed_text == "سلام وقتتون بخیر.\n\nاز ویدیوی دهم شروع کنید."
    assert draft.status == drafts.DraftStatus.pending.value, "بسط، پیش‌نویس را نهایی کرد"
    assert draft.final_text is None, "بسط به‌جای پیشنهاد، تصمیم ثبت کرد"
    assert draft.decided_by is None, "بسط تصمیم‌گیرنده ثبت کرد"
    assert "تأیید" in event.said or "نوشتم" in event.said


async def test_an_empty_instruction_asks_for_one_without_calling_the_model(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    client = _ExpandingClient()
    event, _ = await _instruct(bot, session, linked, "+", client=client)

    assert client.calls == [], "برای دستور خالی مدل صدا زده شد"
    assert "بنویسید چه بگوید" in event.said


async def test_the_path_says_so_when_it_is_not_configured(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """بی کلاینت مدل، مسیر خاموش است — ولی بی‌صدا نه.

    سکوت اینجا یعنی منتور فکر می‌کند دستورش رفته و منتظر می‌ماند.
    """
    event, draft = await _instruct(bot, session, linked, "+ بگو صبر کنه")

    assert "فعال نیست" in event.said
    await session.refresh(draft)
    assert draft.proposed_text == "پاسخ پیشنهادی"


async def test_a_model_failure_leaves_the_draft_untouched(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """جهت شکست به سمت منتور: پیش‌نویس قبلی می‌ماند و خودش خبر می‌گیرد."""
    client = _ExpandingClient(None, error="timeout")
    event, draft = await _instruct(bot, session, linked, "+ بگو صبر کنه", client=client)

    assert "نشد" in event.said
    await session.refresh(draft)
    assert draft.proposed_text == "پاسخ پیشنهادی"


async def test_a_number_the_mentor_did_not_say_is_blocked(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """محافظ قیمت در این مسیر هم هست.

    دستور منتور درباره‌ی قیمت نبود و مدل عددی اضافه کرد. همان قاعده‌ی همیشگی:
    قیمتی که آکادمی نگفته، نمی‌رود.
    """
    client = _ExpandingClient("دوره شهریه‌اش ۹۰۰ هزار تومان است.")
    event, draft = await _instruct(
        bot, session, linked, "+ بگو دوره پانزده جلسه داره", client=client
    )

    assert "رد شد" in event.said
    await session.refresh(draft)
    assert draft.proposed_text == "پاسخ پیشنهادی", "متن با عدد ساختگی جای پیش‌نویس نشست"


async def test_a_number_the_mentor_did_say_goes_through(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """نیمه‌ی دیگر: محافظ نباید خودِ منتور را سانسور کند.

    او آدمِ آکادمی است؛ وقتی قیمت می‌گوید، همان اعلام رسمی است.
    """
    client = _ExpandingClient("شهریه دوره ۸۰۰ هزار تومان است.")
    event, draft = await _instruct(
        bot, session, linked, "+ بگو شهریه ۸۰۰ هزار تومانه", client=client
    )

    await session.refresh(draft)
    assert draft.proposed_text == "شهریه دوره ۸۰۰ هزار تومان است.", event.said


async def test_the_expansion_is_counted_against_the_model_budget(
    session: AsyncSession, linked: MentorAccount, bot
) -> None:  # type: ignore[no-untyped-def]
    """هر فراخوانی مدل پول است و باید به سقف بخورد، وگرنه سقف دور زده می‌شود."""
    client = _ExpandingClient("متن کامل")
    await _instruct(bot, session, linked, "+ بگو صبر کنه", client=client)

    rows = (
        await session.execute(
            text("select count(*) from model_usage where purpose = 'instruction_expansion'")
        )
    ).scalar_one()
    assert rows == 1


async def test_a_plain_reply_still_sends_the_mentor_text_verbatim(
    session: AsyncSession, linked: MentorAccount, bot, monkeypatch: pytest.MonkeyPatch
) -> None:  # type: ignore[no-untyped-def]
    """رفتار پیشین دست‌نخورده: ریپلای بی‌پیشوند یعنی «عیناً همین را بفرست»."""
    import mentorai.control.bot as bot_module

    sent: list[int] = []

    async def _fake_send(draft_id: int, **_: object) -> str:
        sent.append(draft_id)
        return "sent"

    monkeypatch.setattr(bot_module, "send_draft_now", _fake_send)
    client = _ExpandingClient()
    event, draft = await _instruct(
        bot, session, linked, "متن دستی خود منتور", client=client
    )

    assert client.calls == [], "ریپلای ساده نباید مدل را صدا بزند"
    assert sent == [draft.id]
    await session.refresh(draft)
    # ریپلای ساده یک **تصمیم** است: متن در `final_text` می‌نشیند و پیش‌نویس
    # `edited` می‌شود. این همان تفاوتی است که `repropose` از آن دوری می‌کند.
    assert draft.final_text == "متن دستی خود منتور"
    assert draft.status == drafts.DraftStatus.edited.value
