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
from dataclasses import dataclass

import structlog
from telethon import TelegramClient, events
from telethon.sessions import StringSession
from telethon.tl.functions.account import UpdateStatusRequest

from mentorai import escalation
from mentorai.ai import budget
from mentorai.ai.client import RawCall, VisionClient
from mentorai.config import get_settings
from mentorai.conversation import assistant_may_answer
from mentorai.db.crypto import decrypt_session
from mentorai.db.models import MentorAccount, Sender
from mentorai.db.session import session_scope
from mentorai.jobs import queue
from mentorai.media import extract as media_extract
from mentorai.media import store as media_store
from mentorai.media import vision, voice
from mentorai.telegram.normalize import build_inbound, detect_media_type, skip_reason
from mentorai.telegram.store import excluded_peer_ids, record_inbound

log = structlog.get_logger(__name__)

# هر چند دقیقه وضعیت آفلاین اعلام می‌شود. اتصال دائم نباید حساب را همیشه آنلاین نگه
# دارد: هم غیرطبیعی است و هم برای تلگرام سیگنال رفتار خودکار است.
_OFFLINE_INTERVAL_SECONDS = 240


@dataclass(frozen=True)
class _Attachment:
    """فایل یک پیام، بعد از خوانده شدن. خودِ بایت‌ها نگه داشته نمی‌شوند."""

    extraction: media_extract.Extraction
    mime: str | None
    size_bytes: int | None
    sha256: str | None
    # فراخوانی مدل برای توصیف تصویر، اگر انجام شده باشد. خواندن فایل عمداً بیرون از
    # هر تراکنشی انجام می‌شود، پس مصرف اینجا حمل می‌شود تا در همان نشستی ثبت شود که
    # خود پیام ثبت می‌شود (ADR-026).
    model_call: RawCall | None = None


