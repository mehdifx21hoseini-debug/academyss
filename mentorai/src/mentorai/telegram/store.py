"""ذخیره‌ی پیام ورودی، با تشخیص تکراری اتمی.

تشخیص تکراری با قید یکتایی پایگاه داده انجام می‌شود، نه با «اول بخوان بعد بنویس». آن روش
بین دو کارگر هم‌زمان مسابقه دارد: هر دو مقدار قدیمی را می‌بینند، هر دو نتیجه می‌گیرند
تکراری نیست، و پیام دو بار پردازش می‌شود.
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import Conversation, Identity, MentorAccount, Sender, Student
from mentorai.telegram.normalize import InboundMessage


@dataclass(frozen=True)
class RecordResult:
    conversation: Conversation
    message_id: int | None
    is_duplicate: bool

    @property
    def conversation_id(self) -> int:
        return self.conversation.id


async def _resolve_student(session: AsyncSession, message: InboundMessage) -> Student:
    """هویت تلگرامی را به دانشجو وصل کن، و اگر نبود بساز.

    هویت و دانشجو دو چیز جدا هستند تا یک نفر بتواند از چند حساب تلگرام بیاید و همان
    یک دانشجو بماند.
    """
    identity = (
        await session.execute(
            select(Identity).where(Identity.telegram_user_id == message.sender_user_id)
        )
    ).scalar_one_or_none()

    if identity is not None:
        identity.username = message.username
        identity.first_name = message.first_name
        identity.last_name = message.last_name
        return await session.get_one(Student, identity.student_id)

    display = " ".join(p for p in (message.first_name, message.last_name) if p) or None
    student = Student(display_name=display)
    session.add(student)
    await session.flush()
    session.add(
        Identity(
            student_id=student.id,
            telegram_user_id=message.sender_user_id,
            username=message.username,
            first_name=message.first_name,
            last_name=message.last_name,
        )
    )
    await session.flush()
    return student


async def _resolve_conversation(
    session: AsyncSession, account: MentorAccount, student: Student, chat_id: int
) -> Conversation:
    conversation = (
        await session.execute(
            select(Conversation).where(
                Conversation.account_id == account.id,
                Conversation.telegram_chat_id == chat_id,
            )
        )
    ).scalar_one_or_none()
    if conversation is not None:
        return conversation

    conversation = Conversation(
        account_id=account.id, student_id=student.id, telegram_chat_id=chat_id
    )
    session.add(conversation)
    await session.flush()
    return conversation


async def record_inbound(
    session: AsyncSession,
    account: MentorAccount,
    message: InboundMessage,
    *,
    sender: Sender,
) -> RecordResult:
    student = await _resolve_student(session, message)
    conversation = await _resolve_conversation(session, account, student, message.chat_id)

    # درج با on conflict do nothing. اگر سطری برنگشت، یعنی این پیام قبلاً ثبت شده.
    # هیچ پنجره‌ای بین بررسی و درج وجود ندارد.
    inserted = await session.execute(
        text(
            """
            insert into messages (
                conversation_id, telegram_message_id, sender, text, media_type,
                reply_to_message_id, sent_at
            )
            values (
                :conversation_id, :telegram_message_id, :sender, :text, :media_type,
                :reply_to_message_id, :sent_at
            )
            on conflict (conversation_id, telegram_message_id) do nothing
            returning id
            """
        ),
        {
            "conversation_id": conversation.id,
            "telegram_message_id": message.message_id,
            "sender": sender.value,
            "text": message.text,
            "media_type": message.media_type,
            "reply_to_message_id": message.reply_to_message_id,
            "sent_at": message.sent_at,
        },
    )
    new_id = inserted.scalar_one_or_none()

    if new_id is None:
        # تکراری بی‌صدا دور انداخته نمی‌شود. بدون این ثبت، نرخ تکرار هرگز معلوم نمی‌شود.
        await session.execute(
            text(
                """
                insert into duplicate_deliveries
                    (account_id, telegram_chat_id, telegram_message_id)
                values (:account_id, :chat_id, :message_id)
                """
            ),
            {
                "account_id": account.id,
                "chat_id": message.chat_id,
                "message_id": message.message_id,
            },
        )
        return RecordResult(conversation=conversation, message_id=None, is_duplicate=True)

    return RecordResult(conversation=conversation, message_id=int(new_id), is_duplicate=False)


async def excluded_peer_ids(session: AsyncSession, account_id: int) -> frozenset[int]:
    rows = await session.execute(
        text("select telegram_peer_id from excluded_chats where account_id = :account_id"),
        {"account_id": account_id},
    )
    return frozenset(int(r[0]) for r in rows)
