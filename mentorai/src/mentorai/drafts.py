"""پیش‌نویس‌هایی که منتظر تأیید منتور هستند.

طبق ADR-010 این یک دوره‌ی کالیبراسیون است، نه طراحی دائمی. حالت پایدار سیستم ارسال
مستقیم است و این لایه با یک تنظیم روی هر حساب کنار می‌رود، نه با تغییر کد.
"""

from __future__ import annotations

import difflib
import enum
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import Draft, DraftDelivery, DraftStatus
from mentorai.text.persian import normalize_for_search, normalize_for_storage

# از این شباهت به بالا، پیام فرستاده‌شده «همان پیش‌نویسِ ویرایش‌شده» حساب می‌شود و کمتر،
# «چیز دیگری که منتور خودش نوشته». عدد حدسی است و بعد از چند آزمایش واقعی تنظیم
# می‌شود (ADR-036).
SIMILAR_AT = 0.6

# ساعت تلگرام و ساعت سرور چند ثانیه اختلاف دارند. پیامی که کمی پیش از ساخت پیش‌نویس
# ثبت شده نمی‌تواند پاسخ به آن باشد، ولی این‌قدر اختلاف را تحمل می‌کنیم.
CLOCK_SKEW = timedelta(seconds=10)


class DraftNotPending(RuntimeError):
    """پیش‌نویس قبلاً تصمیم گرفته شده.

    دوبار زدن دکمه‌ی تأیید نباید دو پیام بفرستد.
    """


async def create(
    session: AsyncSession,
    *,
    ai_run_id: int,
    conversation_id: int,
    proposed_text: str,
    delivery: DraftDelivery = DraftDelivery.control_bot,
) -> Draft:
    if delivery is DraftDelivery.chat:
        # هر گفتگو فقط یک کادر نوشتن دارد. پیش‌نویس تازه جای پیش‌نویس بی‌پاسخ قبلی را
        # می‌گیرد؛ در همین تراکنش، تا هیچ لحظه‌ای دو پیش‌نویس باز نماند.
        await _withdraw_pending_chat(session, conversation_id, reason="newer_draft")
    draft = Draft(
        ai_run_id=ai_run_id,
        conversation_id=conversation_id,
        proposed_text=proposed_text,
        delivery=delivery.value,
    )
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


async def repropose(session: AsyncSession, draft_id: int, *, body: str) -> Draft:
    """متن پیشنهادی را عوض کن، ولی پیش‌نویس را **تصمیم‌گرفته‌شده نکن**.

    مسیر «دستور کوتاه منتور» این را لازم دارد: منتور گفته چه بگوید، سیستم متن را
    نوشته، و حالا باید همان مسیر تأیید همیشگی طی شود. منتور هنوز تصمیمی نگرفته؛
    فقط پیشنهاد را عوض کرده.

    عمداً `edit` نیست، با اینکه شبیهش است. `edit` یک **تصمیم** است: پیش‌نویس را
    `edited` می‌کند و متن را در `final_text` می‌گذارد. اگر بسط هم از آن مسیر
    می‌رفت، دو چیز خراب می‌شد: پیش‌نویس پیش از تأیید نهایی می‌شد، و نسبت ویرایش به
    تأیید — همان عددی که شرط خروج از حالت پیش‌نویس است (`ADR-006`) — با چیزی پر
    می‌شد که تصمیم منتور نیست.

    بی‌عمد `by` نمی‌گیرد: تصمیمی ثبت نمی‌شود، و اینکه چه کسی دستور داد در
    `AuditLog` ربات کنترل می‌نشیند. پارامتری که نادیده گرفته شود، بعداً کسی را به
    این گمان می‌اندازد که جایی ثبت شده.
    """
    if not body.strip():
        raise ValueError("متن پیشنهادی خالی است")
    draft = await _claim(session, draft_id)
    draft.proposed_text = body.strip()
    # شماره‌ی نسخه بالا می‌رود تا دکمه‌ی تأییدِ کارت قبلی — که متن قبلی را نشان
    # می‌دهد — دیگر نخورد. وگرنه منتور چیزی را تأیید می‌کند که ندیده است.
    draft.revision += 1
    # `decided_by` و `status` دست‌نخورده می‌مانند: هیچ تصمیمی گرفته نشده.
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


