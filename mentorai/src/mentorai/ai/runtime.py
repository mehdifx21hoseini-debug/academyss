"""خط پردازش یک پیام: بازیابی، تصمیم، تولید، ثبت.

قاعده‌ی حاکم بر کل این ماژول: **جهت شکست به سمت انسان است.** هر مسیری که به یقین
نرسد — خطای مدل، خروجی نامعتبر، نبود منبع، اطمینان پایین — به سکوت ختم می‌شود، نه به
پاسخ حدسی. سکوت یعنی پیام خوانده‌نشده می‌ماند و منتور در تلگرام خودش می‌بیندش (ADR-009).
"""

from __future__ import annotations

import enum
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai.client import ModelCall, ModelClient
from mentorai.ai.decision import deterministic_trigger
from mentorai.ai.prompt import SYSTEM_PROMPT, build_user_content
from mentorai.ai.schema import PROMPT_VERSION
from mentorai.config import get_settings
from mentorai.db.models import AiRun, Conversation, Escalation, Message, Outcome, Sender
from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.knowledge.retrieval import Hit, search
from mentorai.media import review
from mentorai.media import store as media_store
from mentorai.media.statement import StatementMetrics
from mentorai.memory import store as memory_store

# زیر این آستانه، پاسخ ارسال نمی‌شود. عدد اولیه محافظه‌کارانه انتخاب شده؛ کالیبره
# کردنش کار داده است نه سلیقه، و برای همین confidence در هر اجرا ثبت می‌شود.
CONFIDENCE_THRESHOLD = 0.7

# چند پیام آخر مکالمه که به‌عنوان زمینه فرستاده می‌شوند.
HISTORY_TURNS = 4

# دلیل ثبت‌شده برای پاسخی که از محاسبه‌ی استیتمنت آمده، نه از مدل.
STATEMENT_REASON = "statement_review"


class SilenceReason(enum.StrEnum):
    rule_money = "rule_money"
    rule_complaint = "rule_complaint"
    rule_account = "rule_account"
    rule_explicit_human_request = "rule_explicit_human_request"
    unsupported_media = "unsupported_media"
    no_sources = "no_sources"
    model_error = "model_error"
    model_flagged = "model_flagged"
    low_confidence = "low_confidence"
    empty_answer = "empty_answer"


@dataclass(frozen=True)
class RunResult:
    outcome: Outcome
    reason: str
    ai_run_id: int
    answer_text: str | None = None


def _serialise(hits: list[Hit]) -> list[dict[str, object]]:
    """اسناد بازیابی‌شده با امتیاز و رتبه، برای ثبت در اجرا.

    امتیازها دور ریخته نمی‌شوند: بدون آن‌ها نمی‌شود فهمید بازیابی ضعیف بوده یا مدل.
    """
    return [
        {
            "chunk_id": h.chunk_id,
            "document_id": h.document_id,
            "score": round(h.score, 6),
            "vector_rank": h.vector_rank,
            "text_rank": h.text_rank,
            "source_class": h.source_class,
            "authority": h.authority,
        }
        for h in hits
    ]


async def _recent_history(
    session: AsyncSession, conversation_id: int, before_message_id: int
) -> list[tuple[str, str]]:
    rows = (
        await session.execute(
            select(Message.sender, Message.text)
            .where(
                Message.conversation_id == conversation_id,
                Message.id < before_message_id,
                Message.text.isnot(None),
            )
            .order_by(Message.id.desc())
            .limit(HISTORY_TURNS)
        )
    ).all()
    labels = {
        Sender.student.value: "دانشجو",
        Sender.assistant.value: "دستیار",
        Sender.mentor.value: "منتور",
    }
    return [(labels.get(sender, sender), text) for sender, text in reversed(rows) if text]


