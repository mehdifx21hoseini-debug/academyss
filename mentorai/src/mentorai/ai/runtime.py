"""خط پردازش یک پیام: بازیابی، تصمیم، تولید، ثبت.

قاعده‌ی حاکم بر کل این ماژول: **جهت شکست به سمت انسان است.** هر مسیری که به یقین
نرسد — خطای مدل، خروجی نامعتبر، نبود منبع، اطمینان پایین — به سکوت ختم می‌شود، نه به
پاسخ حدسی. سکوت یعنی پیام خوانده‌نشده می‌ماند و منتور در تلگرام خودش می‌بیندش (ADR-009).
"""

from __future__ import annotations

import enum
from collections.abc import Sequence
from dataclasses import dataclass

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai import budget, guard
from mentorai.ai.client import ModelCall, ModelClient
from mentorai.ai.decision import deterministic_trigger
from mentorai.ai.prompt import build_system_prompt, build_user_content
from mentorai.ai.schema import PROMPT_VERSION, ModelAnswer
from mentorai.config import get_settings
from mentorai.db.models import (
    AiRun,
    Conversation,
    Escalation,
    MentorAccount,
    Message,
    Outcome,
    Sender,
    SilenceClass,
)
from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.knowledge.retrieval import Hit, search
from mentorai.media import review
from mentorai.media import store as media_store
from mentorai.media.statement import StatementMetrics
from mentorai.memory import store as memory_store

log = structlog.get_logger(__name__)

# زیر این آستانه، پاسخ ارسال نمی‌شود. عدد اولیه محافظه‌کارانه انتخاب شده؛ کالیبره
# کردنش کار داده است نه سلیقه، و برای همین confidence در هر اجرا ثبت می‌شود.
CONFIDENCE_THRESHOLD = 0.7

# چند پیام آخر مکالمه که به‌عنوان زمینه فرستاده می‌شوند.
HISTORY_TURNS = 4

# دلیل ثبت‌شده برای پاسخی که از محاسبه‌ی استیتمنت آمده، نه از مدل.
STATEMENT_REASON = "statement_review"


class SilenceReason(enum.StrEnum):
    rule_identity_question = "rule_identity_question"
    rule_money = "rule_money"
    rule_complaint = "rule_complaint"
    rule_account = "rule_account"
    rule_explicit_human_request = "rule_explicit_human_request"
    unsupported_media = "unsupported_media"
    no_sources = "no_sources"
    model_error = "model_error"
    model_flagged = "model_flagged"
    low_confidence = "low_confidence"
    budget_exhausted = "budget_exhausted"
    empty_answer = "empty_answer"
    ungrounded_money = "ungrounded_money"
    # سکوت عمدی برای پیام قطعاً خارج از حوزه (ADR-042). **موتور فعلی هرگز آن را تولید
    # نمی‌کند**؛ فقط لایه‌ی ثبت آن را می‌شناسد تا موتور بعدی (RO-4) روی آن بنشیند.
    out_of_domain = "out_of_domain"


# کلاس هر دلیل سکوت (ADR-042). صریح است، نه حدسی: هر عضو `SilenceReason` باید اینجا
# باشد و تستی همین را می‌سنجد، تا دلیل تازه بی‌صدا به پیش‌فرض نیفتد.
#
# پنج `rule_*` بر پایه‌ی رفتار فعلی کد `needs_human` هستند: همگی `HANDOFF_REASONS`‌اند،
# یعنی گفتگو برای منتور ارجاع می‌شود (`escalation.py`).
_SILENCE_CLASS: dict[str, SilenceClass] = {
    SilenceReason.rule_identity_question.value: SilenceClass.needs_human,
    SilenceReason.rule_money.value: SilenceClass.needs_human,
    SilenceReason.rule_complaint.value: SilenceClass.needs_human,
    SilenceReason.rule_account.value: SilenceClass.needs_human,
    SilenceReason.rule_explicit_human_request.value: SilenceClass.needs_human,
    SilenceReason.unsupported_media.value: SilenceClass.needs_human,
    SilenceReason.no_sources.value: SilenceClass.needs_human,
    SilenceReason.model_flagged.value: SilenceClass.needs_human,
    SilenceReason.low_confidence.value: SilenceClass.needs_human,
    SilenceReason.ungrounded_money.value: SilenceClass.needs_human,
    SilenceReason.model_error.value: SilenceClass.system_fault,
    SilenceReason.budget_exhausted.value: SilenceClass.system_fault,
    SilenceReason.empty_answer.value: SilenceClass.system_fault,
    SilenceReason.out_of_domain.value: SilenceClass.intentional,
}


