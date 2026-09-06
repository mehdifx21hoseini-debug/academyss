"""ربات کنترل منتورها.

عمداً یک ربات معمولی است و نه حساب کاربری. حساب‌های کاربری فقط رو به دانشجو هستند،
جایی که خواسته‌ی محصول ایجاب می‌کند؛ ربات فقط رو به منتور است، جایی که هیچ ریسک
مسدودی ندارد و ساختش هم ساده‌تر است.

این ماژول یک لایه‌ی نازک ترجمه است. تصمیم‌گیری در drafts.py و worker.py انجام می‌شود
که هر دو بدون تلگرام تست می‌شوند.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import UTC, datetime

import structlog
from sqlalchemy import select
from telethon import Button, TelegramClient, events

from mentorai import drafts, escalation
from mentorai.config import get_settings
from mentorai.control.auth import (
    ControlNotPermitted,
    account_for_slug,
    authorise_draft,
    authorise_draft_by_control_message,
    is_operator,
)
from mentorai.db.models import AuditLog, Conversation, Draft, MentorAccount
from mentorai.db.session import session_scope
from mentorai.telegram.safety import AccountGate
from mentorai.telegram.sender import OutboundChannel
from mentorai.worker import send_approved_draft

log = structlog.get_logger(__name__)

_LINK_USAGE = "برای اتصال این گفتگو به یک حساب: /link <slug>\nبرای قطع اتصال: /unlink <slug>"
# پاسخ یکسان برای «پیدا نشد» و «اجازه نداری»، تا نشود با آن slugهای موجود را شمرد.
_LINK_REFUSED = "انجام نشد."


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
        self._client.add_event_handler(self._on_unlink, events.NewMessage(pattern=r"^/unlink"))
        self._client.add_event_handler(self._on_pending, events.NewMessage(pattern=r"^/pending"))
        self._client.add_event_handler(self._on_resume, events.NewMessage(pattern=r"^/resume"))
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
        """اتصال یک گفتگو به یک حساب.

        بدون فهرست سفید، هر کسی که ربات را پیدا کند می‌تواند گفتگوی خودش را به یک
        حساب وصل کند و از آن لحظه پیام‌های واقعی دانشجوها را ببیند و از طرف منتور
        پاسخ بفرستد. برای همین این دستور فقط برای اپراتورهای تعریف‌شده کار می‌کند.
        """
        parts = (event.raw_text or "").split()
        if len(parts) != 2:
            await event.reply(_LINK_USAGE)
            return

        actor = f"control:{event.sender_id}"
        if not is_operator(event.sender_id):
            async with session_scope() as session:
                session.add(
                    AuditLog(
                        actor=actor,
                        action="link_denied",
                        target=parts[1],
                        detail=f"chat={event.chat_id}",
                    )
                )
            await event.reply(_LINK_REFUSED)
            return

        slug = parts[1]
        async with session_scope() as session:
            account = await account_for_slug(session, slug)
            if account is None:
                await event.reply(_LINK_REFUSED)
                return
            # اتصال موجود بی‌صدا جابه‌جا نمی‌شود. برای تغییر، اول باید قطع شود؛ وگرنه
            # یک دستور می‌تواند جریان پیش‌نویس‌ها را به گفتگوی دیگری منحرف کند.
            if account.control_chat_id is not None and int(account.control_chat_id) != int(
                event.chat_id
            ):
                session.add(
                    AuditLog(
                        actor=actor,
                        action="link_conflict",
                        target=slug,
                        detail=f"chat={event.chat_id}",
                    )
                )
                await event.reply(
                    "این حساب قبلاً به گفتگوی دیگری وصل است. اول از همان‌جا /unlink بزنید."
                )
                return
            account.control_chat_id = int(event.chat_id)
            session.add(AuditLog(actor=actor, action="link_control_chat", target=slug))
        await event.reply(f"این گفتگو به حساب {slug} وصل شد.")

    async def _on_unlink(self, event: events.NewMessage.Event) -> None:
        """قطع اتصال، فقط توسط اپراتور و فقط از همان گفتگویی که وصل است."""
        parts = (event.raw_text or "").split()
        if len(parts) != 2 or not is_operator(event.sender_id):
            await event.reply(_LINK_REFUSED)
            return
        slug = parts[1]
        async with session_scope() as session:
            account = await account_for_slug(session, slug)
            if (
                account is None
                or account.control_chat_id is None
                or int(account.control_chat_id) != int(event.chat_id)
            ):
                await event.reply(_LINK_REFUSED)
                return
            account.control_chat_id = None
            session.add(
                AuditLog(
                    actor=f"control:{event.sender_id}", action="unlink_control_chat", target=slug
                )
            )
        await event.reply(f"اتصال حساب {slug} قطع شد.")

    async def _linked_account(self, event: events.NewMessage.Event) -> MentorAccount | None:
        """حسابی که این گفتگو به آن وصل است، اگر فرستنده مجاز باشد."""
        if not is_operator(event.sender_id):
            return None
        async with session_scope() as session:
            return (
                await session.execute(
                    select(MentorAccount).where(MentorAccount.control_chat_id == int(event.chat_id))
                )
            ).scalar_one_or_none()

    async def _on_pending(self, event: events.NewMessage.Event) -> None:
        """پیام‌هایی که منتظر پاسخ منتور مانده‌اند.

        چون ارجاع برای دانشجو نامرئی است، بدون یک فهرست صریح ممکن است پیامی روزها
        بماند و کسی متوجه نشود.
        """
        account = await self._linked_account(event)
        if account is None:
            await event.reply(_LINK_REFUSED)
            return

        now = datetime.now(UTC)
        async with session_scope() as session:
            rows = await escalation.open_escalations(session, account_id=account.id)

        if not rows:
            await event.reply("هیچ پیام بی‌پاسخی در انتظار نیست.")
            return

        lines = ["پیام‌های در انتظار پاسخ شما، قدیمی‌ترین اول:"]
        for item, conversation in rows:
            hours = int((now - item.created_at).total_seconds() // 3600)
            lines.append(
                f"• گفتگوی {conversation.telegram_chat_id} — {item.reason} — {hours} ساعت پیش"
            )
        await event.reply("\n".join(lines))

    async def _on_resume(self, event: events.NewMessage.Event) -> None:
        """بازگرداندن صریح دستیار روی یک گفتگو، بدون انتظار."""
        parts = (event.raw_text or "").split()
        account = await self._linked_account(event)
        if account is None or len(parts) != 2 or not parts[1].lstrip("-").isdigit():
            await event.reply("برای بازگرداندن دستیار: /resume <شناسه گفتگو>")
            return

        async with session_scope() as session:
            conversation = (
                await session.execute(
                    select(Conversation).where(
                        Conversation.account_id == account.id,
                        Conversation.telegram_chat_id == int(parts[1]),
                    )
                )
            ).scalar_one_or_none()
            if conversation is None:
                await event.reply(_LINK_REFUSED)
                return
            resumed = await escalation.resume_now(
                session, conversation, by=f"control:{event.sender_id}"
            )
        await event.reply(
            "دستیار روی این گفتگو دوباره فعال شد."
            if resumed
            else "این گفتگو در حالت سپرده‌شده نبود."
        )

    async def _on_callback(self, event: events.CallbackQuery.Event) -> None:
        raw = (event.data or b"").decode()
        action, _, draft_id_raw = raw.partition(":")
        if action not in {"approve", "reject"} or not draft_id_raw.isdigit():
            return
        draft_id = int(draft_id_raw)
        actor = f"control:{event.sender_id}"

        async with session_scope() as session:
            # داده‌ی دکمه از سمت کاربر می‌آید و شناسه‌ها پشت‌سرهم‌اند، پس تعلق
            # پیش‌نویس به همین گفتگو و اجازه‌ی فرستنده باید صریح بررسی شود.
            try:
                await authorise_draft(
                    session, draft_id, chat_id=int(event.chat_id), sender_id=event.sender_id
                )
            except ControlNotPermitted as exc:
                session.add(
                    AuditLog(actor=actor, action="draft_action_denied", target=str(draft_id))
                )
                await event.answer(str(exc), alert=True)
                return
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
            # جستجو از ابتدا به همین گفتگو محدود است: شناسه‌ی پیام در تلگرام فقط
            # داخل یک گفتگو یکتاست و بین گفتگوها می‌تواند تکرار شود.
            try:
                draft, _ = await authorise_draft_by_control_message(
                    session,
                    int(replied.id),
                    chat_id=int(event.chat_id),
                    sender_id=event.sender_id,
                )
            except ControlNotPermitted:
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
