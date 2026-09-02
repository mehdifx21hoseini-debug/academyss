"""ربات کنترل منتورها.

عمداً یک ربات معمولی است و نه حساب کاربری. حساب‌های کاربری فقط رو به دانشجو هستند،
جایی که خواسته‌ی محصول ایجاب می‌کند؛ ربات فقط رو به منتور است، جایی که هیچ ریسک
مسدودی ندارد و ساختش هم ساده‌تر است.

این ماژول یک لایه‌ی نازک ترجمه است. تصمیم‌گیری در drafts.py و worker.py انجام می‌شود
که هر دو بدون تلگرام تست می‌شوند.
"""

from __future__ import annotations

from collections.abc import Mapping

import structlog
from sqlalchemy import select
from telethon import Button, TelegramClient, events

from mentorai import drafts
from mentorai.config import get_settings
from mentorai.db.models import AuditLog, Draft, MentorAccount
from mentorai.db.session import session_scope
from mentorai.telegram.safety import AccountGate
from mentorai.telegram.sender import OutboundChannel
from mentorai.worker import send_approved_draft

log = structlog.get_logger(__name__)

_LINK_USAGE = "برای اتصال این گفتگو به یک حساب: /link <slug>"


def _render(question: str, proposed: str) -> str:
    return (
        "📩 پیام دانشجو:\n"
        f"{question}\n\n"
        "✍️ پاسخ پیشنهادی:\n"
        f"{proposed}\n\n"
        "برای اصلاح، همین پیام را ریپلای کنید و متن درست را بنویسید."
    )


class ControlBot:
    """پیش‌نویس را به منتور می‌رساند و تصمیمش را برمی‌گرداند."""

    def __init__(
        self,
        *,
        channels: Mapping[str, OutboundChannel],
        gates: Mapping[str, AccountGate],
    ) -> None:
        settings = get_settings()
        if settings.control_bot_token is None:
            raise ValueError("CONTROL_BOT_TOKEN تنظیم نشده است")
        self._token = settings.control_bot_token.get_secret_value()
        self._client = TelegramClient(
            "control-bot", settings.telegram_api_id, settings.telegram_api_hash.get_secret_value()
        )
        self._channels = channels
        self._gates = gates

    async def start(self) -> None:
        await self._client.start(bot_token=self._token)
        self._client.add_event_handler(self._on_link, events.NewMessage(pattern=r"^/link"))
        self._client.add_event_handler(self._on_reply, events.NewMessage(func=lambda e: e.is_reply))
        self._client.add_event_handler(self._on_callback, events.CallbackQuery())
        log.info("control_bot_started")

    async def run_until_disconnected(self) -> None:
        await self._client.run_until_disconnected()

    async def notify(self, *, account: MentorAccount, draft: Draft, question: str) -> int | None:
        """پیش‌نویس را برای منتور بفرست.

        اگر حساب هنوز به گفتگویی وصل نشده، پیش‌نویس در پایگاه داده می‌ماند و بعداً
        قابل بازیابی است؛ چیزی گم نمی‌شود.
        """
        if account.control_chat_id is None:
            log.warning("control_chat_not_linked", account=account.slug, draft_id=draft.id)
            return None
        message = await self._client.send_message(
            account.control_chat_id,
            _render(question, draft.proposed_text),
            buttons=[
                [
                    Button.inline("✅ تأیید و ارسال", f"approve:{draft.id}".encode()),
                    Button.inline("🚫 رد", f"reject:{draft.id}".encode()),
                ]
            ],
        )
        return int(message.id)

    async def _on_link(self, event: events.NewMessage.Event) -> None:
        parts = (event.raw_text or "").split()
        if len(parts) != 2:
            await event.reply(_LINK_USAGE)
            return
        slug = parts[1]
        async with session_scope() as session:
            account = (
                await session.execute(select(MentorAccount).where(MentorAccount.slug == slug))
            ).scalar_one_or_none()
            if account is None:
                await event.reply(f"حسابی با slug={slug} پیدا نشد")
                return
            account.control_chat_id = int(event.chat_id)
            session.add(
                AuditLog(
                    actor=f"control:{event.sender_id}", action="link_control_chat", target=slug
                )
            )
        await event.reply(f"این گفتگو به حساب {slug} وصل شد.")

    async def _on_callback(self, event: events.CallbackQuery.Event) -> None:
        raw = (event.data or b"").decode()
        action, _, draft_id_raw = raw.partition(":")
        if action not in {"approve", "reject"} or not draft_id_raw.isdigit():
            return
        draft_id = int(draft_id_raw)
        actor = f"control:{event.sender_id}"

        async with session_scope() as session:
            try:
                if action == "reject":
                    await drafts.reject(session, draft_id, by=actor)
                else:
                    await drafts.approve(session, draft_id, by=actor)
            except drafts.DraftNotPending as exc:
                await event.answer(str(exc), alert=True)
                return

        if action == "reject":
            await event.edit("🚫 رد شد. پیام دانشجو خوانده‌نشده ماند و منتظر پاسخ شماست.")
            return

        async with session_scope() as session:
            outcome = await send_approved_draft(
                session, draft_id, channels=self._channels, gates=self._gates
            )
        if outcome.outcome == "sent":
            await event.edit("✅ ارسال شد.")
        else:
            await event.edit(f"⚠️ ارسال نشد: {outcome.outcome} {outcome.detail or ''}".strip())

    async def _on_reply(self, event: events.NewMessage.Event) -> None:
        """ریپلای روی پیام پیش‌نویس، یعنی منتور متن را اصلاح کرده."""
        body = (event.raw_text or "").strip()
        if not body or body.startswith("/"):
            return
        replied = await event.get_reply_message()
        if replied is None:
            return

        async with session_scope() as session:
            draft = (
                await session.execute(
                    select(Draft).where(Draft.control_message_id == int(replied.id))
                )
            ).scalar_one_or_none()
            if draft is None:
                return
            try:
                await drafts.edit(session, draft.id, by=f"control:{event.sender_id}", body=body)
            except (drafts.DraftNotPending, ValueError) as exc:
                await event.reply(str(exc))
                return
            draft_id = draft.id

        async with session_scope() as session:
            outcome = await send_approved_draft(
                session, draft_id, channels=self._channels, gates=self._gates
            )
        await event.reply(
            "✅ نسخه شما ارسال شد."
            if outcome.outcome == "sent"
            else f"⚠️ ارسال نشد: {outcome.outcome} {outcome.detail or ''}".strip()
        )
