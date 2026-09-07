"""کارگر: کارهای صف را بردار و خط پردازش را اجرا کن.

جدا بودن کارگر از دروازه عمدی است. اتصال MTProto باید همیشه پاسخگو بماند در حالی که
یک پاسخ هوش مصنوعی چند ثانیه طول می‌کشد.
"""

from __future__ import annotations

import asyncio
import contextlib
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Protocol

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import delivery, drafts, escalation
from mentorai.ai.client import ModelClient
from mentorai.ai.runtime import handle_message
from mentorai.conversation import assistant_may_answer
from mentorai.db.models import (
    AiRun,
    Conversation,
    Draft,
    DraftStatus,
    MentorAccount,
    Message,
    Outcome,
    ReplyMode,
)
from mentorai.db.session import session_scope
from mentorai.jobs import queue
from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.media import store as media_store
from mentorai.memory import job as memory_job
from mentorai.telegram.safety import AccountGate
from mentorai.telegram.sender import OutboundChannel, SendStatus, push, record_sent

log = structlog.get_logger(__name__)

JOB_KIND = "answer_message"
HANDLED_KINDS = [JOB_KIND, memory_job.JOB_KIND]
IDLE_SLEEP_SECONDS = 2.0
STALE_LOCK_AFTER = timedelta(minutes=10)


class DraftNotifier(Protocol):
    """راهی برای رساندن پیش‌نویس به منتور.

    ربات کنترل این را پیاده می‌کند. جدا بودنش یعنی منطق کارگر بدون تلگرام قابل تست است.
    """

    async def notify(
        self, *, account: MentorAccount, draft: Draft, question: str
    ) -> int | None: ...


@dataclass(frozen=True)
class JobOutcome:
    outcome: str
    detail: str | None = None


# آنچه در فایل پیام دیده شد، همان‌طور که به منتور نشان داده می‌شود.
_MEDIA_LABELS = {
    "voice": "🎙 ویس دانشجو، رونویسی‌شده",
    "image": "🖼 آنچه در تصویر دیده شد",
    "plan": "📄 متن خوانده‌شده از فایل",
}


async def _mentor_question(session: AsyncSession, message: Message) -> str:
    """پرسشی که منتور کنار پیش‌نویس می‌بیند.

    برای پیام دارای فایل، متن پیام تنها کافی نیست: ویس اصلاً متن ندارد و منتور
    نباید پاسخی را تأیید کند که سؤالش را ندیده است.
    """
    text = (message.text or "").strip()
    if message.media_type is None:
        return text

    row = await media_store.load(session, message.id)
    if row is None:
        return text or f"[{message.media_type}]"
    if row.kind == "statement":
        extra = "📊 استیتمنت خوانده شد؛ اعدادش در پاسخ آمده."
    elif row.kind == "rejected":
        extra = f"📎 فایل خوانده نشد ({row.refusal})."
    elif row.extracted_text:
        extra = f"{_MEDIA_LABELS.get(row.kind, '📎 محتوای فایل')}:\n{row.extracted_text}"
    else:
        extra = f"[{message.media_type}]"
    return f"{text}\n\n{extra}" if text else extra


