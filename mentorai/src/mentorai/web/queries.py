"""پرس‌وجوهای پنل.

همه از لایه‌ی دسترسی می‌گذرند یا محدودسازی را داخل خود پرس‌وجو دارند. پنل مسیر
خصوصی خودش به داده ندارد.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.access import Principal, Role
from mentorai.db.models import (
    AiRun,
    Conversation,
    Draft,
    Escalation,
    KnowledgeDocument,
    Message,
    MessageMedia,
    Outcome,
    Student,
)


@dataclass(frozen=True)
class Kpis:
    students: int
    conversations: int
    open_escalations: int
    oldest_open_hours: int | None
    runs_7d: int
    answered_7d: int
    silent_7d: int
    drafts_pending: int
    drafts_approved: int
    drafts_edited: int
    knowledge_documents: int

    @property
    def answer_rate(self) -> float:
        return self.answered_7d / self.runs_7d if self.runs_7d else 0.0

    @property
    def untouched_approval_rate(self) -> float:
        """نسبت تأیید بدون ویرایش.

        همان عددی است که تصمیم می‌گیرد یک حساب کی از حالت پیش‌نویس مستقل شود (ADR-010).
        """
        decided = self.drafts_approved + self.drafts_edited
        return self.drafts_approved / decided if decided else 0.0


def _scope(stmt, principal: Principal):  # type: ignore[no-untyped-def]
    if principal.role is Role.mentor:
        return stmt.where(Conversation.account_id == principal.account_id)
    return stmt


async def kpis(session: AsyncSession, principal: Principal) -> Kpis:
    since = datetime.now(UTC) - timedelta(days=7)

    conversations = (
        await session.execute(_scope(select(func.count(Conversation.id)), principal))
    ).scalar_one()
    students = (
        await session.execute(
            _scope(
                select(func.count(func.distinct(Conversation.student_id))).select_from(
                    Conversation
                ),
                principal,
            )
        )
    ).scalar_one()

    open_stmt = _scope(
        select(func.count(Escalation.id), func.min(Escalation.created_at))
        .select_from(Escalation)
        .join(Conversation, Conversation.id == Escalation.conversation_id)
        .where(Escalation.resolved_at.is_(None)),
        principal,
    )
    open_count, oldest = (await session.execute(open_stmt)).one()
    oldest_hours = (
        int((datetime.now(UTC) - oldest).total_seconds() // 3600) if oldest is not None else None
    )

    runs_stmt = _scope(
        select(AiRun.outcome, func.count(AiRun.id))
        .select_from(AiRun)
        .join(Conversation, Conversation.id == AiRun.conversation_id)
        .where(AiRun.created_at >= since)
        .group_by(AiRun.outcome),
        principal,
    )
    by_outcome: dict[str, int] = {
        str(outcome): int(count) for outcome, count in (await session.execute(runs_stmt)).all()
    }
    answered = int(by_outcome.get(Outcome.answer.value, 0))
    silent = int(by_outcome.get(Outcome.silence.value, 0))

    drafts_stmt = _scope(
        select(Draft.status, func.count(Draft.id))
        .select_from(Draft)
        .join(Conversation, Conversation.id == Draft.conversation_id)
        .group_by(Draft.status),
        principal,
    )
    by_status: dict[str, int] = {
        str(status): int(count) for status, count in (await session.execute(drafts_stmt)).all()
    }

    documents = (
        await session.execute(
            select(func.count(KnowledgeDocument.id)).where(KnowledgeDocument.active.is_(True))
        )
    ).scalar_one()

    return Kpis(
        students=int(students),
        conversations=int(conversations),
        open_escalations=int(open_count),
        oldest_open_hours=oldest_hours,
        runs_7d=answered + silent,
        answered_7d=answered,
        silent_7d=silent,
        drafts_pending=int(by_status.get("pending", 0)),
        drafts_approved=int(by_status.get("approved", 0)) + int(by_status.get("sent", 0)),
        drafts_edited=int(by_status.get("edited", 0)),
        knowledge_documents=int(documents),
    )


@dataclass(frozen=True)
class ConversationRow:
    id: int
    telegram_chat_id: int
    student_name: str | None
    status: str
    assistant_enabled: bool
    updated_at: datetime
    open_escalations: int


async def conversation_rows(
    session: AsyncSession, principal: Principal, *, limit: int = 50
) -> list[ConversationRow]:
    open_count = (
        select(func.count(Escalation.id))
        .where(
            Escalation.conversation_id == Conversation.id,
            Escalation.resolved_at.is_(None),
        )
        .scalar_subquery()
    )
    stmt = (
        _scope(
            select(
                Conversation.id,
                Conversation.telegram_chat_id,
                Student.display_name,
                Conversation.status,
                Conversation.assistant_enabled,
                Conversation.updated_at,
                open_count,
            ).join(Student, Student.id == Conversation.student_id),
            principal,
        )
        .order_by(Conversation.updated_at.desc())
        .limit(limit)
    )

    return [ConversationRow(*row) for row in (await session.execute(stmt)).all()]


async def messages_with_runs(
    session: AsyncSession, conversation_id: int, *, limit: int = 100
) -> list[tuple[Message, AiRun | None, MessageMedia | None]]:
    """پیام‌ها، اجرای هوش مصنوعی هرکدام، و آنچه از فایلشان خوانده شد.

    فایل هم می‌آید چون بدون آن، پیامِ دارای عکس یا سند در پنل فقط یک برچسب خالی است
    و معلوم نمی‌شود سیستم چه فهمیده — که دقیقاً همان چیزی است که باید سنجیده شود.

    دسترسی پیش از این تابع و از راه لایه‌ی دسترسی بررسی می‌شود.
    """
    stmt = (
        select(Message, AiRun, MessageMedia)
        .outerjoin(AiRun, AiRun.message_id == Message.id)
        .outerjoin(MessageMedia, MessageMedia.message_id == Message.id)
        .where(Message.conversation_id == conversation_id)
        .order_by(Message.sent_at, Message.id)
        .limit(limit)
    )
    return [(m, r, media) for m, r, media in (await session.execute(stmt)).all()]


async def open_escalation_rows(
    session: AsyncSession, principal: Principal, *, limit: int = 50
) -> list[tuple[Escalation, Conversation, str | None]]:
    stmt = (
        _scope(
            select(Escalation, Conversation, Student.display_name)
            .join(Conversation, Conversation.id == Escalation.conversation_id)
            .join(Student, Student.id == Conversation.student_id)
            .where(Escalation.resolved_at.is_(None)),
            principal,
        )
        .order_by(Escalation.created_at)
        .limit(limit)
    )
    return [(e, c, n) for e, c, n in (await session.execute(stmt)).all()]


async def knowledge_rows(session: AsyncSession, *, limit: int = 100) -> list[KnowledgeDocument]:
    stmt = (
        select(KnowledgeDocument)
        .order_by(KnowledgeDocument.source_class, KnowledgeDocument.category)
        .limit(limit)
    )
    return list((await session.execute(stmt)).scalars())
