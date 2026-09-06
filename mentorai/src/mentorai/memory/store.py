"""نوشتن و خواندن حافظه‌ی بلندمدت."""

from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy import select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import MemoryRejection, MemorySource, StudentMemory
from mentorai.memory.policy import Accepted, Candidate, Rejected, evaluate


@dataclass
class MemoryReport:
    stored: list[str] = field(default_factory=list)
    superseded: int = 0
    duplicates: int = 0
    rejected: list[Rejected] = field(default_factory=list)


async def _supersede(session: AsyncSession, student_id: int, category: str) -> int:
    """مقدار قبلی یک دسته‌ی تک‌مقداری را کنار بگذار.

    غیرفعال می‌شود، نه حذف. تاریخچه‌ی اینکه دانشجو قبلاً در چه مرحله‌ای بود ارزش دارد
    و حذفش چیزی به‌دست نمی‌آورد.
    """
    result = await session.execute(
        update(StudentMemory)
        .where(
            StudentMemory.student_id == student_id,
            StudentMemory.category == category,
            StudentMemory.active.is_(True),
        )
        .values(active=False, superseded_at=text("now()"))
        .returning(StudentMemory.id)
    )
    return len(result.fetchall())


async def remember(
    session: AsyncSession,
    *,
    student_id: int,
    accepted: Accepted,
    source: MemorySource,
    account_id: int | None = None,
    source_message_id: int | None = None,
) -> tuple[bool, int]:
    """یک واقعیت را ذخیره کن. برمی‌گرداند: (تازه بود، تعداد جایگزین‌شده)."""
    superseded = 0
    if accepted.single_valued:
        superseded = await _supersede(session, student_id, accepted.category.value)

    # ایندکس یکتای جزئی روی موارد فعال. همان واقعیت با همان نگارش دوباره ذخیره نمی‌شود.
    inserted = await session.execute(
        text(
            """
            insert into student_memories (
                student_id, account_id, category, content, content_key,
                confidence, source, source_message_id
            )
            values (
                :student_id, :account_id, :category, :content, :content_key,
                :confidence, :source, :source_message_id
            )
            on conflict (student_id, category, content_key) where active do nothing
            returning id
            """
        ),
        {
            "student_id": student_id,
            "account_id": account_id,
            "category": accepted.category.value,
            "content": accepted.content,
            "content_key": accepted.content_key,
            "confidence": accepted.confidence,
            "source": source.value,
            "source_message_id": source_message_id,
        },
    )
    return inserted.scalar_one_or_none() is not None, superseded


async def record_rejection(session: AsyncSession, *, student_id: int, rejected: Rejected) -> None:
    """رد شدن ثبت می‌شود، ولی محتوای ردشده نه.

    اگر متن ردشده را ذخیره کنیم، همان اطلاعاتی که سیاست جلویش را گرفت در جدول دیگری
    می‌ماند و کل کار بی‌معنی می‌شود.
    """
    session.add(
        MemoryRejection(
            student_id=student_id,
            category=rejected.candidate.category[:32] or None,
            reason=rejected.reason.value,
            detail=rejected.detail[:64] if rejected.detail else None,
        )
    )


async def apply_candidates(
    session: AsyncSession,
    *,
    student_id: int,
    candidates: list[Candidate],
    source: MemorySource,
    account_id: int | None = None,
    source_message_id: int | None = None,
) -> MemoryReport:
    """یافته‌ها را از سیاست بگذران و آنچه قبول شد را ذخیره کن."""
    report = MemoryReport()
    for candidate in candidates:
        verdict = evaluate(candidate)
        if isinstance(verdict, Rejected):
            report.rejected.append(verdict)
            await record_rejection(session, student_id=student_id, rejected=verdict)
            continue

        created, superseded = await remember(
            session,
            student_id=student_id,
            accepted=verdict,
            source=source,
            account_id=account_id,
            source_message_id=source_message_id,
        )
        report.superseded += superseded
        if created:
            report.stored.append(verdict.content)
        else:
            report.duplicates += 1
    return report


async def load_active(
    session: AsyncSession, student_id: int, *, limit: int = 30
) -> list[StudentMemory]:
    stmt = (
        select(StudentMemory)
        .where(StudentMemory.student_id == student_id, StudentMemory.active.is_(True))
        .order_by(StudentMemory.category, StudentMemory.created_at.desc())
        .limit(limit)
    )
    return list((await session.execute(stmt)).scalars())


_LABELS = {
    "course": "دوره",
    "learning_stage": "مرحله آموزشی",
    "interest": "علاقه",
    "goal": "هدف",
    "constraint": "محدودیت",
    "note": "یادداشت",
}


def render(memories: list[StudentMemory]) -> str:
    """حافظه به شکلی که در دستور مدل می‌آید."""
    if not memories:
        return ""
    lines = [f"- {_LABELS.get(m.category, m.category)}: {m.content}" for m in memories]
    return "\n".join(lines)
