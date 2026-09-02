from __future__ import annotations

import pytest

from mentorai.conversation import (
    InvalidTransition,
    assistant_may_answer,
    can_transition,
    escalate,
    resume,
    transition,
)
from mentorai.db.models import Conversation, ConversationStatus


def _conv(status: ConversationStatus = ConversationStatus.active, enabled: bool = True):  # type: ignore[no-untyped-def]
    c = Conversation(account_id=1, student_id=1, telegram_chat_id=1)
    c.status = status.value
    c.assistant_enabled = enabled
    return c


def test_escalation_moves_to_awaiting_mentor() -> None:
    conv = _conv()
    escalate(conv)
    assert conv.status == ConversationStatus.awaiting_mentor.value


def test_assistant_is_silent_after_escalation() -> None:
    """پس از ارجاع، دستیار متوقف می‌ماند تا صریحاً دوباره فعال شود."""
    conv = _conv()
    assert assistant_may_answer(conv) is True
    escalate(conv)
    assert assistant_may_answer(conv) is False


def test_resume_is_explicit_and_restores_the_assistant() -> None:
    conv = _conv()
    escalate(conv)
    resume(conv)
    assert assistant_may_answer(conv) is True


def test_assistant_disabled_on_a_chat_outranks_status() -> None:
    assert assistant_may_answer(_conv(enabled=False)) is False


def test_closed_conversation_never_gets_an_assistant_answer() -> None:
    assert assistant_may_answer(_conv(ConversationStatus.closed)) is False


def test_invalid_transition_raises_instead_of_being_accepted_silently() -> None:
    conv = _conv(ConversationStatus.closed)
    with pytest.raises(InvalidTransition):
        transition(conv, ConversationStatus.awaiting_mentor)


def test_transition_to_the_same_status_is_a_no_op() -> None:
    conv = _conv()
    transition(conv, ConversationStatus.active)
    assert conv.status == ConversationStatus.active.value


@pytest.mark.parametrize(
    ("current", "target", "allowed"),
    [
        (ConversationStatus.active, ConversationStatus.awaiting_mentor, True),
        (ConversationStatus.active, ConversationStatus.closed, True),
        (ConversationStatus.awaiting_mentor, ConversationStatus.active, True),
        (ConversationStatus.awaiting_mentor, ConversationStatus.closed, True),
        (ConversationStatus.closed, ConversationStatus.active, True),
        (ConversationStatus.closed, ConversationStatus.awaiting_mentor, False),
    ],
)
def test_transition_table(
    current: ConversationStatus, target: ConversationStatus, allowed: bool
) -> None:
    assert can_transition(current, target) is allowed