async def _record(
    session: AsyncSession,
    *,
    message: Message,
    outcome: Outcome,
    reason: str,
    hits: list[Hit],
    call: ModelCall | None = None,
    effort: str | None = None,
    confidence: float | None = None,
    response_text: str | None = None,
) -> AiRun:
    run = AiRun(
        conversation_id=message.conversation_id,
        message_id=message.id,
        outcome=outcome.value,
        reason=reason,
        confidence=confidence,
        model=call.model if call else None,
        prompt_version=PROMPT_VERSION,
        effort=effort,
        latency_ms=call.latency_ms if call else None,
        input_tokens=call.input_tokens if call else None,
        output_tokens=call.output_tokens if call else None,
        cache_read_tokens=call.cache_read_tokens if call else None,
        retrieved=_serialise(hits),
        response_text=response_text,
        error=call.error if call else None,
    )
    session.add(run)
    await session.flush()

    if outcome is Outcome.silence:
        # ارجاع برای دانشجو نامرئی است؛ این ثبت تنها راه دیدن آن است.
        session.add(
            Escalation(
                conversation_id=message.conversation_id,
                message_id=message.id,
                ai_run_id=run.id,
                reason=reason,
            )
        )
    return run


def _statement_answer(metrics: StatementMetrics) -> str:
    """پیش‌نویس بررسی استیتمنت.

    عمداً بدون فراخوانی مدل ساخته می‌شود. اعداد اینجا محاسبه شده‌اند و قطعی‌اند؛ عبور
    دادنشان از مدل فقط یک جای تازه برای تغییر عدد می‌سازد، بدون اینکه چیزی اضافه کند.
    منتور در حالت پیش‌نویس متن را می‌بیند و هر جا لازم بود اصلاحش می‌کند.
    """
    return review.render(metrics)


async def _media_silence(session: AsyncSession, message: Message) -> RunResult:
    run = await _record(
        session,
        message=message,
        outcome=Outcome.silence,
        reason=SilenceReason.unsupported_media.value,
        hits=[],
    )
    return RunResult(
        outcome=Outcome.silence, reason=SilenceReason.unsupported_media.value, ai_run_id=run.id
    )


async def _handle_media(
    session: AsyncSession, message: Message
) -> tuple[RunResult | None, str | None]:
    """نتیجه‌ی پیامی که فایل دارد، یا پرسشی که باید با آن ادامه داد.

    فقط استیتمنتی که خوانده شده و اعدادش در آمده پاسخ می‌گیرد. پلن و هر فایل
    خوانده‌نشده به منتور می‌رود: بررسی پلن معاملاتی قضاوت کارشناسی است، نه بازیابی.

    تصویر خوانده می‌شود ولی تا روشن شدن `ANSWER_FROM_IMAGES` پاسخ نمی‌گیرد. توصیفش
    ذخیره و در پنل دیده می‌شود تا مالک کیفیتش را بسنجد و بعد تصمیم بگیرد (ADR-022).
    """
    row = await media_store.load(session, message.id)
    if row is not None and row.kind == "voice":
        # ویسِ رونویسی‌شده دیگر فایل نیست؛ یک سؤال متنی است و از همان مسیر
        # آزموده‌شده رد می‌شود. رونویسی بد هم به پاسخ غلط ختم نمی‌شود: سندی پیدا
        # نمی‌شود و سیستم ساکت می‌ماند.
        if not row.extracted_text:
            return await _media_silence(session, message), None
        return None, row.extracted_text

    if row is not None and row.kind == "image":
        if not get_settings().answer_from_images or not row.extracted_text:
            return await _media_silence(session, message), None
        caption = (message.text or "").strip()
        described = f"[توصیف تصویری که دانشجو فرستاده]\n{row.extracted_text}"
        return None, f"{caption}\n{described}" if caption else described

    metrics: StatementMetrics | None = None
    if row is not None and row.kind == "statement" and row.metrics:
        # ساختار ذخیره‌شده که با کد امروز نخواند None برمی‌گرداند، و همین پیام هم
        # به منتور می‌رود: عدد نیمه‌خوانده بدتر از نخواندن است.
        metrics = StatementMetrics.from_dict(row.metrics)

    if metrics is None:
        return await _media_silence(session, message), None

    answer = _statement_answer(metrics)
    run = await _record(
        session,
        message=message,
        outcome=Outcome.answer,
        reason=STATEMENT_REASON,
        hits=[],
        confidence=1.0,
        response_text=answer,
    )
    return (
        RunResult(
            outcome=Outcome.answer, reason=STATEMENT_REASON, ai_run_id=run.id, answer_text=answer
        ),
        None,
    )