async def process_message(
    session: AsyncSession,
    message_id: int,
    *,
    model_client: ModelClient,
    embedder: EmbeddingProvider | None,
    channels: Mapping[str, OutboundChannel],
    gates: Mapping[str, AccountGate],
    notifier: DraftNotifier | None,
    sleep: bool = True,
) -> JobOutcome:
    message = await session.get(Message, message_id)
    if message is None:
        return JobOutcome("missing_message")

    conversation = await session.get_one(Conversation, message.conversation_id)
    account = await session.get_one(MentorAccount, conversation.account_id)

    # وضعیت ممکن است از زمان صف شدن عوض شده باشد: منتور مکالمه را به دست گرفته یا
    # دستیار روی این گفتگو خاموش شده. دوباره بررسی می‌شود.
    may_answer = assistant_may_answer(conversation)
    if not may_answer:
        # شاید مداخله‌ی انسانی تمام شده باشد. اگر از آخرین پیام منتور به‌قدر کافی
        # گذشته، دستیار برمی‌گردد؛ وگرنه ساکت می‌ماند.
        may_answer = await escalation.maybe_resume(session, conversation)
    if not may_answer:
        return JobOutcome("assistant_disabled")

    result = await handle_message(session, message, model_client=model_client, embedder=embedder)
    if result.outcome is Outcome.silence or result.answer_text is None:
        # سکوت کامل: پیام خوانده‌نشده می‌ماند و منتور در تلگرام خودش می‌بیندش.
        #
        # ولی همه‌ی سکوت‌ها یکی نیستند. اگر دلیل از آن‌هایی است که اصلاً کار دستیار
        # نیست — پول، شکایت، حساب، درخواست منتور — پیام بعدی هم کار دستیار نیست و
        # کل مکالمه سپرده می‌شود. سکوت موردی مکالمه را فعال می‌گذارد.
        if escalation.is_handoff(result.reason):
            await escalation.hand_off(session, conversation, reason=result.reason)
        return JobOutcome("silence", result.reason)

    if account.reply_mode == ReplyMode.draft.value:
        draft = await drafts.create(
            session,
            ai_run_id=result.ai_run_id,
            conversation_id=conversation.id,
            proposed_text=result.answer_text,
        )
        # اعلان به ربات کنترل اینجا فرستاده **نمی‌شود**. آن هم یک ارسال تلگرامی
        # است و اینجا داخل تراکنش هستیم؛ اگر تراکنش برگردد، منتور کارتی می‌بیند
        # که پیش‌نویسش وجود ندارد. پس از تثبیت فرستاده می‌شود (ADR-031).
        return JobOutcome("drafted", str(draft.id))

    if account.slug not in channels or account.slug not in gates:
        return JobOutcome("no_channel", account.slug)

    # ارسال اینجا انجام **نمی‌شود**. این تابع داخل یک تراکنش اجرا می‌شود و ارسال
    # به تلگرام برگشت‌ناپذیر است؛ فقط یک سطر در صندوق خروج ساخته می‌شود و پس از
    # تثبیت تراکنش، بیرون از آن فرستاده می‌شود (ADR-030).
    delivery_id = await delivery.enqueue(
        session,
        conversation_id=conversation.id,
        answered_message_id=message.id,
        body=result.answer_text,
    )
    if delivery_id is None:
        # از قبل تحویلی برای این پیام وجود داشت. قید یکتایی جلوی پاسخ دوم را گرفت.
        return JobOutcome("already_queued")
    return JobOutcome("queued", str(delivery_id))


async def notify_draft(draft_id: int, notifier: DraftNotifier) -> bool:
    """پیش‌نویس تازه را به منتور نشان بده. **پس از** تثبیت تراکنش ساخت آن.

    سه مرحله مثل مسیر تحویل: خواندن آنچه لازم است، ارسال بیرون از هر تراکنشی،
    و ثبت شناسه‌ی پیام کنترلی در تراکنشی جدا (`ADR-031`).

    شکست اعلان پیش‌نویس را از بین نمی‌برد؛ در پنل و با `/pending` دیده می‌شود.
    """
    async with session_scope() as session:
        draft = await session.get(Draft, draft_id)
        if draft is None:
            return False
        conversation = await session.get_one(Conversation, draft.conversation_id)
        account = await session.get_one(MentorAccount, conversation.account_id)
        run = await session.get_one(AiRun, draft.ai_run_id)
        message = await session.get_one(Message, run.message_id)
        question = await _mentor_question(session, message)

    try:
        control_message_id = await notifier.notify(
            account=account, draft=draft, question=question
        )
    except Exception:  # noqa: BLE001 - شکست اعلان نباید کارگر را بکشد
        log.exception("draft_notify_failed", draft_id=draft_id)
        return False

    if control_message_id is None:
        return False

    async with session_scope() as session:
        stored = await session.get(Draft, draft_id)
        if stored is not None:
            stored.control_message_id = control_message_id
    return True


async def queue_approved_draft(
    session: AsyncSession,
    draft_id: int,
    *,
    channels: Mapping[str, OutboundChannel],
    gates: Mapping[str, AccountGate],
) -> tuple[JobOutcome, int | None]:
    """پیش‌نویس تأییدشده را در صندوق خروج بگذار. اینجا هیچ چیزی فرستاده نمی‌شود.

    شناسه‌ی تحویل برگردانده می‌شود تا فراخوانی‌کننده — پس از تثبیت این تراکنش —
    همان را بفرستد و نتیجه‌ی واقعی را به منتور بگوید.
    """
    draft = await session.get_one(Draft, draft_id)
    if draft.final_text is None:
        return JobOutcome("no_final_text"), None

    conversation = await session.get_one(Conversation, draft.conversation_id)
    account = await session.get_one(MentorAccount, conversation.account_id)
    # پیامی که این پیش‌نویس پاسخ آن است. علامت خوانده‌شدن باید تا همین برود، نه جلوتر.
    run = await session.get_one(AiRun, draft.ai_run_id)
    answered_message = await session.get_one(Message, run.message_id)

    if account.slug not in channels or account.slug not in gates:
        await drafts.mark_failed(session, draft_id)
        return JobOutcome("no_channel", account.slug), None

    delivery_id = await delivery.enqueue(
        session,
        conversation_id=conversation.id,
        answered_message_id=answered_message.id,
        body=draft.final_text,
    )
    if delivery_id is None:
        return JobOutcome("already_queued"), None
    return JobOutcome("queued", str(delivery_id)), delivery_id


