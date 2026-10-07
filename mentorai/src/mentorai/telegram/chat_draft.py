"""پیش‌نویس در کادر نوشتن خود گفتگوی دانشجو (ADR-036).

به‌جای کارت در ربات کنترل، متن در «پیش‌نویس ابری» همان گفتگو در حساب منتور گذاشته
می‌شود. **هیچ پیامی ارسال نمی‌شود**: منتور گفتگو را باز می‌کند، ویرایش می‌کند و خودش
می‌فرستد. تصمیم او همان پیامی است که می‌فرستد؛ `drafts.resolve_from_chat` آن را به
پیش‌نویس وصل می‌کند.

جهت شکست بسته است: هر چیزی که مطمئن نباشد، پیش‌نویس را کنار می‌گذارد و پیام دانشجو
مثل همیشه خوانده‌نشده برای منتور می‌ماند.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

import structlog
from sqlalchemy import select
from telethon.errors import FloodWaitError, RPCError

from mentorai import drafts
from mentorai.db.models import Conversation, Draft, DraftDelivery, DraftStatus, MentorAccount
from mentorai.db.session import session_scope
from mentorai.text.persian import normalize_for_search
from mentorai.worker import DraftNotifier

log = structlog.get_logger(__name__)

# چند پیش‌نویس اخیرِ همین گفتگو «متن خود ما» حساب می‌شود. کادر ممکن است هنوز پیش‌نویس
# قبلیِ نفرستاده‌شده را داشته باشد و جایگزین کردنش اشکالی ندارد.
_OUR_RECENT = 5


class ChatDraftNotifier:
    """پیاده‌سازی `DraftNotifier` که پیش‌نویس را در کادر نوشتن گفتگو می‌گذارد."""

    def __init__(self, clients: Mapping[str, Any]) -> None:
        # نام حساب (slug) به کلاینت Telethon همان حساب.
        self._clients = clients

    async def notify(self, *, account: MentorAccount, draft: Draft, question: str) -> int | None:
        # `question` را این مسیر لازم ندارد؛ منتور خودِ گفتگو را می‌بیند.
        del question
        if draft.delivery != DraftDelivery.chat.value:
            return None

        client = self._clients.get(account.slug)
        if client is None:
            await self._withdraw(draft.id, "no_client")
            return None

        async with session_scope() as session:
            fresh = await session.get(Draft, draft.id)
            if fresh is None or fresh.status != DraftStatus.pending.value:
                # در فاصله‌ی ساخت تا اینجا منتور خودش جواب داده یا پیش‌نویس تازه‌تری آمده.
                return None
            conversation = await session.get_one(Conversation, fresh.conversation_id)
            chat_id = int(conversation.telegram_chat_id)
            ours = await _our_recent_texts(session, conversation.id)
            text = fresh.proposed_text

        try:
            current = await client.get_drafts(chat_id)
            if not current.is_empty and normalize_for_search(current.raw_text) not in ours:
                # منتور خودش همین حالا در این گفتگو چیزی نوشته. پاک کردنش از بدترین
                # کارهایی است که این سیستم می‌تواند بکند.
                log.info("chat_draft_skipped_occupied", account=account.slug, draft_id=draft.id)
                await self._withdraw(draft.id, "chat_occupied")
                return None
            # `parse_mode=None`: متن همان‌طور که هست، بدون تبدیل مارک‌داون. نشانه‌هایی
            # مثل `*` یا `_` در پاسخ نباید ناپدید شوند یا قالب بگیرند.
            await current.set_message(text, parse_mode=None, link_preview=False)
        except FloodWaitError as exc:
            log.warning("chat_draft_flood", account=account.slug, seconds=int(exc.seconds))
            await self._withdraw(draft.id, "flood_wait")
            return None
        except (RPCError, ValueError):
            # ValueError: Telethon گفتگو را نمی‌شناسد (مثلاً پس از راه‌اندازی دوباره، پیش
            # از آنکه دانشجو پیام تازه‌ای بدهد).
            log.exception("chat_draft_failed", account=account.slug, draft_id=draft.id)
            await self._withdraw(draft.id, "telegram_error")
            return None

        log.info("chat_draft_written", account=account.slug, draft_id=draft.id)
        return None

    @staticmethod
    async def _withdraw(draft_id: int, reason: str) -> None:
        async with session_scope() as session:
            await drafts.withdraw(session, draft_id, reason=reason)


def choose_notifier(
    delivery: str, bot: DraftNotifier | None, clients: Mapping[str, Any]
) -> DraftNotifier | None:
    """محل تحویل پیش‌نویس را از تنظیم `DRAFT_DELIVERY` انتخاب کن.

    `control_bot`: همان ربات کنترل (یا هیچ، اگر توکنش نیست). `chat`: نوشتن در کادر
    خود گفتگو؛ ربات کنترل برای آن لازم نیست.
    """
    if delivery == DraftDelivery.chat.value:
        return ChatDraftNotifier(clients)
    return bot


async def _our_recent_texts(session: Any, conversation_id: int) -> set[str]:
    rows = (
        await session.execute(
            select(Draft.proposed_text)
            .where(
                Draft.conversation_id == conversation_id,
                Draft.delivery == DraftDelivery.chat.value,
            )
            .order_by(Draft.id.desc())
            .limit(_OUR_RECENT)
        )
    ).scalars()
    return {normalize_for_search(text) for text in rows}
