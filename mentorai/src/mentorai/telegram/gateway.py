"""دروازه‌ی تلگرام: دریافت، فیلتر، ذخیره.

در این مرحله دروازه **هیچ چیزی نمی‌فرستد**. نه پاسخ، نه واکنش، نه نشانگر تایپ، و
هیچ پیامی را خوانده علامت نمی‌زند.

این عمدی است و در ADR-009 ثبت شده: پیام بی‌پاسخ باید خوانده‌نشده بماند تا در تلگرام
خودِ منتور دیده شود. در MTProto دریافت به‌روزرسانی پیام را خوانده علامت نمی‌زند؛
علامت‌گذاری یک فراخوانی جداگانه است که در این ماژول اصلاً وجود ندارد.
"""

from __future__ import annotations

import asyncio
import contextlib

import structlog
from telethon import TelegramClient, events
from telethon.sessions import StringSession
from telethon.tl.functions.account import UpdateStatusRequest

from mentorai.config import get_settings
from mentorai.db.crypto import decrypt_session
from mentorai.db.models import MentorAccount, Sender
from mentorai.db.session import session_scope
from mentorai.jobs import queue
from mentorai.telegram.normalize import build_inbound, detect_media_type, skip_reason
from mentorai.telegram.store import excluded_peer_ids, record_inbound

log = structlog.get_logger(__name__)

# هر چند دقیقه وضعیت آفلاین اعلام می‌شود. اتصال دائم نباید حساب را همیشه آنلاین نگه
# دارد: هم غیرطبیعی است و هم برای تلگرام سیگنال رفتار خودکار است.
_OFFLINE_INTERVAL_SECONDS = 240


class AccountGateway:
    def __init__(self, account: MentorAccount) -> None:
        settings = get_settings()
        if account.session_encrypted is None:
            raise ValueError(f"حساب {account.slug} هنوز وارد نشده است")

        self.account_id = account.id
        self.slug = account.slug
        self._client = TelegramClient(
            StringSession(decrypt_session(account.session_encrypted)),
            settings.telegram_api_id,
            settings.telegram_api_hash.get_secret_value(),
            # اثر انگشت دستگاه ثابت. تغییر مکررش بررسی امنیتی تلگرام را فعال می‌کند.
            device_model=account.device_model,
            system_version=account.system_version,
            app_version=account.app_version,
        )
        self._offline_task: asyncio.Task[None] | None = None

    async def start(self) -> None:
        await self._client.connect()
        if not await self._client.is_user_authorized():
            raise RuntimeError(f"نشست حساب {self.slug} معتبر نیست؛ ورود دوباره لازم است")

        self._client.add_event_handler(self._on_message, events.NewMessage())
        self._offline_task = asyncio.create_task(self._keep_offline())
        log.info("gateway_started", account=self.slug)

    async def stop(self) -> None:
        if self._offline_task is not None:
            self._offline_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._offline_task
        await self._client.disconnect()
        log.info("gateway_stopped", account=self.slug)

    async def run_until_disconnected(self) -> None:
        await self._client.run_until_disconnected()

    async def _keep_offline(self) -> None:
        while True:
            with contextlib.suppress(Exception):
                await self._client(UpdateStatusRequest(offline=True))
            await asyncio.sleep(_OFFLINE_INTERVAL_SECONDS)

    async def _on_message(self, event: events.NewMessage.Event) -> None:
        message = event.message
        sender_id = event.sender_id
        if sender_id is None:
            return

        peer = await event.get_sender()
        inbound = build_inbound(
            account_slug=self.slug,
            chat_id=int(event.chat_id),
            message_id=int(message.id),
            sender_user_id=int(sender_id),
            username=getattr(peer, "username", None),
            first_name=getattr(peer, "first_name", None),
            last_name=getattr(peer, "last_name", None),
            raw_text=message.message or None,
            media_type=detect_media_type(message),
            reply_to_message_id=getattr(message.reply_to, "reply_to_msg_id", None),
            sent_at=message.date,
            is_private=bool(event.is_private),
            is_outgoing=bool(message.out),
        )

        async with session_scope() as session:
            excluded = await excluded_peer_ids(session, self.account_id)
            reason = skip_reason(inbound, excluded_peer_ids=excluded)
            if reason is not None:
                # هیچ اثری در تلگرام گذاشته نمی‌شود و محتوا ذخیره نمی‌شود.
                log.debug("message_skipped", account=self.slug, reason=reason.value)
                return

            account = await session.get_one(MentorAccount, self.account_id)
            # پیام خروجی، پاسخ خود منتور است. ثبتش هم تاریخچه‌ی مکالمه را کامل می‌کند
            # و هم داده‌ی واقعی پاسخ منتور را می‌سازد که برای پایگاه دانش لازم است.
            sender = Sender.mentor if inbound.is_outgoing else Sender.student
            result = await record_inbound(session, account, inbound, sender=sender)

            if result.is_duplicate:
                log.info("duplicate_delivery", account=self.slug, chat_id=inbound.chat_id)
                return

            if sender is Sender.student and result.assistant_enabled:
                await queue.enqueue(
                    session,
                    "answer_message",
                    {"conversation_id": result.conversation_id, "message_id": result.message_id},
                )

        log.info(
            "message_recorded",
            account=self.slug,
            conversation_id=result.conversation_id,
            sender=sender.value,
        )
