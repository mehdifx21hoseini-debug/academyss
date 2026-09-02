"""تبدیل به‌روزرسانی تلگرام به مدل دامنه، و تصمیم اینکه اصلاً پردازش شود یا نه.

این ماژول عمداً به Telethon وابسته نیست تا بدون شبکه و بدون حساب واقعی قابل تست باشد.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from mentorai.text import normalize_for_storage


class SkipReason(enum.StrEnum):
    not_private = "not_private"
    excluded_chat = "excluded_chat"
    assistant_disabled = "assistant_disabled"
    empty = "empty"


@dataclass(frozen=True)
class InboundMessage:
    account_slug: str
    chat_id: int
    message_id: int
    sender_user_id: int
    username: str | None
    first_name: str | None
    last_name: str | None
    text: str | None
    media_type: str | None
    reply_to_message_id: int | None
    sent_at: datetime
    is_private: bool
    is_outgoing: bool


_MEDIA_ATTRS = (
    ("voice", "voice"),
    ("video_note", "video_note"),
    ("photo", "photo"),
    ("video", "video"),
    ("audio", "audio"),
    ("document", "document"),
    ("sticker", "sticker"),
    ("contact", "contact"),
    ("geo", "location"),
)


def detect_media_type(message: Any) -> str | None:
    """اولین نوع رسانه‌ای که پیام دارد.

    ترتیب مهم است: در Telethon یک ویس هم `document` است، پس باید قبل از آن بررسی شود.
    """
    for attr, label in _MEDIA_ATTRS:
        if getattr(message, attr, None):
            return label
    return None


def build_inbound(
    *,
    account_slug: str,
    chat_id: int,
    message_id: int,
    sender_user_id: int,
    username: str | None,
    first_name: str | None,
    last_name: str | None,
    raw_text: str | None,
    media_type: str | None,
    reply_to_message_id: int | None,
    sent_at: datetime,
    is_private: bool,
    is_outgoing: bool,
) -> InboundMessage:
    text = normalize_for_storage(raw_text) if raw_text else None
    return InboundMessage(
        account_slug=account_slug,
        chat_id=chat_id,
        message_id=message_id,
        sender_user_id=sender_user_id,
        username=username,
        first_name=first_name,
        last_name=last_name,
        text=text or None,
        media_type=media_type,
        reply_to_message_id=reply_to_message_id,
        sent_at=sent_at,
        is_private=is_private,
        is_outgoing=is_outgoing,
    )


def skip_reason(
    message: InboundMessage,
    *,
    excluded_peer_ids: frozenset[int],
) -> SkipReason | None:
    """چرا این پیام نباید پردازش شود، یا None اگر باید بشود.

    طبق ADR-008: گفتگوی خصوصی دونفره پیش‌فرض پردازش می‌شود، گروه و کانال هرگز، و
    گفتگوهای فهرست استثنا کنار گذاشته می‌شوند.
    """
    if not message.is_private:
        return SkipReason.not_private
    if message.chat_id in excluded_peer_ids or message.sender_user_id in excluded_peer_ids:
        return SkipReason.excluded_chat
    if message.text is None and message.media_type is None:
        return SkipReason.empty
    return None
