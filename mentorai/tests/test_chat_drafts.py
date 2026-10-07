"""پیش‌نویس داخل کادر نوشتن خود گفتگو (ADR-036).

چهار تضمین، هر کدام با آزمونی که اگر کد خراب شود می‌شکند:

1. **چیزی ارسال نمی‌شود.** سیستم فقط متن را در پیش‌نویس ابری می‌گذارد.
2. **متن منتور هیچ‌وقت پاک نمی‌شود.** اگر منتور همان لحظه در کادر چیزی نوشته باشد،
   پیش‌نویس گذاشته نمی‌شود.
3. **تصمیم منتور همان پیامی است که می‌فرستد.** همان متن یا ویرایش‌شده‌اش یعنی پذیرفتن
   پیشنهاد و دستیار کنار نمی‌رود؛ متن کاملاً متفاوت یعنی منتور خودش گفتگو را گرفته.
4. **کنار گذاشتن سیستم، رد منتور نیست.** آمار رد و تأیید (شرط خروج ADR-010) دست‌نخورده
   می‌ماند.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from telethon.errors import FloodWaitError
from telethon.sessions import StringSession

from mentorai import drafts
from mentorai.config import get_settings
from mentorai.db.crypto import encrypt_session
from mentorai.db.models import (
    AiRun,
    Conversation,
    Draft,
    DraftDelivery,
    DraftStatus,
    MentorAccount,
    Message,
    Student,
)
from mentorai.health import _rates
from mentorai.telegram.chat_draft import ChatDraftNotifier, choose_notifier
from mentorai.telegram.gateway import AccountGateway
from mentorai.telegram.normalize import InboundMessage, build_inbound

CHAT = 700
PROPOSED = "دوره مقدماتی شانزده جلسه دارد و هر جلسه حدود یک ساعت است."


def _now() -> datetime:
    return datetime.now(UTC)


# ---------------------------------------------------------------------------
# ساختن داده
# ---------------------------------------------------------------------------


@pytest.fixture
async def conversation(session: AsyncSession, account: MentorAccount) -> Conversation:
    student = Student(display_name="دانشجو")
    session.add(student)
    await session.flush()
    convo = Conversation(account_id=account.id, student_id=student.id, telegram_chat_id=CHAT)
    session.add(convo)
    await session.commit()
    return convo


async def _draft(
    session: AsyncSession,
    conversation: Conversation,
    n: int,
    body: str = PROPOSED,
    delivery: DraftDelivery = DraftDelivery.chat,
) -> Draft:
    """پیام شماره‌ی n، اجرای مدل برای آن، و پیش‌نویسش."""
    message = Message(
        conversation_id=conversation.id,
        telegram_message_id=n,
        sender="student",
        text="سؤال",
        sent_at=_now(),
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
    draft = await drafts.create(
        session,
        ai_run_id=run.id,
        conversation_id=conversation.id,
        proposed_text=body,
        delivery=delivery,
    )
    await session.commit()
    return draft


# ---------------------------------------------------------------------------
# ۱. تشخیص اینکه منتور چه فرستاد
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("sent", "expected"),
    [
        (PROPOSED, drafts.ChatOutcome.approved),
        # فقط فاصله، نیم‌فاصله و حروف عربی فرق دارند؛ همان متن است.
        ("دوره  مقدماتی شانزده جلسه دارد و هر جلسه حدود يك ساعت است.", drafts.ChatOutcome.approved),
        # ویرایش کوچک: یک عبارت اضافه شد.
        (PROPOSED + " اگر سؤال دیگری دارید بپرسید.", drafts.ChatOutcome.edited),
        ("دوره مقدماتی شانزده جلسه دارد.", drafts.ChatOutcome.edited),
        # یک جمله‌ی کاملاً دیگر.
        ("سلام، الان می‌آیم و خودم جواب می‌دهم", drafts.ChatOutcome.different),
        # پیام بدون متن (مثلاً عکس بدون عنوان).
        ("", drafts.ChatOutcome.different),
    ],
)
def test_what_the_mentor_sent_is_classified_against_the_draft(
    sent: str, expected: drafts.ChatOutcome
) -> None:
    assert drafts.classify_sent(PROPOSED, sent) is expected


# ---------------------------------------------------------------------------
# ۲. تصمیم از روی پیام منتور
# ---------------------------------------------------------------------------


async def test_the_same_text_approves_the_draft_and_the_assistant_stays(
    session: AsyncSession, conversation: Conversation
) -> None:
    draft = await _draft(session, conversation, 1)

    resolution = await drafts.resolve_from_chat(session, conversation.id, PROPOSED, sent_at=_now())
    await session.commit()

    assert resolution is not None
    assert resolution.outcome is drafts.ChatOutcome.approved
    assert not resolution.took_over
    await session.refresh(draft)
    assert draft.status == DraftStatus.approved.value
    assert draft.decided_by == "mentor:chat"
    assert draft.final_text == PROPOSED


async def test_an_edited_text_is_recorded_as_an_edit_and_keeps_both_versions(
    session: AsyncSession, conversation: Conversation
) -> None:
    """نسبت ویرایش به تأیید همان عددی است که شرط خروج از حالت پیش‌نویس را می‌سازد."""
    draft = await _draft(session, conversation, 1)
    edited = "دوره مقدماتی شانزده جلسه دارد."

    resolution = await drafts.resolve_from_chat(session, conversation.id, edited, sent_at=_now())
    await session.commit()

    assert resolution is not None and not resolution.took_over
    await session.refresh(draft)
    assert draft.status == DraftStatus.edited.value
    assert draft.final_text == edited
    assert draft.proposed_text == PROPOSED


async def test_a_different_message_withdraws_the_draft_and_counts_as_taking_over(
    session: AsyncSession, conversation: Conversation
) -> None:
    draft = await _draft(session, conversation, 1)

    resolution = await drafts.resolve_from_chat(
        session, conversation.id, "سلام، خودم الان جواب می‌دهم", sent_at=_now()
    )
    await session.commit()

    assert resolution is not None and resolution.took_over
    await session.refresh(draft)
    # رد (rejected) نیست: رد تصمیم منتور درباره‌ی «پیشنهاد» است و در آمار می‌شمارد.
    assert draft.status == DraftStatus.withdrawn.value
    assert draft.decided_by == "system:mentor_wrote_other"


async def test_no_open_chat_draft_means_an_ordinary_mentor_message(
    session: AsyncSession, conversation: Conversation
) -> None:
    assert await drafts.resolve_from_chat(session, conversation.id, "سلام", sent_at=_now()) is None


async def test_a_control_bot_draft_is_never_resolved_from_the_chat(
    session: AsyncSession, conversation: Conversation
) -> None:
    """کارت ربات کنترل فقط با دکمه تصمیم می‌گیرد، نه با پیامی که منتور در گفتگو می‌فرستد."""
    draft = await _draft(session, conversation, 1, delivery=DraftDelivery.control_bot)

    resolved = await drafts.resolve_from_chat(session, conversation.id, PROPOSED, sent_at=_now())
    assert resolved is None
    await session.refresh(draft)
    assert draft.status == DraftStatus.pending.value


async def test_a_message_sent_before_the_draft_existed_is_not_an_answer_to_it(
    session: AsyncSession, conversation: Conversation
) -> None:
    draft = await _draft(session, conversation, 1)
    long_before = draft.created_at - timedelta(minutes=5)

    assert (
        await drafts.resolve_from_chat(session, conversation.id, PROPOSED, sent_at=long_before)
        is None
    )
    await session.refresh(draft)
    assert draft.status == DraftStatus.pending.value


async def test_a_second_message_resolves_nothing_once_the_draft_is_decided(
    session: AsyncSession, conversation: Conversation
) -> None:
    await _draft(session, conversation, 1)
    await drafts.resolve_from_chat(session, conversation.id, PROPOSED, sent_at=_now())
    await session.commit()

    assert (
        await drafts.resolve_from_chat(session, conversation.id, "پیام بعدی", sent_at=_now())
        is None
    )


# ---------------------------------------------------------------------------
# ۳. یک کادر برای هر گفتگو
# ---------------------------------------------------------------------------


async def test_a_newer_draft_replaces_the_open_one_without_counting_as_a_rejection(
    session: AsyncSession, conversation: Conversation
) -> None:
    first = await _draft(session, conversation, 1, "پاسخ اول")
    second = await _draft(session, conversation, 2, "پاسخ دوم")

    await session.refresh(first)
    await session.refresh(second)
    assert first.status == DraftStatus.withdrawn.value
    assert first.decided_by == "system:newer_draft"
    assert second.status == DraftStatus.pending.value
    rejected = (
        await session.execute(select(Draft).where(Draft.status == DraftStatus.rejected.value))
    ).all()
    assert rejected == []


async def test_a_new_chat_draft_leaves_another_conversations_draft_alone(
    session: AsyncSession, account: MentorAccount, conversation: Conversation
) -> None:
    other_student = Student(display_name="دانشجوی دیگر")
    session.add(other_student)
    await session.flush()
    other = Conversation(account_id=account.id, student_id=other_student.id, telegram_chat_id=701)
    session.add(other)
    await session.commit()

    theirs = await _draft(session, other, 1, "برای دیگری")
    await _draft(session, conversation, 2)

    await session.refresh(theirs)
    assert theirs.status == DraftStatus.pending.value


async def test_a_control_bot_draft_does_not_withdraw_the_chat_draft(
    session: AsyncSession, conversation: Conversation
) -> None:
    chat = await _draft(session, conversation, 1)
    await _draft(session, conversation, 2, delivery=DraftDelivery.control_bot)

    await session.refresh(chat)
    assert chat.status == DraftStatus.pending.value


async def test_withdrawing_a_decided_draft_changes_nothing(
    session: AsyncSession, conversation: Conversation
) -> None:
    draft = await _draft(session, conversation, 1)
    await drafts.approve(session, draft.id, by="mentor-a")
    await session.commit()

    assert await drafts.withdraw(session, draft.id, reason="x") is None
    await session.refresh(draft)
    assert draft.status == DraftStatus.approved.value


# ---------------------------------------------------------------------------
# ۴. دروازه: پیام خروجی منتور
# ---------------------------------------------------------------------------


@pytest.fixture
async def gateway(session: AsyncSession, account: MentorAccount) -> AccountGateway:
    account.session_encrypted = encrypt_session(StringSession().save())
    await session.commit()
    return AccountGateway(account)


def _inbound(
    account: MentorAccount, *, message_id: int, body: str, outgoing: bool
) -> InboundMessage:
    return build_inbound(
        account_slug=account.slug,
        chat_id=CHAT,
        message_id=message_id,
        sender_user_id=CHAT,
        username="student",
        first_name="دانشجو",
        last_name=None,
        raw_text=body,
        media_type=None,
        reply_to_message_id=None,
        sent_at=_now(),
        is_private=True,
        is_outgoing=outgoing,
    )


async def _conversation_after_student_message(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> Conversation:
    await gateway.persist(_inbound(account, message_id=1, body="سؤال", outgoing=False))
    return (await session.execute(select(Conversation))).scalar_one()


async def test_sending_the_draft_unchanged_does_not_make_the_assistant_step_aside(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    convo = await _conversation_after_student_message(session, account, gateway)
    draft = await _draft(session, convo, 50)

    await gateway.persist(_inbound(account, message_id=2, body=PROPOSED, outgoing=True))

    session.expire_all()
    convo = (await session.execute(select(Conversation))).scalar_one()
    assert convo.status == "active", "منتور پیشنهاد دستیار را فرستاد؛ این در دست گرفتن نیست"
    await session.refresh(draft)
    assert draft.status == DraftStatus.approved.value


async def test_sending_an_edited_draft_does_not_make_the_assistant_step_aside_either(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    convo = await _conversation_after_student_message(session, account, gateway)
    draft = await _draft(session, convo, 50)

    await gateway.persist(
        _inbound(account, message_id=2, body="دوره مقدماتی شانزده جلسه دارد.", outgoing=True)
    )

    session.expire_all()
    convo = (await session.execute(select(Conversation))).scalar_one()
    assert convo.status == "active"
    await session.refresh(draft)
    assert draft.status == DraftStatus.edited.value


async def test_writing_something_else_is_taking_over_as_before(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    convo = await _conversation_after_student_message(session, account, gateway)
    draft = await _draft(session, convo, 50)

    await gateway.persist(
        _inbound(account, message_id=2, body="سلام، خودم الان جواب می‌دهم", outgoing=True)
    )

    session.expire_all()
    convo = (await session.execute(select(Conversation))).scalar_one()
    assert convo.status != "active"
    await session.refresh(draft)
    assert draft.status == DraftStatus.withdrawn.value


async def test_a_mentor_message_without_any_draft_still_takes_over(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    await _conversation_after_student_message(session, account, gateway)

    await gateway.persist(_inbound(account, message_id=2, body="من جواب می‌دهم", outgoing=True))

    session.expire_all()
    convo = (await session.execute(select(Conversation))).scalar_one()
    assert convo.status != "active"


# ---------------------------------------------------------------------------
# ۵. نوشتن در کادر
# ---------------------------------------------------------------------------


class FakeTelegramDraft:
    def __init__(self, existing: str = "") -> None:
        self.raw_text = existing
        self.writes: list[dict[str, Any]] = []

    @property
    def is_empty(self) -> bool:
        return not self.raw_text

    async def set_message(self, text: str, **kwargs: Any) -> bool:
        self.writes.append({"text": text, **kwargs})
        self.raw_text = text
        return True


class FakeClient:
    """کلاینت سخت‌گیر: جز خواندن پیش‌نویس هر چیز دیگری صدا شود، آزمون می‌شکند.

    به‌ویژه هر متد ارسال (`send_message`، `send_file`، ...) یا علامت خواندن
    (`send_read_acknowledge`) یا نشانگر تایپ، که دانشجو می‌تواند ببیند.
    """

    def __init__(self, existing: str = "", *, fail: Exception | None = None) -> None:
        self.draft = FakeTelegramDraft(existing)
        self.asked: list[int] = []
        self._fail = fail

    async def get_drafts(self, chat_id: int) -> FakeTelegramDraft:
        self.asked.append(chat_id)
        if self._fail is not None:
            raise self._fail
        return self.draft

    def __getattr__(self, name: str) -> Any:
        raise AssertionError(f"نوشتن پیش‌نویس نباید {name} را صدا بزند")

    async def __call__(self, *args: Any, **kwargs: Any) -> Any:
        raise AssertionError("نوشتن پیش‌نویس نباید درخواست خام به تلگرام بفرستد")


def _notifier(client: Any) -> ChatDraftNotifier:
    return ChatDraftNotifier({"mentor-a": client})


async def test_the_text_is_written_into_the_chat_and_nothing_is_sent(
    session: AsyncSession, account: MentorAccount, conversation: Conversation
) -> None:
    draft = await _draft(session, conversation, 1)
    client = FakeClient()

    await _notifier(client).notify(account=account, draft=draft, question="")

    assert client.asked == [CHAT]
    assert [w["text"] for w in client.draft.writes] == [PROPOSED]
    # متن همان‌طور که هست: تبدیل مارک‌داون `*` و `_` را از پاسخ می‌خورد.
    assert client.draft.writes[0]["parse_mode"] is None
    # هنوز منتظر منتور است؛ سیستم هیچ تصمیمی نگرفته.
    await session.refresh(draft)
    assert draft.status == DraftStatus.pending.value


async def test_what_the_mentor_is_typing_is_never_overwritten(
    session: AsyncSession, account: MentorAccount, conversation: Conversation
) -> None:
    draft = await _draft(session, conversation, 1)
    client = FakeClient(existing="دارم برای این دانشجو یک چیزی می‌نویسم")

    await _notifier(client).notify(account=account, draft=draft, question="")

    assert client.draft.writes == []
    assert client.draft.raw_text == "دارم برای این دانشجو یک چیزی می‌نویسم"
    await session.refresh(draft)
    assert draft.status == DraftStatus.withdrawn.value
    assert draft.decided_by == "system:chat_occupied"


async def test_our_own_unsent_earlier_draft_may_be_replaced(
    session: AsyncSession, account: MentorAccount, conversation: Conversation
) -> None:
    await _draft(session, conversation, 1, "پاسخ اولِ نفرستاده")
    second = await _draft(session, conversation, 2, "پاسخ دوم")
    client = FakeClient(existing="پاسخ اولِ نفرستاده")

    await _notifier(client).notify(account=account, draft=second, question="")

    assert [w["text"] for w in client.draft.writes] == ["پاسخ دوم"]


@pytest.mark.parametrize(
    ("failure", "reason"),
    [
        (FloodWaitError(request=None, capture=30), "flood_wait"),
        (ValueError("Could not find the input entity"), "telegram_error"),
    ],
)
async def test_a_telegram_failure_withdraws_the_draft_and_does_not_raise(
    session: AsyncSession,
    account: MentorAccount,
    conversation: Conversation,
    failure: Exception,
    reason: str,
) -> None:
    draft = await _draft(session, conversation, 1)
    client = FakeClient(fail=failure)

    await _notifier(client).notify(account=account, draft=draft, question="")

    await session.refresh(draft)
    assert draft.status == DraftStatus.withdrawn.value
    assert draft.decided_by == f"system:{reason}"


async def test_an_account_without_a_client_withdraws_the_draft(
    session: AsyncSession, account: MentorAccount, conversation: Conversation
) -> None:
    draft = await _draft(session, conversation, 1)

    await ChatDraftNotifier({}).notify(account=account, draft=draft, question="")

    await session.refresh(draft)
    assert draft.status == DraftStatus.withdrawn.value


async def test_a_draft_already_decided_is_not_written(
    session: AsyncSession, account: MentorAccount, conversation: Conversation
) -> None:
    """منتور در فاصله‌ی ساخت تا نوشتن خودش جواب داده؛ نوشتن بعدی بی‌معنی است."""
    draft = await _draft(session, conversation, 1)
    await drafts.withdraw(session, draft.id, reason="mentor_wrote_other")
    await session.commit()
    client = FakeClient()

    await _notifier(client).notify(account=account, draft=draft, question="")

    assert client.draft.writes == []


async def test_a_control_bot_draft_is_ignored_by_the_chat_notifier(
    session: AsyncSession, account: MentorAccount, conversation: Conversation
) -> None:
    draft = await _draft(session, conversation, 1, delivery=DraftDelivery.control_bot)
    client = FakeClient()

    await _notifier(client).notify(account=account, draft=draft, question="")

    assert client.asked == [] and client.draft.writes == []


# ---------------------------------------------------------------------------
# ۶. انتخاب محل تحویل
# ---------------------------------------------------------------------------


def test_the_setting_chooses_the_notifier() -> None:
    bot = object()

    assert choose_notifier("control_bot", bot, {}) is bot  # type: ignore[arg-type]
    assert isinstance(choose_notifier("chat", bot, {}), ChatDraftNotifier)  # type: ignore[arg-type]
    # بدون ربات هم حالت chat کار می‌کند.
    assert isinstance(choose_notifier("chat", None, {}), ChatDraftNotifier)
    assert choose_notifier("control_bot", None, {}) is None


def test_the_delivery_setting_defaults_to_the_control_bot_and_rejects_nonsense(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("DRAFT_DELIVERY", raising=False)
    get_settings.cache_clear()
    assert get_settings().draft_delivery == "control_bot"

    monkeypatch.setenv("DRAFT_DELIVERY", "telegram")
    get_settings.cache_clear()
    with pytest.raises(ValueError, match="draft_delivery"):
        get_settings()
    get_settings.cache_clear()


# ---------------------------------------------------------------------------
# ۷. قیدهای پایگاه داده
# ---------------------------------------------------------------------------


async def test_the_database_accepts_withdrawn_and_chat_and_rejects_unknown_values(
    session: AsyncSession, conversation: Conversation
) -> None:
    draft_id = (await _draft(session, conversation, 1)).id

    # مقدار مجاز تازه
    await session.execute(
        text("update drafts set status = 'withdrawn' where id = :i"), {"i": draft_id}
    )
    await session.commit()

    for column, bad in (("status", "vanished"), ("delivery", "carrier_pigeon")):
        with pytest.raises(IntegrityError):
            await session.execute(
                text(f"update drafts set {column} = :v where id = :i"), {"v": bad, "i": draft_id}
            )
        await session.rollback()


async def test_a_draft_created_the_old_way_is_a_control_bot_draft(
    session: AsyncSession, conversation: Conversation
) -> None:
    """پیش‌نویس‌های موجود و مسیر قدیمی بدون هیچ تغییری همان رفتار قبلی را دارند."""
    message = Message(
        conversation_id=conversation.id,
        telegram_message_id=9,
        sender="student",
        text="سؤال",
        sent_at=_now(),
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

    draft = await drafts.create(
        session, ai_run_id=run.id, conversation_id=conversation.id, proposed_text="پاسخ"
    )
    await session.commit()

    assert draft.delivery == DraftDelivery.control_bot.value


async def test_chat_approvals_count_as_decisions_in_the_rejection_rate(
    session: AsyncSession, conversation: Conversation
) -> None:
    """پیش‌نویس داخل گفتگو `approved` می‌ماند؛ شمرده نشود، نرخ رد بزرگ‌تر از واقع می‌شود."""
    first = await _draft(session, conversation, 1, "یک")
    await drafts.approve(session, first.id, by="mentor:chat")
    second = await _draft(session, conversation, 2, "دو")
    await drafts.edit(session, second.id, by="mentor:chat", body="دو ویرایش")
    third = await _draft(session, conversation, 3, "سه")
    await drafts.reject(session, third.id, by="mentor-a")
    await session.commit()

    rates = await _rates(session)

    assert rates["draft_rejection_rate"] == round(1 / 3, 3)
