from __future__ import annotations

from datetime import UTC, datetime

from mentorai.telegram.normalize import SkipReason, build_inbound, skip_reason


def _msg(**kw: object):  # type: ignore[no-untyped-def]
    defaults = {
        "account_slug": "mentor-a",
        "chat_id": 100,
        "message_id": 1,
        "sender_user_id": 100,
        "username": "student",
        "first_name": "سبحان",
        "last_name": None,
        "raw_text": "سلام",
        "media_type": None,
        "reply_to_message_id": None,
        "sent_at": datetime(2026, 9, 2, 12, 0, tzinfo=UTC),
        "is_private": True,
        "is_outgoing": False,
    }
    return build_inbound(**{**defaults, **kw})  # type: ignore[arg-type]


def test_private_student_message_is_processed() -> None:
    assert skip_reason(_msg(), excluded_peer_ids=frozenset()) is None


def test_group_and_channel_messages_are_never_processed() -> None:
    assert (
        skip_reason(_msg(is_private=False), excluded_peer_ids=frozenset()) is SkipReason.not_private
    )


def test_excluded_chat_is_skipped_by_chat_id() -> None:
    assert skip_reason(_msg(), excluded_peer_ids=frozenset({100})) is SkipReason.excluded_chat


def test_excluded_chat_is_skipped_by_sender_id() -> None:
    """گفتگو با شناسه‌ی دیگری هم استثنا می‌شود، چون شناسه‌ی گفتگو و کاربر همیشه یکی نیست."""
    msg = _msg(chat_id=555, sender_user_id=777)
    assert skip_reason(msg, excluded_peer_ids=frozenset({777})) is SkipReason.excluded_chat


def test_message_with_neither_text_nor_media_is_skipped() -> None:
    assert skip_reason(_msg(raw_text=None), excluded_peer_ids=frozenset()) is SkipReason.empty


def test_media_only_message_is_processed() -> None:
    assert (
        skip_reason(_msg(raw_text=None, media_type="voice"), excluded_peer_ids=frozenset()) is None
    )


def test_text_is_normalised_on_the_way_in() -> None:
    assert _msg(raw_text="كتاب  ۲").text == "کتاب 2"


def test_whitespace_only_text_becomes_none() -> None:
    assert _msg(raw_text="   ").text is None
