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
from mentorai.ai import budget, expand, guard
from mentorai.ai.client import ModelClient
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
from mentorai.worker import question_for_draft, send_draft_now

log = structlog.get_logger(__name__)

_LINK_USAGE = "برای اتصال این گفتگو به یک حساب: /link <slug>\nبرای قطع اتصال: /unlink <slug>"
# پاسخ یکسان برای «پیدا نشد» و «اجازه نداری»، تا نشود با آن slugهای موجود را شمرد.
_LINK_REFUSED = "انجام نشد."


# پیشوندی که ریپلای را از «این را عیناً بفرست» به «این را بگو، خودت کاملش کن» عوض
# می‌کند. یک نویسه‌ی تک، چون منتور با موبایل تایپ می‌کند؛ و نویسه‌ای که هیچ پاسخ
# واقعی فارسی با آن شروع نمی‌شود.
INSTRUCTION_PREFIX = "+"


def _render(question: str, proposed: str) -> str:
    return (
        "📩 پیام دانشجو:\n"
        f"{question}\n\n"
        "✍️ پاسخ پیشنهادی:\n"
        f"{proposed}\n\n"
        "برای اصلاح، همین پیام را ریپلای کنید و متن درست را بنویسید.\n"
        f"یا با «{INSTRUCTION_PREFIX}» شروع کنید و فقط بگویید چه بگوید — "
        f"مثلاً «{INSTRUCTION_PREFIX} بگو از ویدیو ۱۰ شروع کنه»."
    )


# وضعیت تحویل، به زبانی که منتور بفهمد. کلید ناشناخته خودش نمایش داده می‌شود تا
# چیزی پنهان نماند.
_SEND_FAILURE = {
    "blocked": "فعلاً ارسال ممکن نیست (ساعات سکوت، سقف نرخ، یا محدودیت تلگرام). دوباره تلاش می‌شود.",
    "failed": "نتیجه‌ی ارسال نامعلوم ماند. عمداً دوباره فرستاده نمی‌شود؛ لطفاً خودتان بررسی کنید.",
    "abandoned": "ارسال رها شد چون نتیجه‌اش نامعلوم بود. لطفاً خودتان بررسی کنید.",
    "pending": "در صف ارسال است.",
    "sending": "در حال ارسال است.",
    "no_final_text": "متنی برای ارسال نیست.",
    "already_queued": "قبلاً در صف ارسال قرار گرفته.",
}


def _failure_text(status: str) -> str:
    return _SEND_FAILURE.get(status, status)


