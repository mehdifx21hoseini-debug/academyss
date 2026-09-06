"""پیش‌نویس‌هایی که منتظر تأیید منتور هستند.

طبق ADR-010 این یک دوره‌ی کالیبراسیون است، نه طراحی دائمی. حالت پایدار سیستم ارسال
مستقیم است و این لایه با یک تنظیم روی هر حساب کنار می‌رود، نه با تغییر کد.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import Draft, DraftStatus


class DraftNotPending(RuntimeError):
    """پیش‌نویس قبلاً تصمیم گرفته شده.

    دوبار زدن دکمه‌ی تأیید نباید دو پیام بفرستد.
    """


async def create(
    session: AsyncSession, *, ai_run_id: int, conversation_id: int, proposed_text: str
) -> Draft:
    draft = Draft(ai_run_id=ai_run_id, conversation_id=conversation_id, proposed_text=proposed_text)
    session.add(draft)
    await session.flush()
    return draft


async def _claim(session: AsyncSession, draft_id: int) -> Draft:
    """پیش‌نویس را قفل کن تا دو تصمیم هم‌زمان روی آن ممکن نباشد."""
    draft = (
        await session.execute(select(Draft).where(Draft.id == draft_id).with_for_update())
    ).scalar_one_or_none()
    if draft is None:
        raise DraftNotPending(f"پیش‌نویس {draft_id} پیدا نشد")
    if draft.status != DraftStatus.pending.value:
        raise DraftNotPending(f"پیش‌نویس {draft_id} قبلاً {draft.status} شده")
    return draft


async def approve(session: AsyncSession, draft_id: int, *, by: str) -> Draft:
    draft = await _claim(session, draft_id)
    draft.status = DraftStatus.approved.value
    draft.final_text = draft.proposed_text
    draft.decided_by = by
    draft.decided_at = datetime.now(UTC)
    return draft


async def edit(session: AsyncSession, draft_id: int, *, by: str, body: str) -> Draft:
    """منتور متن را عوض کرد.

    تفاوت approve و edit در ثبت باقی می‌ماند: نسبت ویرایش به تأیید بدون تغییر، همان
    عددی است که شرط خروج از حالت پیش‌نویس را تعیین می‌کند.
    """
    if not body.strip():
        raise ValueError("متن ویرایش‌شده خالی است")
    draft = await _claim(session, draft_id)
    draft.status = DraftStatus.edited.value
    draft.final_text = body.strip()
    draft.decided_by = by
    draft.decided_at = datetime.now(UTC)
    return draft


async def reject(session: AsyncSession, draft_id: int, *, by: str) -> Draft:
    """منتور پیش‌نویس را رد کرد؛ چیزی به دانشجو نمی‌رود.

    پیام دانشجو خوانده‌نشده می‌ماند و مثل هر ارجاع دیگری منتظر پاسخ منتور است.
    """
    draft = await _claim(session, draft_id)
    draft.status = DraftStatus.rejected.value
    draft.decided_by = by
    draft.decided_at = datetime.now(UTC)
    return draft


async def mark_sent(session: AsyncSession, draft_id: int) -> Draft:
    draft = await session.get_one(Draft, draft_id)
    draft.status = DraftStatus.sent.value
    return draft


async def mark_failed(session: AsyncSession, draft_id: int) -> Draft:
    draft = await session.get_one(Draft, draft_id)
    draft.status = DraftStatus.failed.value
    return draft
