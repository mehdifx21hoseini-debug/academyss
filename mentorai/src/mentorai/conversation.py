"""موتور مکالمه: وضعیت‌ها و گذارهای مجاز.

وضعیت مکالمه صریح و شمارش‌شده است، نه چیزی که از روی مقدار چند فیلد پراکنده حدس زده
شود. گذار نامعتبر خطا می‌دهد؛ اگر بی‌صدا بپذیریم، مکالمه به حالتی می‌رسد که هیچ‌کس
برایش برنامه‌ای نداشته.
"""

from __future__ import annotations

from mentorai.db.models import Conversation, ConversationStatus

# گذارهای مجاز. هر چیزی که اینجا نیست، ممنوع است.
_ALLOWED: dict[ConversationStatus, frozenset[ConversationStatus]] = {
    ConversationStatus.active: frozenset(
        {ConversationStatus.awaiting_mentor, ConversationStatus.closed}
    ),
    ConversationStatus.awaiting_mentor: frozenset(
        {ConversationStatus.active, ConversationStatus.closed}
    ),
    ConversationStatus.closed: frozenset({ConversationStatus.active}),
}


class InvalidTransition(ValueError):
    pass


def can_transition(current: ConversationStatus, target: ConversationStatus) -> bool:
    return target in _ALLOWED[current]


def transition(conversation: Conversation, target: ConversationStatus) -> None:
    current = ConversationStatus(conversation.status)
    if current is target:
        return
    if not can_transition(current, target):
        raise InvalidTransition(f"گذار از {current.value} به {target.value} مجاز نیست")
    conversation.status = target.value


def assistant_may_answer(conversation: Conversation) -> bool:
    """آیا دستیار اجازه دارد روی این مکالمه پاسخ تولید کند.

    سه شرط، و هر سه باید برقرار باشند. جهت پیش‌فرض «نه» است: هر حالتی که اینجا صریحاً
    مجاز نشده، یعنی دستیار ساکت می‌ماند و کار به منتور می‌رسد.
    """
    if not conversation.assistant_enabled:
        return False
    status = ConversationStatus(conversation.status)
    if status is ConversationStatus.awaiting_mentor:
        # پس از ارجاع، دستیار متوقف می‌ماند تا صریحاً دوباره فعال شود.
        return False
    return status is ConversationStatus.active


def escalate(conversation: Conversation) -> None:
    """سپردن مکالمه به منتور.

    از هر وضعیتی قابل انجام است جز بسته‌شده، چون ارجاع مکالمه‌ی بسته بی‌معنی است.
    """
    transition(conversation, ConversationStatus.awaiting_mentor)


def resume(conversation: Conversation) -> None:
    """فعال‌سازی دوباره‌ی دستیار پس از پایان مداخله‌ی انسانی.

    عمداً یک عمل صریح است. بازگشت خودکار یعنی دستیار وسط کار منتور حرف بزند.
    """
    transition(conversation, ConversationStatus.active)