class ControlBot:
    """پیش‌نویس را به منتور می‌رساند و تصمیمش را برمی‌گرداند."""

    def __init__(
        self,
        *,
        channels: Mapping[str, OutboundChannel],
        gates: Mapping[str, AccountGate],
        model_client: ModelClient | None = None,
    ) -> None:
        settings = get_settings()
        if settings.control_bot_token is None:
            raise ValueError("CONTROL_BOT_TOKEN تنظیم نشده است")
        # بدون کلاینت مدل، مسیر دستور کوتاه خاموش است و منتور همان سه کار قبلی را
        # دارد. خاموش بودنش به منتور گفته می‌شود، بی‌صدا رد نمی‌شود.
        self._model_client = model_client
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
                    Button.inline(
                        "✅ تأیید و ارسال",
                        f"approve:{draft.id}:{draft.revision}".encode(),
                    ),
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
        action, _, rest = raw.partition(":")
        draft_id_raw, _, revision_raw = rest.partition(":")
        if action not in {"approve", "reject"} or not draft_id_raw.isdigit():
            return
        draft_id = int(draft_id_raw)
        # نسخه‌ای که این دکمه با خودش آورده. کارت‌های پیش از این قابلیت شماره
        # ندارند و «۰» حساب می‌شوند — که درست است: پیش‌نویسی که متنش عوض شده
        # نسخه‌اش حتماً بالاتر از صفر است، پس دکمه‌ی کهنه‌اش نمی‌خورد.
        shown_revision = int(revision_raw) if revision_raw.isdigit() else 0
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
            # تأیید باید به همان متنی بخورد که منتور دیده. اگر متن پیشنهادی بعد
            # از ساخته شدن این کارت عوض شده باشد — مثلاً با دستور کوتاه خودش —
            # این دکمه کهنه است و زدنش یعنی تأیید چیزی که ندیده. رد کردن کهنه
            # نیست: نرفتن پیام، هر نسخه‌ای باشد، همان نتیجه را دارد.
            if action == "approve":
                current = await session.get_one(Draft, draft_id)
                if current.revision != shown_revision:
                    await event.answer(
                        "متن این پیش‌نویس عوض شده. نسخه‌ی تازه را ببینید و همان را تأیید کنید.",
                        alert=True,
                    )
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

        result = await send_draft_now(draft_id, channels=self._channels, gates=self._gates)
        if result == "sent":
            await event.edit("✅ ارسال شد.")
        else:
            await event.edit(f"⚠️ ارسال نشد. {_failure_text(result)}")

    async def _expand_instruction(
        self, event: events.NewMessage.Event, replied: object, instruction: str
    ) -> None:
        """دستور کوتاه منتور را باز کن و برای تأیید برگردان.

        ترتیب عمدی است و هیچ‌کدام قابل حذف نیست: اول اجازه، بعد سقف هزینه، بعد
        فراخوانی مدل، بعد محافظ قیمت، و آخر ثبت در پیش‌نویس. بسط دادن **ارسال
        نیست**؛ متن جای پیش‌نویس می‌نشیند و منتور همان‌طور که قبلاً تأیید می‌کرد
        تأیید می‌کند. آدم از مدار بیرون نمی‌رود.
        """
        if not instruction:
            await event.reply(
                f"بعد از «{INSTRUCTION_PREFIX}» بنویسید چه بگوید. "
                f"مثلاً «{INSTRUCTION_PREFIX} بگو از ویدیو ۱۰ شروع کنه»."
            )
            return
        if self._model_client is None:
            await event.reply(
                "مسیر دستور کوتاه فعال نیست. متن کامل را ریپلای کنید تا همان فرستاده شود."
            )
            return

        async with session_scope() as session:
            # همان مسیر اجازه‌ی ریپلای ساده: محدود به همین گفتگو، چون شناسه‌ی پیام
            # تلگرام فقط داخل یک گفتگو یکتاست.
            try:
                draft, _ = await authorise_draft_by_control_message(
                    session,
                    int(replied.id),  # type: ignore[attr-defined]
                    chat_id=int(event.chat_id),
                    sender_id=event.sender_id,
                )
            except ControlNotPermitted:
                return
            draft_id = draft.id
            question = await question_for_draft(session, draft)
            if not (await budget.check(session, purpose=budget.Purpose.answer)).may_call:
                await event.reply("سقف هزینه‌ی مدل پر شده. متن کامل را ریپلای کنید.")
                return

        result = await expand.expand(
            self._model_client, instruction=instruction, question=question
        )

        async with session_scope() as session:
            # ثبت مصرف بی‌قیدوشرط، حتی وقتی فراخوانی شکست خورده: توکن مصرف‌شده در
            # پاسخ ناقص هم پول است.
            await budget.record(
                session,
                purpose=budget.Purpose.instruction_expansion,
                model=result.call.model,
                input_tokens=result.call.input_tokens,
                output_tokens=result.call.output_tokens,
                cache_read_tokens=result.call.cache_read_tokens,
            )

        if result.text is None:
            await event.reply(
                f"نشد متن را بسازم: {result.reason}\nمتن کامل را ریپلای کنید تا همان برود."
            )
            return

        # محافظ قیمت همین‌جا هم اجرا می‌شود، ولی دستور خود منتور منبع مجاز است:
        # او آدمِ آکادمی است. چیزی که می‌گیرد، عددی است که مدل **اضافه** کرده.
        bad = guard.ungrounded_money(result.text, mentor_text=instruction)
        if bad is not None:
            log.error("expansion_blocked_money", draft_id=draft_id, amount=bad)
            await event.reply(
                "متن ساخته‌شده عددی داشت که در دستور شما نبود، پس رد شد. "
                "اگر عدد لازم است خودتان در دستور بنویسید."
            )
            return

        async with session_scope() as session:
            try:
                await drafts.repropose(session, draft_id, body=result.text)
            except (drafts.DraftNotPending, ValueError) as exc:
                await event.reply(str(exc))
                return
            session.add(
                AuditLog(
                    actor=f"control:{event.sender_id}",
                    action="draft_expanded_from_instruction",
                    target=str(draft_id),
                )
            )
            await session.flush()
            revision = (await session.get_one(Draft, draft_id)).revision

        await event.reply(
            f"✍️ این را نوشتم:\n\n{result.text}",
            buttons=[
                [
                    Button.inline(
                        "✅ تأیید و ارسال", f"approve:{draft_id}:{revision}".encode()
                    ),
                    Button.inline("🚫 رد", f"reject:{draft_id}".encode()),
                ]
            ],
        )

    async def _on_reply(self, event: events.NewMessage.Event) -> None:
        """ریپلای روی پیام پیش‌نویس.

        دو معنی دارد و پیشوند از هم جدایشان می‌کند. ریپلای ساده یعنی «این متن را
        عیناً بفرست» — رفتار همیشگی. ریپلای با پیشوند یعنی «این را بگو، خودت
        کاملش کن»: دستور کوتاه منتور با لحن آکادمی باز می‌شود و **دوباره برای
        تأیید** به او برمی‌گردد، نه اینکه فرستاده شود.
        """
        body = (event.raw_text or "").strip()
        if not body or body.startswith("/"):
            return
        replied = await event.get_reply_message()
        if replied is None:
            return

        if body.startswith(INSTRUCTION_PREFIX):
            await self._expand_instruction(
                event, replied, body[len(INSTRUCTION_PREFIX) :].strip()
            )
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

        result = await send_draft_now(draft_id, channels=self._channels, gates=self._gates)
        await event.reply(
            "✅ نسخه شما ارسال شد." if result == "sent" else f"⚠️ ارسال نشد. {_failure_text(result)}"
        )
