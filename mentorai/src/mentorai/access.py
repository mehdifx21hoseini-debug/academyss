"""لایه‌ی دسترسی.

تمام خواندن داده‌ی دانشجو و مکالمه از همین‌جا می‌گذرد. محدودسازی داخل خود پرس‌وجو
اعمال می‌شود، نه بعد از خواندن: سطری که اجازه‌اش نیست اصلاً از پایگاه داده برنمی‌گردد.

دلیل اینکه این یک ماژول مشترک است و نه چند کپی در هر نقطه‌ی مصرف: در سیستم قبلی آکادمی
همین منطق ۴۸ بار دستی تکرار شده بود، اصلاح امنیتی در یکی انجام شد و در بقیه جا ماند.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass

from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import AuditLog, Conversation, Identity, Message, Student


class Role(enum.StrEnum):
    """فهرست سفید. هر نقشی که اینجا نباشد، هیچ دسترسی‌ای ندارد."""

    mentor = "mentor"
    admin = "admin"


@dataclass(frozen=True)
class Principal:
    """چه کسی درخواست می‌دهد."""

    role: Role
    account_id: int | None = None
    label: str = "unknown"

    def __post_init__(self) -> None:
        if self.role is Role.mentor and self.account_id is None:
            raise ValueError("منتور بدون حساب معنی ندارد؛ دامنه‌ی دسترسی از حساب می‌آید")


class NotPermitted(PermissionError):
    """درخواست‌شده وجود ندارد یا این درخواست‌دهنده اجازه‌اش را ندارد.

    این دو حالت عمداً از هم تفکیک نمی‌شوند. پاسخ متفاوت به «وجود ندارد» و «اجازه نداری»
    خودش افشای اطلاعات است: می‌شود با آن فهمید کدام شناسه‌ها وجود دارند.
    """


def _scoped_conversations(principal: Principal) -> Select[tuple[Conversation]]:
    stmt = select(Conversation)
    if principal.role is Role.mentor:
        # طبق ADR-007 منتور مسئول از روی حسابی که پیام روی آن رسیده تعیین می‌شود.
        stmt = stmt.where(Conversation.account_id == principal.account_id)
    return stmt


async def list_conversations(
    session: AsyncSession, principal: Principal, *, limit: int = 50, offset: int = 0
) -> list[Conversation]:
    stmt = (
        _scoped_conversations(principal)
        .order_by(Conversation.updated_at.desc())
        .limit(limit)
        .offset(offset)
    )
    return list((await session.execute(stmt)).scalars())


async def get_conversation(
    session: AsyncSession, principal: Principal, conversation_id: int
) -> Conversation:
    stmt = _scoped_conversations(principal).where(Conversation.id == conversation_id)
    conversation = (await session.execute(stmt)).scalar_one_or_none()
    if conversation is None:
        raise NotPermitted(f"مکالمه‌ی {conversation_id} در دسترس نیست")

    # خواندن یک مکالمه‌ی مشخص ثبت می‌شود. فهرست‌ها ثبت نمی‌شوند، چون حجم بالایی
    # تولید می‌کنند بدون اینکه چیز بیشتری بگویند؛ آنچه اهمیت دارد این است که چه کسی
    # سراغ کدام دانشجو رفت. محتوای پیام هرگز در این ثبت نمی‌آید.
    session.add(
        AuditLog(
            actor=principal.label,
            action="read_conversation",
            target=str(conversation_id),
        )
    )
    return conversation


async def list_messages(
    session: AsyncSession,
    principal: Principal,
    conversation_id: int,
    *,
    limit: int = 100,
) -> list[Message]:
    """پیام‌های یک مکالمه، تازه‌ترین اول.

    دسترسی از راه خود مکالمه بررسی می‌شود، پس مسیر میان‌بری وجود ندارد که کسی با
    شناسه‌ی مکالمه‌ی دیگری پیام بگیرد.
    """
    await get_conversation(session, principal, conversation_id)
    stmt = (
        select(Message)
        .where(Message.conversation_id == conversation_id)
        .order_by(Message.sent_at.desc(), Message.id.desc())
        .limit(limit)
    )
    return list((await session.execute(stmt)).scalars())


async def get_student(session: AsyncSession, principal: Principal, student_id: int) -> Student:
    """دانشجو فقط از راه مکالمه‌ای که این درخواست‌دهنده به آن دسترسی دارد دیده می‌شود.

    یک دانشجو می‌تواند با چند منتور مکالمه داشته باشد؛ هر منتور فقط از راه مکالمه‌ی
    خودش به او می‌رسد.
    """
    stmt = select(Student).where(
        Student.id == student_id,
        Student.id.in_(_scoped_conversations(principal).with_only_columns(Conversation.student_id)),
    )
    student = (await session.execute(stmt)).scalar_one_or_none()
    if student is None:
        raise NotPermitted(f"دانشجوی {student_id} در دسترس نیست")
    return student


async def list_identities(
    session: AsyncSession, principal: Principal, student_id: int
) -> list[Identity]:
    await get_student(session, principal, student_id)
    stmt = select(Identity).where(Identity.student_id == student_id).order_by(Identity.id)
    return list((await session.execute(stmt)).scalars())