async def deliver_claimed(
    claimed: delivery.Claimed,
    *,
    channels: Mapping[str, OutboundChannel],
    gates: Mapping[str, AccountGate],
    sleep: bool = True,
) -> SendStatus:
    """یک تحویل برداشته‌شده را بفرست و نتیجه‌اش را ثبت کن.

    ارسال **بیرون از هر تراکنشی** انجام می‌شود؛ ثبت نتیجه در تراکنشی جدا. اگر
    فرایند بین این دو بمیرد، سطر در `sending` می‌ماند و `abandon_stale` بعداً
    رهایش می‌کند — هرگز دوباره فرستاده نمی‌شود.
    """
    channel = channels.get(claimed.account_slug)
    gate = gates.get(claimed.account_slug)
    if channel is None or gate is None:
        async with session_scope() as session:
            await delivery.abandon(session, claimed.id, f"کانالی برای {claimed.account_slug} نیست")
        return SendStatus.failed

    send = await push(
        chat_id=claimed.telegram_chat_id,
        answered_telegram_message_id=claimed.answered_telegram_message_id,
        body=claimed.body,
        gate=gate,
        channel=channel,
        sleep=sleep,
    )

    async with session_scope() as session:
        if send.status is SendStatus.sent and send.telegram_message_id is not None:
            conversation = await session.get_one(Conversation, claimed.conversation_id)
            answered = await session.get_one(Message, claimed.answered_message_id)
            record_sent(
                session,
                conversation=conversation,
                answered_message=answered,
                body=claimed.body,
                telegram_message_id=send.telegram_message_id,
            )
            await delivery.mark_sent(
                session, claimed.id, telegram_message_id=send.telegram_message_id
            )
            await _settle_draft(session, claimed.answered_message_id, sent=True)
        elif send.status is SendStatus.blocked:
            # می‌دانیم چیزی نرفته — سقف نرخ، ساعات سکوت، یا FloodWait. امن است.
            await delivery.retry_later(session, claimed.id, error=send.reason or "blocked")
        else:
            # نامعلوم. شاید رفته باشد. هرگز دوباره فرستاده نمی‌شود.
            await delivery.abandon(session, claimed.id, send.reason or "unknown")
            await _settle_draft(session, claimed.answered_message_id, sent=False)
    return send.status


async def _settle_draft(session: AsyncSession, answered_message_id: int, *, sent: bool) -> None:
    """پیش‌نویس مربوط به این پیام را هم‌راستا کن، اگر پیش‌نویسی بوده."""
    run = (
        await session.execute(select(AiRun).where(AiRun.message_id == answered_message_id))
    ).scalar_one_or_none()
    if run is None:
        return
    draft = (
        await session.execute(select(Draft).where(Draft.ai_run_id == run.id))
    ).scalar_one_or_none()
    if draft is None or draft.status in (DraftStatus.sent.value, DraftStatus.failed.value):
        return
    if sent:
        await drafts.mark_sent(session, draft.id)
    else:
        await drafts.mark_failed(session, draft.id)