class AccountGateway:
    def __init__(
        self, account: MentorAccount, *, vision_client: VisionClient | None = None
    ) -> None:
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
        # بدون این، عکس فقط ثبت می‌شود و خوانده نمی‌شود. حالت «فقط دریافت» عمداً
        # هیچ فراخوانی مدلی ندارد.
        self._vision = vision_client
        # None یعنی هیچ سرویس رونویسی‌ای پیکربندی نشده و ویس به منتور می‌رود.
        self._transcriber = voice.build_transcriber()

    @property
    def client(self) -> TelegramClient:
        """کلاینت زیرین، برای ساخت کانال خروجی.

        مسیر ارسال عمداً در ماژول جدایی است؛ این فقط اتصال را در اختیار می‌گذارد.
        """
        return self._client

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

    async def _read_attachment(self, message: object, media_type: str | None) -> _Attachment | None:
        """سند همراه پیام را بخوان، یا صریح ردش کن.

        فقط سند: عکس و ویس هم در تلگرام سند حساب می‌شوند، ولی خواندنشان هنوز ساخته
        نشده و طبق ADR-017 به منتور می‌روند. حجم **پیش از** دانلود بررسی می‌شود؛ بعد
        از دانلود دیگر دیر است.
        """
        if media_type not in ("document", "photo", "voice", "audio", "video_note"):
            return None
        handle = getattr(message, "file", None)
        if handle is None:
            return None

        mime = getattr(handle, "mime_type", None)
        # نام فایل از فرستنده می‌آید و فقط برای تشخیص قالب استفاده می‌شود؛ هیچ‌وقت
        # به مسیر فایل‌سیستم تبدیل نمی‌شود.
        name = getattr(handle, "name", None)
        size = int(getattr(handle, "size", 0) or 0)
        if media_type in ("voice", "audio", "video_note") and not voice.is_supported(
            mime or "audio/ogg", size
        ):
            return _Attachment(
                extraction=media_extract.Extraction(
                    kind="rejected", refused=media_extract.Refusal.unsupported_format
                ),
                mime=mime,
                size_bytes=size or None,
                sha256=None,
            )
        if media_type == "photo" and not vision.is_supported(mime or "image/jpeg", size):
            return _Attachment(
                extraction=media_extract.Extraction(
                    kind="rejected", refused=media_extract.Refusal.unsupported_format
                ),
                mime=mime,
                size_bytes=size or None,
                sha256=None,
            )
        if size > media_extract.MAX_BYTES:
            return _Attachment(
                extraction=media_extract.Extraction(
                    kind="rejected", refused=media_extract.Refusal.too_large
                ),
                mime=mime,
                size_bytes=size,
                sha256=None,
            )

        try:
            data = await message.download_media(file=bytes)  # type: ignore[attr-defined]
        except Exception:
            # شکست دانلود نباید کل پیام را از دست بدهد؛ پیام ثبت می‌شود و فایلش
            # ردشده علامت می‌خورد تا در پنل دیده شود.
            log.warning("media_download_failed", account=self.slug)
            data = None

        if not isinstance(data, bytes) or not data:
            return _Attachment(
                extraction=media_extract.Extraction(
                    kind="rejected", refused=media_extract.Refusal.unreadable
                ),
                mime=mime,
                size_bytes=size or None,
                sha256=None,
            )

        model_call: RawCall | None = None
        if media_type == "photo":
            extraction, model_call = await self._read_image(data, mime or "image/jpeg")
        elif media_type in ("voice", "audio", "video_note"):
            extraction = await self._read_voice(data, mime or "audio/ogg", name or "voice.ogg")
        else:
            extraction = media_extract.extract(data, filename=name, mime=mime)

        return _Attachment(
            extraction=extraction,
            model_call=model_call,
            mime=mime,
            size_bytes=len(data),
            sha256=media_store.fingerprint(data),
        )

    async def _read_image(
        self, data: bytes, mime: str
    ) -> tuple[media_extract.Extraction, RawCall | None]:
        """توصیف تصویر، یا رد شدن.

        در حالت «فقط دریافت» هیچ مدلی در دسترس نیست و تصویر رد می‌شود؛ یعنی همان
        رفتار قبلی: به منتور می‌رود.
        """
        if self._vision is None:
            return (
                media_extract.Extraction(
                    kind="rejected", refused=media_extract.Refusal.unsupported_format
                ),
                None,
            )
        description, error, call = await vision.describe(
            self._vision, image=data, media_type=mime
        )
        if description is None:
            log.warning("image_not_read", account=self.slug, reason=error)
            return (
                media_extract.Extraction(
                    kind="rejected", refused=media_extract.Refusal.unreadable
                ),
                call,
            )
        return media_extract.Extraction(kind="image", text=description), call

    async def _read_voice(self, data: bytes, mime: str, filename: str) -> media_extract.Extraction:
        """رونویسی ویس، یا رد شدن.

        بدون سرویس پیکربندی‌شده هیچ صدایی جایی نمی‌رود و ویس مثل قبل به منتور می‌رسد.
        """
        if self._transcriber is None:
            return media_extract.Extraction(
                kind="rejected", refused=media_extract.Refusal.unsupported_format
            )
        text, error = await voice.transcribe(
            self._transcriber, audio=data, media_type=mime, filename=filename
        )
        if text is None:
            log.warning("voice_not_transcribed", account=self.slug, reason=error)
            return media_extract.Extraction(
                kind="rejected", refused=media_extract.Refusal.unreadable
            )
        return media_extract.Extraction(kind="voice", text=text)

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
            # هیچ اثری در تلگرام گذاشته نمی‌شود، محتوا ذخیره نمی‌شود، و فایلی هم
            # دانلود نمی‌شود: گفتگوی استثناشده اصلاً وارد سیستم نمی‌شود.
            log.debug("message_skipped", account=self.slug, reason=reason.value)
            return

        # دانلود و خواندن فایل بیرون از هر تراکنش انجام می‌شود. نگه داشتن یک اتصال
        # پایگاه داده در طول یک انتقال شبکه، استخر اتصال را زیر بار واقعی خالی می‌کند.
        attachment = await self._read_attachment(message, inbound.media_type)

        async with session_scope() as session:
            account = await session.get_one(MentorAccount, self.account_id)
            # پیام خروجی، پاسخ خود منتور است. ثبتش هم تاریخچه‌ی مکالمه را کامل می‌کند
            # و هم داده‌ی واقعی پاسخ منتور را می‌سازد که برای پایگاه دانش لازم است.
            sender = Sender.mentor if inbound.is_outgoing else Sender.student
            result = await record_inbound(session, account, inbound, sender=sender)

            if result.is_duplicate:
                log.info("duplicate_delivery", account=self.slug, chat_id=inbound.chat_id)
                return

            # مصرف توصیف تصویر، در همان نشست. پیش از بررسی تکراری بودن انجام
            # نمی‌شود چون فراخوانی مدل قبلاً رخ داده و پولش خرج شده — چه پیام
            # تکراری باشد چه نه.
            if attachment is not None and attachment.model_call is not None:
                await budget.record(
                    session,
                    purpose=budget.Purpose.image_description,
                    model=attachment.model_call.model,
                    input_tokens=attachment.model_call.input_tokens,
                    output_tokens=attachment.model_call.output_tokens,
                    cache_read_tokens=attachment.model_call.cache_read_tokens,
                )

            if attachment is not None and result.message_id is not None:
                await media_store.record(
                    session,
                    message_id=result.message_id,
                    extraction=attachment.extraction,
                    mime=attachment.mime,
                    size_bytes=attachment.size_bytes,
                    sha256=attachment.sha256,
                )

            # وضعیت مکالمه هم دخیل است، نه فقط کلید روشن و خاموش: مکالمه‌ای که به
            # منتور ارجاع شده، تا فعال‌سازی صریح هیچ کاری تولید نمی‌کند.
            if sender is Sender.mentor:
                # روشن‌ترین نشانه‌ی در دست گرفتن مکالمه. دستیار کنار می‌رود و
                # ارجاع‌های باز بسته می‌شوند.
                await escalation.on_mentor_message(session, result.conversation)

            if sender is Sender.student and assistant_may_answer(result.conversation):
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