def silence_class_of(reason: str) -> SilenceClass:
    """کلاس یک دلیل سکوت. خالص است و به پایگاه داده دست نمی‌زند.

    **دلیل ناشناخته `needs_human` است** (جهت امن): سکوتی که نمی‌شناسیم نباید به‌عنوان
    «عمدی» از شاخص انتظار و از فهرست ارجاع‌ها بیرون برود.
    """
    return _SILENCE_CLASS.get(reason, SilenceClass.needs_human)


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
    # کلاس فقط برای سکوت است؛ پاسخ، حتی پاسخ جزئی، کلاس ندارد.
    silence_class = silence_class_of(reason) if outcome is Outcome.silence else None

    run = AiRun(
        conversation_id=message.conversation_id,
        message_id=message.id,
        outcome=outcome.value,
        reason=reason,
        silence_class=silence_class.value if silence_class is not None else None,
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

    # سکوت عمدی (خارج از حوزه) **ردیف ارجاع نمی‌سازد**: پیامی نیست که منتور باید جواب بدهد،
    # پس نباید وارد `/pending` و شاخص انتظار شود. فقط `ai_runs` می‌ماند (ADR-042).
    if silence_class is not None and silence_class is not SilenceClass.intentional:
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


def _statement_answer(metrics: StatementMetrics, *, seed: int) -> str:
    """پیش‌نویس بررسی استیتمنت.

    عمداً بدون فراخوانی مدل ساخته می‌شود. اعداد اینجا محاسبه شده‌اند و قطعی‌اند؛ عبور
    دادنشان از مدل فقط یک جای تازه برای تغییر عدد می‌سازد، بدون اینکه چیزی اضافه کند.
    منتور در حالت پیش‌نویس متن را می‌بیند و هر جا لازم بود اصلاحش می‌کند.

    `seed` شناسه‌ی پیام است و شکلِ سلام و بدرقه را تعیین می‌کند — تا دو دانشجو یک
    جمله‌ی یکسان نگیرند، ولی یک استیتمنت دوباره ساخته‌شده همان متن را بدهد.
    """
    return review.render(metrics, seed=seed)


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

    answer = _statement_answer(metrics, seed=message.id)
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


def silence_reason_for(
    answer: ModelAnswer,
    hits: Sequence[Hit],
    *,
    confidence_threshold: float = CONFIDENCE_THRESHOLD,
) -> tuple[str | None, str | None]:
    """(دلیل سکوت، جزئیات). دلیل `None` یعنی این پاسخ می‌رود.

    خالص است و به پایگاه داده دست نمی‌زند، تا مقایسه‌ی مدل‌ها (`model_compare.py`) دقیقاً
    همین دروازه را بگذراند و نه نسخه‌ای که با گذر زمان از آن جدا شود. ترتیب مهم است:
    اولی که بگیرد دلیل ثبت‌شده است.

    جزئیات فقط برای سکوت قیمتی پر است: همان عددی که منبعی نداشت.
    """
    if answer.needs_human:
        return SilenceReason.model_flagged.value, None
    if not answer.answer.strip():
        return SilenceReason.empty_answer.value, None
    if answer.confidence < confidence_threshold:
        return SilenceReason.low_confidence.value, None
    # عددی با واحد پول که در هیچ منبع رسمی و در خود سؤال نبود. این بررسی در کد است و به
    # اطمینان مدل کاری ندارد: قیمت اشتباه، بدترین خطای ممکن این سیستم است و برخلاف
    # توضیح ناقص، قابل جبران نیست.
    bad = guard.ungrounded_money(answer.answer, hits=hits)
    if bad is not None:
        return SilenceReason.ungrounded_money.value, bad
    return None, None


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

    # سقف هزینه پیش از فراخوانی بررسی می‌شود. اگر پر باشد، همان سکوتی رخ می‌دهد که
    # هر شکست دیگری: پیام خوانده‌نشده می‌ماند و منتور خودش می‌بیندش (ADR-026).
    if not (await budget.check(session, purpose=budget.Purpose.answer)).may_call:
        run = await _record(
            session,
            message=message,
            outcome=Outcome.silence,
            reason=SilenceReason.budget_exhausted.value,
            hits=hits,
        )
        return RunResult(
            outcome=Outcome.silence,
            reason=SilenceReason.budget_exhausted.value,
            ai_run_id=run.id,
        )

    history = await _recent_history(session, message.conversation_id, message.id)
    conversation = await session.get_one(Conversation, message.conversation_id)
    account = await session.get_one(MentorAccount, conversation.account_id)
    memories = memory_store.render(await memory_store.load_active(session, conversation.student_id))
    call = await model_client.complete(
        system=build_system_prompt(account.mentor_name),
        user=build_user_content(question=question, hits=hits, history=history, memories=memories),
    )
    # ثبت مصرف بی‌قیدوشرط است، حتی وقتی فراخوانی خطا داد: توکن مصرف‌شده حتی در
    # پاسخ ناقص هم پول است.
    await budget.record(
        session,
        purpose=budget.Purpose.answer,
        model=call.model,
        input_tokens=call.input_tokens,
        output_tokens=call.output_tokens,
        cache_read_tokens=call.cache_read_tokens,
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
    silence_reason, blocked_amount = silence_reason_for(
        answer, hits, confidence_threshold=confidence_threshold
    )
    if silence_reason == SilenceReason.ungrounded_money.value:
        log.error("ungrounded_money_blocked", message_id=message.id, amount=blocked_amount)

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
