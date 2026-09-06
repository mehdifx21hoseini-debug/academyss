"""دروازه: ثبت پیام و تصمیم درباره‌ی کارهایی که ساخته می‌شوند.

این تنها ورودی کل سیستم است و تا امروز هیچ تستی نداشت — یعنی اولین پیام واقعی
تلگرام، اولین اجرای این کد بود.

منطق ثبت از کنترل‌کننده‌ی رویداد Telethon جدا شده (`persist`)، پس اینجا بدون شبکه
و بدون جعل کردن شیء رویداد آزموده می‌شود. تبدیل رویداد تلگرام به پیام دامنه جدا و
در `test_normalize.py` آزموده می‌شود.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from telethon.sessions import StringSession

from mentorai.ai import budget
from mentorai.ai.client import RawCall
from mentorai.conversation import escalate
from mentorai.db.crypto import encrypt_session
from mentorai.db.models import (
    Conversation,
    DuplicateDelivery,
    Escalation,
    MentorAccount,
    Message,
    MessageMedia,
    ModelUsage,
    Sender,
)
from mentorai.media.extract import Extraction
from mentorai.memory import job as memory_job
from mentorai.telegram.gateway import AccountGateway, _Attachment
from mentorai.telegram.normalize import InboundMessage, build_inbound

ANSWER_JOB = "answer_message"


@pytest.fixture
async def gateway(session: AsyncSession, account: MentorAccount) -> AccountGateway:
    """دروازه‌ی واقعی، با نشستی که هرگز وصل نمی‌شود."""
    account.session_encrypted = encrypt_session(StringSession().save())
    await session.commit()
    return AccountGateway(account)


def _inbound(
    account: MentorAccount,
    *,
    message_id: int,
    text: str | None = "سلام",
    outgoing: bool = False,
    chat_id: int = 700,
    media_type: str | None = None,
) -> InboundMessage:
    return build_inbound(
        account_slug=account.slug,
        chat_id=chat_id,
        message_id=message_id,
        sender_user_id=700,
        username="student",
        first_name="دانشجو",
        last_name=None,
        raw_text=text,
        media_type=media_type,
        reply_to_message_id=None,
        sent_at=datetime(2026, 9, 2, 12, 0, tzinfo=UTC),
        is_private=True,
        is_outgoing=outgoing,
    )


# ---------------------------------------------------------------------------
# مسیر عادی
# ---------------------------------------------------------------------------


async def test_a_student_message_is_stored_and_queued_for_an_answer(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    await gateway.persist(_inbound(account, message_id=1))

    stored = list((await session.execute(select(Message))).scalars())
    assert len(stored) == 1
    assert stored[0].sender == Sender.student.value

    kinds = await _job_kinds(session)
    assert ANSWER_JOB in kinds


async def test_a_mentor_message_hands_the_conversation_over_and_queues_nothing(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    """پیام خود منتور روشن‌ترین نشانه‌ی در دست گرفتن مکالمه است.

    اگر دستیار بعد از آن باز هم جواب بسازد، وسط حرف منتور می‌پرد.
    """
    await gateway.persist(_inbound(account, message_id=1, text="من جواب می‌دم", outgoing=True))

    conversation = (await session.execute(select(Conversation))).scalar_one()
    assert conversation.status != "active"
    assert ANSWER_JOB not in await _job_kinds(session)


async def test_an_escalated_conversation_produces_no_answer_job(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    """مکالمه‌ای که به منتور سپرده شده تا فعال‌سازی صریح هیچ کاری تولید نمی‌کند."""
    await gateway.persist(_inbound(account, message_id=1))
    conversation = (await session.execute(select(Conversation))).scalar_one()
    escalate(conversation)
    await session.commit()

    await gateway.persist(_inbound(account, message_id=2, text="سؤال دوم"))

    answers = [k for k in await _job_kinds(session) if k == ANSWER_JOB]
    assert len(answers) == 1, "برای مکالمه‌ی سپرده‌شده کار تازه ساخته شد"


# ---------------------------------------------------------------------------
# پیام تکراری
# ---------------------------------------------------------------------------


async def test_the_same_message_twice_is_stored_once_and_answered_once(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    """تحویل دوباره‌ی یک به‌روزرسانی نباید پاسخ دوم بسازد.

    تلگرام همان به‌روزرسانی را بعد از قطعی اتصال دوباره می‌فرستد. بدون این، دانشجو
    دو جواب می‌گیرد و هزینه‌ی مدل هم دو برابر می‌شود.
    """
    inbound = _inbound(account, message_id=42)
    await gateway.persist(inbound)
    await gateway.persist(inbound)

    assert (await session.execute(select(func.count(Message.id)))).scalar_one() == 1
    answers = [k for k in await _job_kinds(session) if k == ANSWER_JOB]
    assert len(answers) == 1

    duplicates = (
        await session.execute(select(func.count(DuplicateDelivery.id)))
    ).scalar_one()
    assert duplicates == 1, "تکرار بی‌صدا دور انداخته شد و شمرده نشد"


# ---------------------------------------------------------------------------
# حافظه‌ی بلندمدت (ADR-027)
# ---------------------------------------------------------------------------


async def test_memory_extraction_is_queued_every_fifth_student_message(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    """شکستی که این تست می‌بندد: حافظه‌ای که هرگز نوشته نمی‌شود.

    پیش از ADR-027 این کار هیچ‌جا در صف گذاشته نمی‌شد. کل زیرسیستم حافظه — جدول،
    سیاست، کنترل‌کننده‌ی کارگر — وجود داشت و هیچ‌وقت اجرا نمی‌شد، در حالی که README
    وجودش را اعلام کرده بود.
    """
    for i in range(1, 5):
        await gateway.persist(_inbound(account, message_id=i, text=f"پیام {i}"))
    assert memory_job.JOB_KIND not in await _job_kinds(session), "زودتر از پنجمین پیام ساخته شد"

    await gateway.persist(_inbound(account, message_id=5, text="پیام ۵"))
    assert memory_job.JOB_KIND in await _job_kinds(session)


async def test_memory_extraction_runs_even_when_the_mentor_has_taken_over(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    """واقعیت‌های دانشجو در مکالمه‌ای که منتور در دستش دارد هم گفته می‌شوند.

    `recent_turns` عمداً پیام منتور را هم برچسب می‌زند، پس استخراج نباید به فعال
    بودن دستیار گره بخورد.
    """
    await gateway.persist(_inbound(account, message_id=1))
    conversation = (await session.execute(select(Conversation))).scalar_one()
    escalate(conversation)
    await session.commit()

    for i in range(2, 6):
        await gateway.persist(_inbound(account, message_id=i, text=f"پیام {i}"))

    assert memory_job.JOB_KIND in await _job_kinds(session)


# ---------------------------------------------------------------------------
# فایل پیوست
# ---------------------------------------------------------------------------


async def test_an_attachment_is_recorded_against_the_message(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    attachment = _Attachment(
        extraction=Extraction(kind="plan", text="پلن معاملاتی"),
        mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        size_bytes=1234,
        sha256="a" * 64,
    )
    await gateway.persist(_inbound(account, message_id=1, media_type="document"), attachment)

    media = (await session.execute(select(MessageMedia))).scalar_one()
    assert media.kind == "plan"
    assert media.extracted_text == "پلن معاملاتی"


async def test_image_description_spend_is_recorded_even_for_a_duplicate(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    """پول توصیف تصویر پیش از تشخیص تکراری خرج شده است.

    اگر فقط برای پیام‌های تازه ثبت شود، خرج تحویل‌های تکراری از سقف پنهان می‌ماند.
    """
    attachment = _Attachment(
        extraction=Extraction(kind="image", text="نمودار"),
        mime="image/jpeg",
        size_bytes=999,
        sha256="b" * 64,
        model_call=RawCall(
            text="نمودار", model="claude-opus-5", latency_ms=10, input_tokens=100, output_tokens=20
        ),
    )
    inbound = _inbound(account, message_id=7, media_type="photo")
    await gateway.persist(inbound, attachment)
    await gateway.persist(inbound, attachment)

    rows = list((await session.execute(select(ModelUsage))).scalars())
    assert len(rows) == 2, "خرج تحویل تکراری شمرده نشد"
    assert all(r.purpose == budget.Purpose.image_description.value for r in rows)


# ---------------------------------------------------------------------------
# استثنا
# ---------------------------------------------------------------------------


async def test_a_mentor_message_closes_open_escalations(
    session: AsyncSession, account: MentorAccount, gateway: AccountGateway
) -> None:
    await gateway.persist(_inbound(account, message_id=1))
    conversation = (await session.execute(select(Conversation))).scalar_one()
    first = (await session.execute(select(Message))).scalar_one()
    session.add(
        Escalation(conversation_id=conversation.id, message_id=first.id, reason="rule_money")
    )
    escalate(conversation)
    await session.commit()

    await gateway.persist(_inbound(account, message_id=2, text="رسیدگی کردم", outgoing=True))

    open_left = (
        await session.execute(
            select(func.count(Escalation.id)).where(Escalation.resolved_at.is_(None))
        )
    ).scalar_one()
    assert open_left == 0


async def _job_kinds(session: AsyncSession) -> list[str]:
    from sqlalchemy import text as sql

    rows = await session.execute(sql("select kind from jobs order by id"))
    return [r[0] for r in rows.all()]