async def withdraw(session: AsyncSession, draft_id: int, *, reason: str) -> Draft | None:
    """سیستم خودش پیش‌نویس را کنار می‌گذارد. این **تصمیم منتور نیست**.

    `rejected` نیست: رد تصمیم منتور است و در آمار شرط خروج از حالت پیش‌نویس
    می‌شمارد. دلیل در `decided_by` می‌ماند. اگر پیش‌نویس دیگر باز نیست، کاری نمی‌کند.
    """
    draft = (
        await session.execute(select(Draft).where(Draft.id == draft_id).with_for_update())
    ).scalar_one_or_none()
    if draft is None or draft.status != DraftStatus.pending.value:
        return None
    draft.status = DraftStatus.withdrawn.value
    draft.decided_by = f"system:{reason}"
    draft.decided_at = datetime.now(UTC)
    return draft


async def _pending_chat_drafts(session: AsyncSession, conversation_id: int) -> list[Draft]:
    return list(
        (
            await session.execute(
                select(Draft)
                .where(
                    Draft.conversation_id == conversation_id,
                    Draft.delivery == DraftDelivery.chat.value,
                    Draft.status == DraftStatus.pending.value,
                )
                .order_by(Draft.id.desc())
                .with_for_update()
            )
        ).scalars()
    )


async def _withdraw_pending_chat(
    session: AsyncSession, conversation_id: int, *, reason: str
) -> None:
    for draft in await _pending_chat_drafts(session, conversation_id):
        await withdraw(session, draft.id, reason=reason)


class ChatOutcome(enum.StrEnum):
    approved = "approved"
    edited = "edited"
    different = "different"


@dataclass(frozen=True)
class ChatResolution:
    draft_id: int
    outcome: ChatOutcome

    @property
    def took_over(self) -> bool:
        """منتور چیز دیگری نوشته؛ یعنی خودش گفتگو را در دست گرفته."""
        return self.outcome is ChatOutcome.different


def classify_sent(proposed: str, sent: str) -> ChatOutcome:
    """پیامی که منتور فرستاد نسبت به پیش‌نویس چیست."""
    a, b = normalize_for_search(proposed), normalize_for_search(sent)
    if a == b:
        return ChatOutcome.approved
    if not b:
        return ChatOutcome.different
    if difflib.SequenceMatcher(None, a, b).ratio() >= SIMILAR_AT:
        return ChatOutcome.edited
    return ChatOutcome.different


async def resolve_from_chat(
    session: AsyncSession, conversation_id: int, sent_text: str, *, sent_at: datetime
) -> ChatResolution | None:
    """پیام خروجی منتور را به پیش‌نویس باز همان گفتگو وصل کن (ADR-036).

    وقتی پیش‌نویس در کادر نوشتن خود گفتگو گذاشته می‌شود، دکمه‌ی تأییدی در کار نیست؛
    تصمیم منتور همان پیامی است که خودش می‌فرستد. None یعنی پیش‌نویسی در انتظار نبود
    و پیام یک پیام عادی منتور است.

    پیش‌نویس همیشه تصمیم می‌گیرد، حتی وقتی متن کاملاً متفاوت است: در آن حالت
    `withdrawn` می‌شود و `took_over` راست است تا فراخوانی‌کننده مثل هر پیام دستیِ منتور
    رفتار کند. بدون این، پیش‌نویسی که هیچ‌کس نفرستاده بود برای همیشه باز می‌ماند و
    پیام بعدیِ نامرتبط را به‌اشتباه به خودش وصل می‌کرد.
    """
    candidates = await _pending_chat_drafts(session, conversation_id)
    if not candidates:
        return None
    draft = candidates[0]
    # پیامی که پیش از ساخت پیش‌نویس رفته، پاسخ به آن نیست. پیش‌نویس باز می‌ماند و پیام
    # یک پیام عادی منتور حساب می‌شود.
    if sent_at < draft.created_at - CLOCK_SKEW:
        return None

    outcome = classify_sent(draft.proposed_text, sent_text)
    if outcome is ChatOutcome.different:
        await withdraw(session, draft.id, reason="mentor_wrote_other")
    else:
        draft.status = (
            DraftStatus.approved.value
            if outcome is ChatOutcome.approved
            else DraftStatus.edited.value
        )
        draft.final_text = normalize_for_storage(sent_text)
        draft.decided_by = "mentor:chat"
        draft.decided_at = sent_at
    # هر پیش‌نویس باز دیگرِ همین گفتگو هم دیگر معنی ندارد.
    for other in candidates[1:]:
        await withdraw(session, other.id, reason="newer_draft")
    return ChatResolution(draft_id=draft.id, outcome=outcome)