async def handle_message(
    session: AsyncSession,
    message: Message,
    *,
    model_client: ModelClient,
    embedder: EmbeddingProvider | None = None,
    confidence_threshold: float = CONFIDENCE_THRESHOLD,
) -> RunResult:
    question = message.text or ""

    # مرحله‌ی اول: قواعد قطعی، پیش از هر فراخوانی مدل. برای موضوعی مثل شکایت یا
    # پرداخت نباید به قضاوت مدل تکیه کرد، و این مسیر هزینه‌ی مدل هم ندارد.
    trigger = deterministic_trigger(question)
    if trigger is not None:
        reason = f"rule_{trigger.value}" if not trigger.value.startswith("rule_") else trigger.value
        run = await _record(
            session, message=message, outcome=Outcome.silence, reason=reason, hits=[]
        )
        return RunResult(outcome=Outcome.silence, reason=reason, ai_run_id=run.id)

    # پیامی که فایل همراه دارد — عکس، ویس، سند — از روی متنش پاسخ داده نمی‌شود.
    # کپشن معمولاً به خود فایل ارجاع می‌دهد («این ورودم درسته؟»)، پس پاسخ دادن به
    # کپشن یعنی پاسخ دادن به سؤالی که دیده نشده است (ADR-017). تنها استثنا فایلی
    # است که واقعاً خوانده شده باشد.
    if message.media_type is not None:
        outcome, from_image = await _handle_media(session, message)
        if outcome is not None:
            return outcome
        # تنها راه رسیدن به اینجا: تصویری که خوانده شده و پاسخ‌دهی از تصویر روشن است.
        question = from_image or question

    hits = await search(session, question, embedder=embedder)
    if not hits:
        run = await _record(
            session,
            message=message,
            outcome=Outcome.silence,
            reason=SilenceReason.no_sources.value,
            hits=[],
        )
        return RunResult(
            outcome=Outcome.silence, reason=SilenceReason.no_sources.value, ai_run_id=run.id
        )

    history = await _recent_history(session, message.conversation_id, message.id)
    conversation = await session.get_one(Conversation, message.conversation_id)
    memories = memory_store.render(await memory_store.load_active(session, conversation.student_id))
    call = await model_client.complete(
        system=SYSTEM_PROMPT,
        user=build_user_content(question=question, hits=hits, history=history, memories=memories),
    )

    if call.answer is None:
        run = await _record(
            session,
            message=message,
            outcome=Outcome.silence,
            reason=SilenceReason.model_error.value,
            hits=hits,
            call=call,
            effort=model_client.effort,
        )
        return RunResult(
            outcome=Outcome.silence, reason=SilenceReason.model_error.value, ai_run_id=run.id
        )

    answer = call.answer
    silence_reason: str | None = None
    if answer.needs_human:
        silence_reason = SilenceReason.model_flagged.value
    elif not answer.answer.strip():
        silence_reason = SilenceReason.empty_answer.value
    elif answer.confidence < confidence_threshold:
        silence_reason = SilenceReason.low_confidence.value

    if silence_reason is not None:
        run = await _record(
            session,
            message=message,
            outcome=Outcome.silence,
            reason=silence_reason,
            hits=hits,
            call=call,
            effort=model_client.effort,
            confidence=answer.confidence,
            response_text=answer.answer or None,
        )
        return RunResult(outcome=Outcome.silence, reason=silence_reason, ai_run_id=run.id)

    run = await _record(
        session,
        message=message,
        outcome=Outcome.answer,
        reason=answer.reason[:64] or "answered",
        hits=hits,
        call=call,
        effort=model_client.effort,
        confidence=answer.confidence,
        response_text=answer.answer,
    )
    return RunResult(
        outcome=Outcome.answer,
        reason=run.reason,
        ai_run_id=run.id,
        answer_text=answer.answer,
    )
