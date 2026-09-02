"""مجوزدهی ربات کنترل.

این منطق عمداً از خود ربات جدا است تا بدون تلگرام تست شود. ربات یک لایه‌ی نازک ترجمه
می‌ماند و هیچ تصمیم دسترسی‌ای داخلش گرفته نمی‌شود.

سه چیز باید هم‌زمان برقرار باشد تا کسی بتواند روی یک پیش‌نویس تصمیم بگیرد:
فرستنده در فهرست سفید باشد، گفتگو همان گفتگوی وصل‌شده‌ی آن حساب باشد، و پیش‌نویس
واقعاً متعلق به همان حساب باشد. هر کدام که نباشد، رد.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.config import get_settings
from mentorai.db.models import Conversation, Draft, MentorAccount


class ControlNotPermitted(PermissionError):
    """این درخواست‌دهنده اجازه‌ی این کار را ندارد، یا هدف وجود ندارد.

    دو حالت عمداً تفکیک نمی‌شوند: پاسخ متفاوت به «وجود ندارد» و «اجازه نداری» راهی
    برای شمردن شناسه‌های موجود می‌دهد.
    """


def is_operator(sender_id: int | None) -> bool:
    """آیا این فرستنده اجازه‌ی کار با ربات کنترل را دارد.

    فهرست خالی یعنی هیچ‌کس. جهت شکست بسته است: تنظیم‌نشده بودن نباید به دسترسی باز
    ختم شود.
    """
    if sender_id is None:
        return False
    return int(sender_id) in get_settings().operator_ids


async def account_for_slug(session: AsyncSession, slug: str) -> MentorAccount | None:
    return (
        await session.execute(select(MentorAccount).where(MentorAccount.slug == slug))
    ).scalar_one_or_none()


async def authorise_draft(
    session: AsyncSession, draft_id: int, *, chat_id: int, sender_id: int | None
) -> tuple[Draft, MentorAccount]:
    """پیش‌نویس را فقط وقتی برگردان که این فرستنده در این گفتگو مجاز باشد."""
    if not is_operator(sender_id):
        raise ControlNotPermitted("این کاربر اجازه‌ی کار با ربات کنترل را ندارد")

    row = (
        await session.execute(
            select(Draft, MentorAccount)
            .join(Conversation, Conversation.id == Draft.conversation_id)
            .join(MentorAccount, MentorAccount.id == Conversation.account_id)
            .where(Draft.id == draft_id)
        )
    ).first()
    if row is None:
        raise ControlNotPermitted(f"پیش‌نویس {draft_id} در دسترس نیست")

    draft, account = row
    # گفتگوی درخواست باید همان گفتگوی وصل‌شده‌ی همین حساب باشد. بدون این بررسی،
    # شناسه‌ی پیام در گفتگوی دیگری می‌تواند با شناسه‌ی یک پیش‌نویس واقعی برخورد کند.
    if account.control_chat_id is None or int(chat_id) != int(account.control_chat_id):
        raise ControlNotPermitted(f"پیش‌نویس {draft_id} در دسترس نیست")
    return draft, account


async def authorise_draft_by_control_message(
    session: AsyncSession, control_message_id: int, *, chat_id: int, sender_id: int | None
) -> tuple[Draft, MentorAccount]:
    """همان بررسی، ولی وقتی فقط شناسه‌ی پیام ربات را داریم.

    جستجو از ابتدا به گفتگو محدود می‌شود؛ شناسه‌ی پیام در تلگرام فقط داخل یک گفتگو
    یکتاست و بین گفتگوها می‌تواند تکرار شود.
    """
    if not is_operator(sender_id):
        raise ControlNotPermitted("این کاربر اجازه‌ی کار با ربات کنترل را ندارد")

    row = (
        await session.execute(
            select(Draft, MentorAccount)
            .join(Conversation, Conversation.id == Draft.conversation_id)
            .join(MentorAccount, MentorAccount.id == Conversation.account_id)
            .where(
                Draft.control_message_id == int(control_message_id),
                MentorAccount.control_chat_id == int(chat_id),
            )
        )
    ).first()
    if row is None:
        raise ControlNotPermitted("پیش‌نویسی برای این پیام پیدا نشد")
    draft, account = row
    return draft, account