async def send_draft_now(
    draft_id: int,
    *,
    channels: Mapping[str, OutboundChannel],
    gates: Mapping[str, AccountGate],
    sleep: bool = True,
) -> str:
    """پیش‌نویس تأییدشده را در صندوق خروج بگذار و همان‌جا بفرست.

    سه مرحله‌ی جدا و عمدی: تراکنش اول تصمیم را تثبیت می‌کند، ارسال بیرون از هر
    تراکنشی انجام می‌شود، تراکنش دوم نتیجه را ثبت می‌کند (`ADR-030`). منتور
    همچنان نتیجه‌ی واقعی را می‌بیند، نه «در صف گذاشته شد».

    اگر کارگر زودتر همان تحویل را برداشته باشد، وضعیت نهایی از خود سطر خوانده
    می‌شود — دوباره فرستاده نمی‌شود.
    """
    async with session_scope() as session:
        outcome, delivery_id = await queue_approved_draft(
            session, draft_id, channels=channels, gates=gates
        )
    if delivery_id is None:
        return f"{outcome.outcome} {outcome.detail or ''}".strip()

    async with session_scope() as session:
        claimed = await delivery.claim(session, delivery_id)

    if claimed is not None:
        status = await deliver_claimed(claimed, channels=channels, gates=gates, sleep=sleep)
        return status.value

    async with session_scope() as session:
        return await delivery.status_of(session, delivery_id) or "unknown"


async def drain_deliveries(
    *,
    channels: Mapping[str, OutboundChannel],
    gates: Mapping[str, AccountGate],
    sleep: bool = True,
    limit: int = 20,
) -> int:
    """صندوق خروج را خالی کن.

    هر برداشتن در تراکنش خودش تثبیت می‌شود **پیش از** ارسال، و ثبت نتیجه در
    تراکنشی دیگر پس از آن. هیچ ارسالی داخل تراکنش نیست.
    """
    delivered = 0
    for _ in range(limit):
        async with session_scope() as session:
            claimed = await delivery.claim_next(session)
        if claimed is None:
            break
        await deliver_claimed(claimed, channels=channels, gates=gates, sleep=sleep)
        delivered += 1
    return delivered


async def run_forever(
    *,
    worker_id: str,
    model_client: ModelClient,
    embedder: EmbeddingProvider | None,
    channels: Mapping[str, OutboundChannel],
    gates: Mapping[str, AccountGate],
    notifier: DraftNotifier | None,
) -> None:
    last_sweep = datetime.now(UTC)
    while True:
        async with session_scope() as session:
            job = await queue.claim(session, worker_id=worker_id, kinds=HANDLED_KINDS)

        if job is None:
            # صف کار خالی است؛ حالا صندوق خروج. ارسال عمداً پس از پردازش می‌آید تا
            # پیام تازه زودتر تصمیمش گرفته شود.
            await drain_deliveries(channels=channels, gates=gates)

            if datetime.now(UTC) - last_sweep > STALE_LOCK_AFTER:
                async with session_scope() as session:
                    freed = await queue.release_stale(session, older_than=STALE_LOCK_AFTER)
                if freed:
                    log.warning("stale_jobs_released", count=freed)
                # تحویل‌هایی که کارگرشان وسط ارسال مرده. هرگز دوباره فرستاده
                # نمی‌شوند؛ فقط رها و بلند اعلام می‌شوند تا آدمی نگاه کند.
                async with session_scope() as session:
                    await delivery.abandon_stale(session)
                last_sweep = datetime.now(UTC)
            await asyncio.sleep(IDLE_SLEEP_SECONDS)
            continue

        try:
            async with session_scope() as session:
                if job.kind == memory_job.JOB_KIND:
                    report = await memory_job.run(
                        session,
                        int(job.payload["conversation_id"]),
                        model_client=model_client,
                    )
                    detail = f"stored={len(report.stored)} rejected={len(report.rejected)}"
                    outcome = JobOutcome("memory_extracted", detail)
                else:
                    outcome = await process_message(
                        session,
                        int(job.payload["message_id"]),
                        model_client=model_client,
                        embedder=embedder,
                        channels=channels,
                        gates=gates,
                        notifier=notifier,
                    )
                await queue.complete(session, job.id)
            log.info("job_done", job_id=job.id, outcome=outcome.outcome, detail=outcome.detail)

            # اعلان و ارسال، هر دو بیرون از تراکنش بالا و پس از تثبیت آن.
            if outcome.outcome == "drafted" and notifier is not None and outcome.detail:
                await notify_draft(int(outcome.detail), notifier)
            # پاسخی که همین الان تصمیمش گرفته شد نباید تا خالی شدن صف کار منتظر بماند.
            await drain_deliveries(channels=channels, gates=gates)
        except Exception as exc:  # noqa: BLE001 - یک کار خراب نباید کارگر را بکشد
            log.exception("job_failed", job_id=job.id)
            with contextlib.suppress(Exception):
                async with session_scope() as session:
                    await queue.fail(
                        session,
                        job.id,
                        f"{type(exc).__name__}: {exc}",
                        retry_in=timedelta(minutes=2),
                    )
