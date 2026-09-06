"""ارجاع به منتور و بازگشت دستیار.

دو نوع سکوت وجود دارد و تفکیکشان مهم است:

**سکوت موردی.** دستیار نتوانست همین یک پیام را جواب بدهد — منبعی نبود، اطمینان کافی
نبود، مدل خطا داد. مکالمه فعال می‌ماند و پیام بعدی دوباره تلاش می‌شود. اگر هر بار
نتوانستن باعث توقف کل مکالمه شود، دستیار خیلی زود از کار می‌افتد.

**سپردن مکالمه.** موضوع از آن‌هایی است که اصلاً کار دستیار نیست — پول، شکایت، حساب
کاربری، یا درخواست صریح منتور. اینجا پیام بعدی هم کار دستیار نیست، پس کل مکالمه به
منتور سپرده می‌شود تا صریحاً برگردانده شود.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.conversation import escalate, resume
from mentorai.db.models import (
    AuditLog,
    Conversation,
    ConversationStatus,
    Escalation,
    Message,
    Sender,
)

# دلایلی که کل مکالمه را به منتور می‌سپارند. بقیه‌ی دلایل سکوت موردی‌اند.
HANDOFF_REASONS = frozenset(
    {
        "rule_explicit_human_request",
        "rule_money",
        "rule_complaint",
        "rule_account",
    }
)

# اگر از آخرین پیام منتور این‌قدر گذشته باشد، دستیار خودش برمی‌گردد.
# بدون این، هر مکالمه‌ای که یک‌بار سپرده شد برای همیشه سپرده می‌ماند.
DEFAULT_RESUME_AFTER = timedelta(hours=12)


def is_handoff(reason: str) -> bool:
    return reason in HANDOFF_REASONS


async def hand_off(session: AsyncSession, conversation: Conversation, *, reason: str) -> bool:
    """مکالمه را به منتور بسپار. True یعنی وضعیت واقعاً عوض شد."""
    if ConversationStatus(conversation.status) is not ConversationStatus.active:
        return False
    escalate(conversation)
    session.add(
        AuditLog(
            actor="system",
            action="hand_off",
            target=str(conversation.id),
            detail=reason,
        )
    )
    return True


async def last_mentor_message_at(session: AsyncSession, conversation_id: int) -> datetime | None:
    return (
        await session.execute(
            select(func.max(Message.sent_at)).where(
                Message.conversation_id == conversation_id,
                Message.sender == Sender.mentor.value,
            )
        )
    ).scalar_one_or_none()


async def resolve_open(session: AsyncSession, conversation_id: int, *, by: str) -> int:
    """ارجاع‌های باز این مکالمه را بسته اعلام کن.

    زمان بسته شدن همان چیزی است که «چقدر دانشجو منتظر ماند» را قابل اندازه‌گیری می‌کند؛
    چون ارجاع برای دانشجو نامرئی است، بدون این عدد هیچ راهی برای دیدنش نیست.
    """
    result = await session.execute(
        update(Escalation)
        .where(Escalation.conversation_id == conversation_id, Escalation.resolved_at.is_(None))
        .values(resolved_at=func.now(), resolved_by=by)
        .returning(Escalation.id)
    )
    return len(result.fetchall())


async def on_mentor_message(
    session: AsyncSession, conversation: Conversation, *, actor: str = "mentor"
) -> None:
    """منتور در این گفتگو حرف زد.

    این روشن‌ترین نشانه‌ی در دست گرفتن مکالمه است، پس دستیار کنار می‌رود و ارجاع‌های
    باز بسته می‌شوند. برای فعال شدن دوباره یا خود منتور اقدام می‌کند یا فاصله‌ی زمانی
    کافی می‌گذرد.
    """
    await resolve_open(session, conversation.id, by=actor)
    if ConversationStatus(conversation.status) is ConversationStatus.active:
        escalate(conversation)
        session.add(
            AuditLog(
                actor=actor,
                action="mentor_took_over",
                target=str(conversation.id),
            )
        )


async def maybe_resume(
    session: AsyncSession,
    conversation: Conversation,
    *,
    after: timedelta = DEFAULT_RESUME_AFTER,
    now: datetime | None = None,
) -> bool:
    """اگر مداخله‌ی انسانی تمام شده به‌نظر می‌رسد، دستیار را برگردان.

    معیار، فاصله از آخرین پیام منتور است. اگر منتور همین حالا وسط گفتگوست، دستیار
    نباید وسط حرفش بپرد؛ اگر دیروز جواب داده و امروز سؤال تازه‌ای آمده، ساکت ماندن
    دستیار فایده‌ای ندارد.

    اگر منتور هنوز هیچ جوابی نداده، بازگشتی در کار نیست: مداخله‌ی انسانی اصلاً شروع
    نشده که تمام شده باشد.

    بازگشت خودکار فقط از حالت سپرده‌شده انجام می‌شود، هرگز از حالت بسته.
    """
    if ConversationStatus(conversation.status) is not ConversationStatus.awaiting_mentor:
        return False

    last = await last_mentor_message_at(session, conversation.id)
    if last is None:
        # منتور هنوز اصلاً جواب نداده. سپردن هنوز انجام نشده، پس برگرداندن دستیار
        # دقیقاً همان کاری است که نباید بشود. مکالمه سپرده می‌ماند و در فهرست
        # ارجاع‌های باز دیده می‌شود؛ شیر اطمینان همان فهرست است، نه بازگشت خودکار.
        return False

    moment = now or datetime.now(UTC)
    if moment - last < after:
        return False

    resume(conversation)
    session.add(
        AuditLog(
            actor="system",
            action="assistant_resumed",
            target=str(conversation.id),
            detail="auto",
        )
    )
    return True


async def resume_now(session: AsyncSession, conversation: Conversation, *, by: str) -> bool:
    """بازگرداندن صریح توسط منتور، بدون انتظار."""
    if ConversationStatus(conversation.status) is not ConversationStatus.awaiting_mentor:
        return False
    resume(conversation)
    session.add(
        AuditLog(actor=by, action="assistant_resumed", target=str(conversation.id), detail="manual")
    )
    return True


async def open_escalations(
    session: AsyncSession, *, account_id: int | None = None, limit: int = 20
) -> list[tuple[Escalation, Conversation]]:
    """ارجاع‌های باز، قدیمی‌ترین اول.

    این همان چیزی است که جلوی «پیامی روزها ماند و کسی متوجه نشد» را می‌گیرد.
    """
    stmt = (
        select(Escalation, Conversation)
        .join(Conversation, Conversation.id == Escalation.conversation_id)
        .where(Escalation.resolved_at.is_(None))
        .order_by(Escalation.created_at)
        .limit(limit)
    )
    if account_id is not None:
        stmt = stmt.where(Conversation.account_id == account_id)
    return [(e, c) for e, c in (await session.execute(stmt)).all()]
