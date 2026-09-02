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
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import drafts, escalation
from mentorai.ai.client import ModelClient
from mentorai.ai.runtime import handle_message
from mentorai.conversation import assistant_may_answer
from mentorai.db.models import (
    AiRun,
    Conversation,
    Draft,
    MentorAccount,
    Message,
    Outcome,
    ReplyMode,
)
from mentorai.db.session import session_scope
from mentorai.jobs import queue
from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.telegram.safety import AccountGate
from mentorai.telegram.sender import OutboundChannel, SendStatus, deliver_answer

log = structlog.get_logger(__name__)

JOB_KIND = "answer_message"
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
        if notifier is not None:
            draft.control_message_id = await notifier.notify(
                account=account, draft=draft, question=message.text or ""
            )
        return JobOutcome("drafted", str(draft.id))

    channel = channels.get(account.slug)
    gate = gates.get(account.slug)
    if channel is None or gate is None:
        return JobOutcome("no_channel", account.slug)

    send = await deliver_answer(
        session,
        account=account,
        conversation=conversation,
        answered_message=message,
        body=result.answer_text,
        gate=gate,
        channel=channel,
        sleep=sleep,
    )
    return JobOutcome(send.status.value, send.reason)


async def send_approved_draft(
    session: AsyncSession,
    draft_id: int,
    *,
    channels: Mapping[str, OutboundChannel],
    gates: Mapping[str, AccountGate],
    sleep: bool = True,
) -> JobOutcome:
    """پیش‌نویسی که منتور تأیید یا ویرایش کرده را بفرست."""
    draft = await session.get_one(Draft, draft_id)
    if draft.final_text is None:
        return JobOutcome("no_final_text")

    conversation = await session.get_one(Conversation, draft.conversation_id)
    account = await session.get_one(MentorAccount, conversation.account_id)
    # پیامی که این پیش‌نویس پاسخ آن است. علامت خوانده‌شدن باید تا همین برود، نه جلوتر.
    run = await session.get_one(AiRun, draft.ai_run_id)
    answered_message = await session.get_one(Message, run.message_id)

    channel = channels.get(account.slug)
    gate = gates.get(account.slug)
    if channel is None or gate is None:
        await drafts.mark_failed(session, draft_id)
        return JobOutcome("no_channel", account.slug)

    send = await deliver_answer(
        session,
        account=account,
        conversation=conversation,
        answered_message=answered_message,
        body=draft.final_text,
        gate=gate,
        channel=channel,
        sleep=sleep,
    )
    if send.status is SendStatus.sent:
        await drafts.mark_sent(session, draft_id)
    else:
        await drafts.mark_failed(session, draft_id)
    return JobOutcome(send.status.value, send.reason)


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
            job = await queue.claim(session, worker_id=worker_id, kinds=[JOB_KIND])

        if job is None:
            if datetime.now(UTC) - last_sweep > STALE_LOCK_AFTER:
                async with session_scope() as session:
                    freed = await queue.release_stale(session, older_than=STALE_LOCK_AFTER)
                if freed:
                    log.warning("stale_jobs_released", count=freed)
                last_sweep = datetime.now(UTC)
            await asyncio.sleep(IDLE_SLEEP_SECONDS)
            continue

        try:
            async with session_scope() as session:
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
