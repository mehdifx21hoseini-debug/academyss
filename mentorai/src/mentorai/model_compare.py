"""مقایسه‌ی کور مدل‌ها روی پرسش‌های واقعی (`mentorai compare-run` و `compare-report`).

سؤالی که جواب می‌دهد: **کدام مدل پیش‌نویس‌هایی می‌نویسد که منتور کمتر بازنویسی کند؟**
نه «کدام باهوش‌تر است». این همان سنجه‌ی اصلی پروژه است (ADR-018).

سه مرحله، و هر کدام جدا آزمودنی:

1. **اجرا.** هر پرسش با **همان سندهای بازیابی‌شده** و **همان دستور سیستمی تولید** به همه‌ی
   نامزدها داده می‌شود و نتیجه از **همان دروازه‌ی تولید** (`silence_reason_for`) می‌گذرد.
   پس تفاوت فقط از خود مدل است. پرسشی که مدل هرگز نمی‌دیدش (قاعده‌ی قطعی، بی‌سند) کنار
   گذاشته و شمرده می‌شود، نه به مدل‌ها داده.
2. **برگه‌ی کور.** پاسخ‌ها برای هر پرسش با ترتیب تصادفی و **بدون نام مدل** در یک فایل
   می‌آیند. داور (منتور) امتیاز ۰ تا ۳ می‌دهد و می‌گوید پاسخ چیزی از خودش ساخته یا نه.
   نام مدل‌ها فقط در `key.json` است که تا پایان داوری نباید دست داور برسد.
3. **گزارش.** برگه‌ی پرشده با کلید یکی می‌شود و اعداد درمی‌آیند، با بازه‌ی اطمینان و
   آزمون علامت، نه فقط میانگین.

محدودیت‌هایی که باید با خود نتیجه گفته شوند:

- **کور کامل نیست.** سبک نوشتار هر مدل (فهرست، طول، لحن) می‌تواند لو بدهد.
- **تک‌پیام است.** تاریخچه‌ی مکالمه و حافظه‌ی دانشجو در کار نیست؛ مسیر «یک پرسش» سنجیده
  می‌شود، نه مکالمه‌ی چندنوبتی.
- **نمونه‌ی کم نتیجه‌ی قطعی نمی‌دهد.** گزارش خودش می‌گوید وقتی n کوچک است.

⚠️ فایل‌های خروجی با `--from-db` پیام واقعی دانشجو دارند. فقط برای صاحبشان خواندنی ساخته
می‌شوند، شماره و ایمیل و نام کاربری در آن‌ها پوشانده می‌شود، و **هرگز نباید به مخزن بروند**
(`mentorai/model-compare/` در `.gitignore` است).
"""

from __future__ import annotations

import asyncio
import csv
import io
import json
import math
import os
import random
import re
import statistics
from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai.budget import PRICES, Price
from mentorai.ai.client import (
    _ANTHROPIC_EFFORTS,
    _NO_EFFORT_MODELS,
    DEFAULT_EFFORT,
    AnthropicClient,
    ChatAndVision,
)
from mentorai.ai.decision import deterministic_trigger
from mentorai.ai.prompt import SYSTEM_PROMPT, build_user_content
from mentorai.ai.runtime import CONFIDENCE_THRESHOLD, silence_reason_for
from mentorai.ai.schema import PROMPT_VERSION
from mentorai.config import Settings
from mentorai.db.models import Conversation, ExcludedChat, Message
from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.knowledge.retrieval import Hit, search
from mentorai.media import office
from mentorai.text import normalize_for_search

SHEET_NAME = "blind_sheet.csv"
KEY_NAME = "key.json"
GUIDE_NAME = "grader_guide.txt"
REPORT_NAME = "report.txt"
KEY_VERSION = 1

SILENT = "ساکت می‌ماند"
SENT = "ارسال می‌شد"
NO_ANSWER = "— پاسخی نداد —"

# پایین‌تر از این، «پیام» سؤال نیست؛ بالاتر از این، پیام بلند است و برگه را ناخواناتر می‌کند.
MIN_QUESTION_CHARS = 8
MAX_QUESTION_CHARS = 600
DB_POOL = 5000
MAX_SOURCES_CHARS = 2500
MIN_SAMPLE_FOR_CONCLUSION = 30

THRESHOLDS = (0.5, 0.6, 0.7, 0.8, 0.9)


class CompareError(Exception):
    """ورودی یا پیکربندی نادرست؛ پیام برای مالک است و بی‌خطر چاپ می‌شود."""


class CostLimitExceeded(CompareError):
    """هزینه‌ی برآوردشده از سقف می‌گذرد. پیش از خرج بیشتر متوقف می‌شود."""

    def __init__(self, projected: float, limit: float) -> None:
        super().__init__(
            f"هزینه‌ی برآوردشده {projected:.2f} دلار است و از سقف {limit:.2f} می‌گذرد. "
            "پرسش‌ها را کمتر کنید (--limit) یا سقف را آگاهانه بالا ببرید (--max-cost-usd)."
        )
        self.projected = projected


# ---------------------------------------------------------------------------
# نامزدها
# ---------------------------------------------------------------------------

_SPEC = re.compile(
    r"^(?P<provider>[a-z]+):(?P<model>[^:@\s]+)(?::(?P<effort>[a-z]+))?"
    r"(?:@(?P<pin>\d+(?:\.\d+)?)/(?P<pout>\d+(?:\.\d+)?))?$"
)


@dataclass(frozen=True)
class Candidate:
    id: str
    spec: str
    provider: str
    model: str
    effort: str | None
    price: Price | None

    @property
    def name(self) -> str:
        return f"{self.provider}:{self.model}:{self.effort or 'پیش‌فرض'}"


def parse_candidate(spec: str, *, index: int) -> Candidate:
    """`provider:model[:effort][@ورودی/خروجی]`، مثلاً `openai:gpt-x:low@0.25/2.0`.

    قیمت (دلار برای هر میلیون توکن) برای مدلی که در `budget.PRICES` نیست اجباری است؛
    بدون آن، هزینه‌ی گزارش‌شده و سقف هزینه‌ی خود این اجرا واقعی نیست.
    """
    match = _SPEC.match(spec.strip())
    if match is None:
        raise CompareError(
            f"نامزد «{spec}» را نخواندم. قالب: provider:model[:effort][@ورودی/خروجی]، "
            "مثلاً anthropic:claude-sonnet-5-5:medium"
        )
    provider = match["provider"]
    if provider not in ("anthropic", "openai"):
        raise CompareError(f"ارائه‌دهنده‌ی «{provider}» پشتیبانی نمی‌شود (anthropic یا openai)")
    model = match["model"]
    price = (
        Price(float(match["pin"]), float(match["pout"]))
        if match["pin"] is not None
        else PRICES.get(model)
    )
    if price is None:
        raise CompareError(
            f"قیمت «{model}» را نمی‌دانم. در نامزد بیفزایید: {spec}@ورودی/خروجی "
            "(دلار برای هر میلیون توکن، از صفحه‌ی قیمت ارائه‌دهنده)"
        )
    return Candidate(
        id=f"c{index}",
        spec=spec.strip(),
        provider=provider,
        model=model,
        # عمقی که کلاینت واقعاً می‌فرستد؛ گزارش باید تنظیم واقعی را بگوید، نه «پیش‌فرض».
        effort=match["effort"] or (DEFAULT_EFFORT if provider == "anthropic" else None),
        price=price,
    )


def parse_candidates(specs: Sequence[str]) -> list[Candidate]:
    if len(specs) < 2:
        raise CompareError("برای مقایسه دست‌کم دو نامزد لازم است (--candidate را دوبار بدهید)")
    candidates = [parse_candidate(spec, index=i + 1) for i, spec in enumerate(specs)]
    names = [c.name for c in candidates]
    if len(set(names)) != len(names):
        raise CompareError("دو نامزد یکسان‌اند؛ مقایسه‌ی یک مدل با خودش معنی ندارد")
    return candidates


ClientFactory = Callable[[Candidate], ChatAndVision]


def default_client_factory(settings: Settings) -> ClientFactory:
    """کلاینت واقعی هر نامزد، با همان سقف‌ها و مهلت `.env`."""

    def build(candidate: Candidate) -> ChatAndVision:
        if candidate.provider == "anthropic":
            if candidate.model in _NO_EFFORT_MODELS:
                raise CompareError(f"{candidate.model} پارامتر effort را نمی‌پذیرد")
            effort = candidate.effort or DEFAULT_EFFORT
            if effort not in _ANTHROPIC_EFFORTS:
                raise CompareError(f"effort «{effort}» برای anthropic مجاز نیست")
            return AnthropicClient(
                model=candidate.model,
                effort=effort,  # type: ignore[arg-type]
                max_tokens=settings.ai_max_tokens,
                timeout=settings.ai_timeout_seconds,
            )
        from mentorai.ai.openai_client import OPENAI_EFFORTS, OpenAIClient

        if settings.openai_api_key is None or not settings.openai_api_key.get_secret_value():
            raise CompareError("برای نامزد openai، OPENAI_API_KEY لازم است")
        if candidate.effort is not None and candidate.effort not in OPENAI_EFFORTS:
            raise CompareError(f"effort «{candidate.effort}» برای openai مجاز نیست")
        return OpenAIClient(
            model=candidate.model,
            api_key=settings.openai_api_key.get_secret_value(),
            base_url=settings.openai_base_url,
            effort=candidate.effort,
            max_tokens=settings.ai_max_tokens,
            timeout=settings.ai_timeout_seconds,
        )

    return build


# ---------------------------------------------------------------------------
# پرسش‌ها
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Case:
    id: str
    question: str


_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
_EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
_HANDLE = re.compile(r"(?<![\w@])@[A-Za-z0-9_]{4,}")
# رقم‌ها با یک فاصله یا خط تیره هم‌چسب حساب می‌شوند: شماره و کارت را همین‌طور می‌نویسند
# («0912 345 6789»، «6037-9912-3456-7890»). نقطه و ویرگول عمداً نیست، تا «0.00012345» اعشار
# بماند. بهایش: چند عدد بازار پشت‌هم («1900 1950 2000») و تاریخ با ساعت هم پوشانده
# می‌شوند؛ در برگه‌ای که به دست آدم‌ها می‌رسد، پوشاندن اضافه از جا ماندن شماره بهتر است.
_LONG_DIGITS = re.compile(r"\d(?:[\s-]?\d){8,}")
MASK = "[حذف‌شده]"


def mask_personal(value: str) -> str:
    """ایمیل، نام کاربری تلگرام و رشته‌ی ۹ رقمی و بیشتر (تلفن، کارت، حساب) را بپوشان.

    عددهای کوتاه‌تر (کمتر از ۹ رقم) می‌مانند: «قیمت ۱۹۰۰» یا «لات ۰٫۱» خود پرسش‌اند. ارقام فارسی و عربی
    هم گرفته می‌شوند؛ جدول ترجمه هم‌طول است تا جای هر بازه در متن اصلی همان بماند.
    """
    value = _EMAIL.sub(MASK, value)
    value = _HANDLE.sub(MASK, value)
    spans = [m.span() for m in _LONG_DIGITS.finditer(value.translate(_DIGITS))]
    for start, end in reversed(spans):
        value = value[:start] + MASK + value[end:]
    return value


def load_cases(path: Path, *, limit: int, seed: int) -> list[Case]:
    """پرسش‌ها از یک CSV با ستون `question` (و اختیاری `id`)."""
    raw = path.read_text(encoding="utf-8-sig")
    rows = list(csv.DictReader(io.StringIO(raw)))
    if not rows or "question" not in rows[0]:
        raise CompareError(f"{path.name} ستون «question» ندارد")
    seen: set[str] = set()
    cases: list[Case] = []
    for index, row in enumerate(rows, start=1):
        question = (row.get("question") or "").strip()
        key = normalize_for_search(question)
        if not question or key in seen:
            continue
        seen.add(key)
        cases.append(Case(id=_safe_id(row.get("id"), f"q{index}"), question=question))
    return _sample(cases, limit=limit, seed=seed)


def _safe_id(raw: str | None, fallback: str) -> str:
    """شناسه‌ی پرسش: حروف و رقم و `_.-`، و هرگز با نشانه‌ی فرمول شروع نمی‌شود.

    شناسه در برگه تمیز نمی‌شود (باید پس از داوری عیناً به کلید برگردد)، پس باید از همین‌جا
    امن باشد.
    """
    cleaned = re.sub(r"[^\w.-]", "_", (raw or "").strip())
    if not cleaned:
        return fallback
    return f"q{cleaned}" if cleaned[0] in "=+-@" else cleaned


async def sample_from_database(session: AsyncSession, *, limit: int, seed: int) -> list[Case]:
    """پیام‌های متنیِ واقعی دانشجوها، از میان ۵۰۰۰ پیام اخیر.

    فقط متن بی‌فایل، با طولی که پرسش باشد، و از گفتگوهایی که استثنا نشده‌اند (ADR-008).
    """
    excluded_chat = (
        select(ExcludedChat.id)
        .where(
            ExcludedChat.account_id == Conversation.account_id,
            ExcludedChat.telegram_peer_id == Conversation.telegram_chat_id,
        )
        .exists()
    )
    rows = (
        await session.execute(
            select(Message.id, Message.text)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(
                Message.sender == "student",
                Message.media_type.is_(None),
                Message.text.isnot(None),
                # `Message.text` در همین where صریحاً None نیست؛ mypy آن را نمی‌بیند.
                func.char_length(Message.text).between(MIN_QUESTION_CHARS, MAX_QUESTION_CHARS),  # type: ignore[arg-type]
                ~excluded_chat,
            )
            .order_by(Message.sent_at.desc())
            .limit(DB_POOL)
        )
    ).all()
    seen: set[str] = set()
    cases: list[Case] = []
    for message_id, body in rows:
        key = normalize_for_search(body or "")
        if not key or key in seen:
            continue
        seen.add(key)
        cases.append(Case(id=f"m{message_id}", question=body.strip()))
    return _sample(cases, limit=limit, seed=seed)


def _sample(cases: list[Case], *, limit: int, seed: int) -> list[Case]:
    if len(cases) <= limit:
        return cases
    return random.Random(seed).sample(cases, limit)


# ---------------------------------------------------------------------------
# اجرا
# ---------------------------------------------------------------------------


@dataclass
class CandidateResult:
    outcome: str  # answer | silence | error
    text: str | None = None
    confidence: float | None = None
    needs_human: bool | None = None
    silence_reason: str | None = None
    error: str | None = None
    stop_reason: str | None = None
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    latency_ms: int = 0
    cost_usd: float = 0.0


@dataclass
class CaseRun:
    id: str
    question: str
    sources: str
    order: list[str]
    results: dict[str, CandidateResult]


@dataclass
class RunData:
    candidates: list[Candidate]
    cases: list[CaseRun] = field(default_factory=list)
    excluded: Counter[str] = field(default_factory=Counter)
    spent_usd: float = 0.0
    stopped_early: bool = False
    seed: int = 0
    confidence_threshold: float = CONFIDENCE_THRESHOLD
    created: str = ""


def cost_of(price: Price, *, input_tokens: int, output_tokens: int, cache_read: int = 0) -> float:
    """دلار. توکن نهان با قیمت ورودی حساب می‌شود، مثل `budget.cost_micros` (جهت محافظه‌کار)."""
    return ((input_tokens + cache_read) * price.input_usd + output_tokens * price.output_usd) / 1e6


def render_sources(hits: Sequence[Hit]) -> str:
    parts = [f"[{h.source_class}] {h.title}: {h.content}" for h in hits]
    joined = "\n\n".join(parts)
    return joined if len(joined) <= MAX_SOURCES_CHARS else joined[:MAX_SOURCES_CHARS] + " …"


async def _ask(
    candidate: Candidate,
    client: ChatAndVision,
    *,
    user: str,
    hits: Sequence[Hit],
    threshold: float,
) -> CandidateResult:
    call = await client.complete(system=SYSTEM_PROMPT, user=user)
    assert candidate.price is not None
    cost = cost_of(
        candidate.price,
        input_tokens=call.input_tokens,
        output_tokens=call.output_tokens,
        cache_read=call.cache_read_tokens,
    )
    base = CandidateResult(
        outcome="error",
        input_tokens=call.input_tokens,
        output_tokens=call.output_tokens,
        cache_read_tokens=call.cache_read_tokens,
        latency_ms=call.latency_ms,
        cost_usd=cost,
    )
    if call.answer is None:
        base.error = call.error or "بی‌پاسخ"
        return base
    reason, _ = silence_reason_for(call.answer, hits, confidence_threshold=threshold)
    base.text = call.answer.answer
    base.confidence = call.answer.confidence
    base.needs_human = call.answer.needs_human
    base.silence_reason = reason
    base.outcome = "answer" if reason is None else "silence"
    return base


async def run_comparison(
    session: AsyncSession,
    cases: Sequence[Case],
    candidates: Sequence[Candidate],
    *,
    make_client: ClientFactory,
    embedder: EmbeddingProvider | None = None,
    seed: int = 7,
    max_cost_usd: float = 5.0,
    threshold: float = CONFIDENCE_THRESHOLD,
    dry_run: bool = False,
    progress: Callable[[str], None] | None = None,
) -> RunData:
    """هر پرسش را به همه‌ی نامزدها بده، با همان سندها و همان دستور."""
    # کمبود پیکربندی (کلید، مدل نامجاز) پیش از هر خرج دیده می‌شود. شمارش خشک به هیچ‌کدام
    # نیازی ندارد و نباید کلید بخواهد.
    clients = {} if dry_run else {c.id: make_client(c) for c in candidates}
    run = RunData(
        candidates=list(candidates),
        seed=seed,
        confidence_threshold=threshold,
        created=datetime.now(UTC).isoformat(timespec="seconds"),
    )
    for position, case in enumerate(cases, start=1):
        question = mask_personal(case.question)

        # پرسشی که مدل در تولید هرگز نمی‌بیند، به مدل‌ها داده نمی‌شود.
        trigger = deterministic_trigger(question)
        if trigger is not None:
            run.excluded[f"rule_{trigger.value}"] += 1
            continue
        hits = await search(session, question, embedder=embedder)
        if not hits:
            run.excluded["no_sources"] += 1
            continue
        if dry_run:
            run.cases.append(
                CaseRun(case.id, question, render_sources(hits), [c.id for c in candidates], {})
            )
            continue

        user = build_user_content(question=question, hits=hits)
        results = await asyncio.gather(
            *(_ask(c, clients[c.id], user=user, hits=hits, threshold=threshold) for c in candidates)
        )
        order = [c.id for c in candidates]
        random.Random(f"{seed}:{case.id}").shuffle(order)
        run.cases.append(
            CaseRun(
                case.id,
                question,
                render_sources(hits),
                order,
                {c.id: r for c, r in zip(candidates, results, strict=True)},
            )
        )
        run.spent_usd += sum(r.cost_usd for r in results)

        # پس از نخستین پرسش هزینه‌ی کل برآورد می‌شود: خطا در برآورد باید با چند سنت
        # معلوم شود، نه با خالی شدن حساب.
        if len(run.cases) == 1:
            projected = run.spent_usd * len(cases)
            if projected > max_cost_usd:
                raise CostLimitExceeded(projected, max_cost_usd)
        if run.spent_usd > max_cost_usd:
            run.stopped_early = True
            break
        if progress is not None and (position % 10 == 0 or position == len(cases)):
            progress(f"{position}/{len(cases)} — خرج تا اینجا {run.spent_usd:.3f} دلار")
    return run


# ---------------------------------------------------------------------------
# برگه‌ی کور
# ---------------------------------------------------------------------------


def sheet_header(count: int) -> list[str]:
    header = ["شناسه", "پرسش دانشجو", "منابعی که مدل‌ها دیدند"]
    for k in range(1, count + 1):
        header += [
            f"پاسخ {k}",
            f"وضعیت {k}",
            f"امتیاز {k}",
            f"ساخته‌شده {k}",
        ]
    return [*header, "توضیح"]


_FORMULA_START = ("=", "+", "-", "@", "\t", "\r")


def safe_cell(value: str) -> str:
    """سلولی که اکسل آن را فرمول نمی‌خواند.

    متن دانشجو و پاسخ مدل **نامطمئن‌اند** و منتور برگه را در اکسل باز می‌کند؛ پیامی که با
    `=` یا `+` یا `-` یا `@` شروع شود، مثل `=HYPERLINK(...)`، اجرا می‌شود. راه استاندارد
    (OWASP): یک `'` جلوی آن. اکسل آن را در CSV عیناً نشان می‌دهد، که برای خواندن اشکالی ندارد.
    فاصله‌ی ابتدایی هم نادیده گرفته می‌شود، چون اکسل بعضی نسخه‌ها آن را حذف می‌کند.
    """
    return "'" + value if value.lstrip()[:1] in _FORMULA_START and value.strip() else value


def build_sheet(run: RunData) -> str:
    """CSV برای داور. هیچ نام مدل و ارائه‌دهنده‌ای در آن نیست."""
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(sheet_header(len(run.candidates)))
    for case in run.cases:
        # شناسه تمیز نمی‌شود، چون پس از داوری با همان مقدار به کلید برمی‌گردد؛ پیش‌تر در
        # `_safe_id` از ورودی‌ها پاک شده است.
        row: list[str] = [case.id, safe_cell(case.question), safe_cell(case.sources)]
        for cid in case.order:
            result = case.results[cid]
            row += [
                safe_cell(result.text) if result.text else NO_ANSWER,
                SENT if result.outcome == "answer" else SILENT,
                "",
                "",
            ]
        row.append("")
        writer.writerow(row)
    return buffer.getvalue()


GUIDE = """راهنمای داور
=============

هر ردیف یک پرسش واقعی دانشجوست و چند پاسخ برای آن. نمی‌دانید هر پاسخ از کدام مدل است،
و لازم هم نیست. ستون «منابعی که مدل‌ها دیدند» همان چیزی است که مدل‌ها داشتند؛ پاسخ باید
فقط از همان‌ها بیاید.

برای هر پاسخ، دو ستون را پر کنید:

۱) «امتیاز» (فقط ۰ تا ۳)
   ۳ = همین را می‌شد برای دانشجو فرستاد، بدون هیچ تغییری
   ۲ = با ویرایش کوچک قابل ارسال است
   ۱ = باید کامل بازنویسی شود
   ۰ = غلط یا خطرناک است (چیز نادرست، وعده‌ی سود، قیمت یا قانون اشتباه)

۲) «ساخته‌شده» (فقط ۱ یا خالی)
   اگر پاسخ چیزی گفته که در «منابع» نیست و از خودش افزوده (عدد، قانون، نام، وعده)، ۱
   بنویسید. وگرنه خالی بگذارید. پاسخی ممکن است ساخته‌شده باشد ولی درست از آب درآمده؛
   باز هم ۱ بنویسید.

ستون «وضعیت» می‌گوید سیستم در عمل این پاسخ را می‌فرستاد یا ساکت می‌ماند. شما فقط
**خود متن** را امتیاز بدهید، نه وضعیت را. «— پاسخی نداد —» را خالی بگذارید.

نکته‌ها
- اگر دو پاسخ تقریباً یکی‌اند، هر دو را یک امتیاز بدهید.
- هر پرسش را مستقل از بقیه ببینید. حدس نزنید کدام پاسخ از کدام مدل است.
- فایل را در اکسل پر کنید و به‌صورت «CSV UTF-8» یا xlsx ذخیره کنید. ستون‌ها و ردیف‌ها را
  جابه‌جا یا حذف نکنید.
- اگر پرسشی را نمی‌فهمید، در «توضیح» بنویسید و امتیاز ندهید.

این فایل پیام‌های واقعی دانشجوهاست. جای دیگری نفرستید.
"""


def _private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    path.chmod(0o700)


def _write_private(path: Path, data: str | bytes) -> None:
    """فایل فقط برای صاحبش خواندنی است؛ پیام واقعی دانشجو داخلش است."""
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(data.encode("utf-8") if isinstance(data, str) else data)
    path.chmod(0o600)


def key_document(run: RunData) -> dict[str, Any]:
    return {
        "version": KEY_VERSION,
        "created": run.created,
        "seed": run.seed,
        "prompt_version": PROMPT_VERSION,
        "confidence_threshold": run.confidence_threshold,
        "stopped_early": run.stopped_early,
        "spent_usd": round(run.spent_usd, 6),
        "excluded": dict(run.excluded),
        "candidates": [
            {
                "id": c.id,
                "spec": c.spec,
                "name": c.name,
                "provider": c.provider,
                "model": c.model,
                "effort": c.effort,
                "price_input_usd": c.price.input_usd if c.price else None,
                "price_output_usd": c.price.output_usd if c.price else None,
            }
            for c in run.candidates
        ],
        "cases": [
            {
                "id": case.id,
                "question": case.question,
                "order": case.order,
                "results": {cid: asdict(r) for cid, r in case.results.items()},
            }
            for case in run.cases
        ],
    }


def write_run(run: RunData, out_dir: Path) -> dict[str, Path]:
    """برگه‌ی کور و راهنمای داور را به‌علاوه‌ی کلید خصوصی بنویس."""
    _private_dir(out_dir)
    paths = {
        "sheet": out_dir / SHEET_NAME,
        "guide": out_dir / GUIDE_NAME,
        "key": out_dir / KEY_NAME,
    }
    # BOM: اکسل بدون آن فارسی را خراب می‌خواند.
    _write_private(paths["sheet"], "﻿" + build_sheet(run))
    _write_private(paths["guide"], "﻿" + GUIDE)
    _write_private(paths["key"], json.dumps(key_document(run), ensure_ascii=False, indent=2))
    return paths


# ---------------------------------------------------------------------------
# خواندن برگه‌ی پرشده
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Grade:
    score: int | None
    invented: bool


_TRUE = {"1", "x", "y", "yes", "true", "بله", "آره", "اره", "✓", "✔"}
_FALSE = {"", "0", "no", "false", "نه", "خیر"}


def to_ascii_digits(value: str) -> str:
    return value.translate(_DIGITS)


def _unreadable(path: Path, exc: OSError) -> CompareError:
    """پیام عملی برای فایلی که باز نشد. بیشترین علتش در سرور: مالک و مجوز.

    فرمان داخل کانتینر با کاربر ۱۰۰۰۱ اجرا می‌شود؛ فایلی که root با مجوز ۶۰۰ گذاشته برای او
    بسته است و بدون این راهنما فقط یک `PermissionError` دیده می‌شود.
    """
    return CompareError(
        f"{path.name} باز نشد ({type(exc).__name__}). اگر آن را با root در پوشه گذاشته‌اید، "
        f"برای کاربر کانتینر خواندنی کنید: chmod 644 model-compare/…/{path.name}"
    )


def _read_rows(path: Path) -> list[list[str]]:
    try:
        if path.suffix.lower() == ".xlsx":
            return office.read_xlsx(path.read_bytes())[0].rows
        raw = path.read_text(encoding="utf-8-sig")
    except office.OfficeError as exc:
        raise CompareError(f"{path.name} را نتوانستم بخوانم: {exc}") from exc
    except OSError as exc:
        raise _unreadable(path, exc) from exc
    first = raw.splitlines()[0] if raw else ""
    # اکسل در بعضی تنظیمات منطقه‌ای با «;» یا تب ذخیره می‌کند، نه «,».
    delimiter = max(",;\t", key=first.count)
    return list(csv.reader(io.StringIO(raw), delimiter=delimiter))


_GRADE_COLUMN = re.compile(r"^(امتیاز|ساخته‌شده)\s*(\d+)")


def load_grades(
    path: Path, *, position_count: int
) -> tuple[dict[tuple[str, int], Grade], list[str]]:
    """({(شناسه‌ی پرسش، جایگاه): نمره}, مشکلات).

    خانه‌ی نامعتبر **بی‌صدا دور ریخته نمی‌شود**؛ در فهرست مشکلات می‌آید و گزارش نشانش
    می‌دهد، وگرنه اشتباه تایپی داور نتیجه را بی‌خبر عوض می‌کند.
    """
    rows = _read_rows(path)
    if not rows:
        raise CompareError(f"{path.name} خالی است")
    header = [to_ascii_digits(h).strip() for h in rows[0]]
    columns: dict[tuple[str, int], int] = {}
    for index, name in enumerate(header):
        match = _GRADE_COLUMN.match(name)
        if match:
            columns[(match[1], int(match[2]))] = index
    id_column = header.index("شناسه") if "شناسه" in header else None
    if id_column is None or not columns:
        raise CompareError(
            f"{path.name} قالب برگه‌ی کور را ندارد (ستون «شناسه» یا «امتیاز k» پیدا نشد). "
            "فایلی را بدهید که از همان برگه ساخته شده."
        )

    grades: dict[tuple[str, int], Grade] = {}
    problems: list[str] = []
    for row in rows[1:]:
        padded = row + [""] * (len(header) - len(row))
        case_id = padded[id_column].strip()
        if not case_id:
            continue
        for k in range(1, position_count + 1):
            raw_score = (
                to_ascii_digits(padded[columns[("امتیاز", k)]]).strip()
                if ("امتیاز", k) in columns
                else ""
            )
            raw_flag = (
                to_ascii_digits(padded[columns[("ساخته‌شده", k)]]).strip().lower()
                if ("ساخته‌شده", k) in columns
                else ""
            )
            score: int | None = None
            if raw_score:
                try:
                    number = float(raw_score)
                except ValueError:
                    number = -1.0
                if number in (0.0, 1.0, 2.0, 3.0):
                    score = int(number)
                else:
                    problems.append(
                        f"{case_id}: امتیاز {k} نامعتبر است («{raw_score}»؛ فقط ۰ تا ۳)"
                    )
            if raw_flag in _TRUE:
                invented = True
            elif raw_flag in _FALSE:
                invented = False
            else:
                invented = False
                problems.append(
                    f"{case_id}: «ساخته‌شده {k}» نامعتبر است («{raw_flag}»؛ فقط ۱ یا خالی)"
                )
            grades[(case_id, k)] = Grade(score, invented)
    return grades, problems


# ---------------------------------------------------------------------------
# آمار
# ---------------------------------------------------------------------------


def wilson(successes: int, n: int, z: float = 1.96) -> tuple[float, float]:
    """بازه‌ی اطمینان ۹۵٪ برای یک نسبت. برای n کوچک از «میانگین ± خطا» درست‌تر است."""
    if n == 0:
        return 0.0, 0.0
    p = successes / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    margin = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return max(0.0, centre - margin), min(1.0, centre + margin)


def sign_test_p(wins: int, losses: int) -> float:
    """آزمون علامت دوطرفه‌ی دقیق، بدون ساده‌سازی. تساوی‌ها پیش‌تر کنار گذاشته شده‌اند."""
    n = wins + losses
    if n == 0:
        return 1.0
    tail = sum(math.comb(n, i) for i in range(0, min(wins, losses) + 1)) / (2.0**n)
    return float(min(1.0, 2 * tail))


def _pct(k: int, n: int) -> str:
    if n == 0:
        return "—"
    lo, hi = wilson(k, n)
    return f"{100 * k / n:.0f}٪ ({k} از {n}، بازه‌ی ۹۵٪: {100 * lo:.0f}–{100 * hi:.0f})"


def _percentile(values: Sequence[float], q: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, round(q * (len(ordered) - 1)))]


def _eligible_for_threshold(result: dict[str, Any]) -> bool:
    """پاسخی که فقط به‌خاطر آستانه‌ی اطمینان ساکت شده، با آستانه‌ی پایین‌تر می‌رفت."""
    return result["outcome"] in ("answer", "silence") and result["silence_reason"] in (
        None,
        "low_confidence",
    )


def analyse_and_render(
    key: dict[str, Any], grades: dict[tuple[str, int], Grade], problems: list[str]
) -> str:
    """گزارش نهایی، به فارسی ساده."""
    candidates: list[dict[str, Any]] = key["candidates"]
    cases: list[dict[str, Any]] = key["cases"]
    names = {c["id"]: c["name"] for c in candidates}

    # برگه‌ی پرشده به نامزد: جایگاه k در هر پرسش همان `order[k-1]` است.
    scored: dict[str, dict[str, tuple[Grade, dict[str, Any]]]] = {c["id"]: {} for c in candidates}
    for case in cases:
        for k, cid in enumerate(case["order"], start=1):
            grade = grades.get((case["id"], k))
            if grade is not None:
                scored[cid][case["id"]] = (grade, case["results"][cid])

    lines: list[str] = []
    add = lines.append
    add("گزارش مقایسه‌ی کور مدل‌ها")
    add("=" * 24)
    add(
        f"تاریخ اجرا: {key['created']} | پرسش‌های داوری‌شده: {len(cases)} | "
        f"نسخه‌ی دستور: {key['prompt_version']} | آستانه‌ی اطمینان: {key['confidence_threshold']}"
    )
    excluded = key.get("excluded") or {}
    if excluded:
        add(
            "کنار گذاشته (مدل هرگز نمی‌دیدشان): "
            + "، ".join(f"{reason}: {n}" for reason, n in sorted(excluded.items()))
        )
    if key.get("stopped_early"):
        add("⚠️ اجرا به سقف هزینه خورد و زودتر تمام شد؛ فقط پرسش‌های اجراشده‌اند.")
    add(f"هزینه‌ی کل اجرا: {key['spent_usd']:.3f} دلار")
    if problems:
        add("")
        add(f"⚠️ {len(problems)} خانه‌ی نامعتبر در برگه بود و نادیده گرفته شد:")
        lines.extend(f"  - {p}" for p in problems[:20])
        if len(problems) > 20:
            add(f"  … و {len(problems) - 20} مورد دیگر")

    # -- جدول هر نامزد
    for c in candidates:
        cid = c["id"]
        rated = {
            case_id: pair
            for case_id, pair in scored[cid].items()
            if pair[0].score is not None and pair[1]["text"]
        }
        all_results = [case["results"][cid] for case in cases]
        failures = sum(1 for r in all_results if r["outcome"] == "error")
        latencies = [r["latency_ms"] / 1000 for r in all_results if r["latency_ms"]]
        scores = [g.score for g, _ in rated.values() if g.score is not None]
        n = len(scores)
        add("")
        add(f"■ {names[cid]}")
        if n == 0:
            add("  هنوز هیچ پاسخش امتیاز نگرفته.")
        else:
            add(f"  میانگین امتیاز: {statistics.mean(scores):.2f} از ۳ (روی {n} پاسخ)")
            add(f"  بدون نیاز به ویرایش (امتیاز ۳): {_pct(sum(s == 3 for s in scores), n)}")
            rewrite = _pct(sum(s <= 1 for s in scores), n)
            add(f"  نیاز به بازنویسی کامل یا غلط (امتیاز ۰ و ۱): {rewrite}")
            invented = sum(1 for g, _ in rated.values() if g.invented)
            add(f"  چیزی از خودش ساخته: {_pct(invented, n)}")

            sent = [(g, r) for g, r in rated.values() if r["outcome"] == "answer"]
            silenced = [(g, r) for g, r in rated.values() if r["outcome"] == "silence"]
            bad_sent = sum(1 for g, _ in sent if g.score == 0 or g.invented)
            add(f"  از پاسخ‌هایی که می‌رفتند ({len(sent)} تا): {bad_sent} تا غلط یا ساخته‌شده بود")
            missed = sum(1 for g, _ in silenced if (g.score or 0) >= 2)
            add(f"  از پاسخ‌هایی که ساکت می‌ماندند ({len(silenced)} تا): {missed} تا خوب بود")
        add(
            f"  شکست فراخوانی (بریده شد، رد شد، خطا): {failures} از {len(all_results)} | "
            f"زمان میانه {statistics.median(latencies) if latencies else 0:.1f} ثانیه، "
            f"٪۹۰ {_percentile(latencies, 0.9):.1f} ثانیه"
        )
        per_message = sum(r["cost_usd"] for r in all_results) / max(1, len(all_results))
        add(f"  هزینه‌ی میانگین هر پیام: {per_message * 100:.2f} سنت")

    # -- رودررو
    add("")
    add("رودررو (روی پرسش‌هایی که هر دو پاسخ امتیاز گرفتند)")
    for i, a in enumerate(candidates):
        for b in candidates[i + 1 :]:
            wins = losses = ties = 0
            for case_id, (ga, ra) in scored[a["id"]].items():
                pair_b = scored[b["id"]].get(case_id)
                if pair_b is None or ga.score is None or pair_b[0].score is None:
                    continue
                if not ra["text"] or not pair_b[1]["text"]:
                    continue
                diff = ga.score - pair_b[0].score
                wins += diff > 0
                losses += diff < 0
                ties += diff == 0
            total = wins + losses + ties
            p = sign_test_p(wins, losses)
            versus = f"{names[a['id']]} در برابر {names[b['id']]}"
            add(f"  {versus}: برد {wins}، باخت {losses}، مساوی {ties} (از {total})")
            if total < MIN_SAMPLE_FOR_CONCLUSION:
                few = f"کمتر از {MIN_SAMPLE_FOR_CONCLUSION}"
                add(f"    ⚠️ نمونه کم است ({few}): نشانه است، نه نتیجه.")
            if wins + losses == 0:
                add("    هیچ تفاوتی دیده نشد.")
            elif p >= 0.05:
                add(f"    تفاوت قابل تشخیص نیست (p = {p:.2f}). نمی‌شود گفت یکی بهتر است.")
            else:
                better = a if wins > losses else b
                add(f"    {names[better['id']]} به‌طور معنی‌دار بهتر است (p = {p:.3f}).")

    # -- آستانه‌ی اطمینان
    add("")
    add("آستانه‌ی اطمینان (پاسخ فقط وقتی می‌رود که اطمینان مدل از آستانه کمتر نباشد)")
    for c in candidates:
        cid = c["id"]
        add(f"  {names[cid]}:")
        add("    آستانه | چند پاسخ می‌رفت | از آن‌ها خوب (۲ و ۳) | غلط یا ساخته‌شده")
        safe: list[float] = []
        for t in THRESHOLDS:
            kept = [
                (g, r)
                for g, r in scored[cid].values()
                if g.score is not None
                and r["text"]
                and _eligible_for_threshold(r)
                and r["confidence"] is not None
                and r["confidence"] >= t
            ]
            if not kept:
                add(f"    {t:.2f}  | 0 | — | —")
                continue
            good = sum(1 for g, _ in kept if (g.score or 0) >= 2)
            bad = sum(1 for g, _ in kept if g.score == 0 or g.invented)
            add(f"    {t:.2f}  | {len(kept)} | {100 * good / len(kept):.0f}٪ | {bad}")
            if bad == 0 and len(kept) >= 10:
                safe.append(t)
        if safe:
            add(f"    کمترین آستانه‌ای که در آن هیچ پاسخ غلط یا ساخته‌شده‌ای نمی‌رفت: {min(safe):.2f}")
        else:
            add("    هیچ آستانه‌ای با نمونه‌ی کافی بدون پاسخ غلط پیدا نشد.")

    add("")
    add("یادآوری: این سنجش تک‌پیام است (بدون تاریخچه‌ی مکالمه و حافظه)، و کور بودنش کامل")
    add("نیست (سبک نوشتار می‌تواند لو بدهد). تصمیم نهایی با شماست.")
    return "\n".join(lines)


def load_key(path: Path) -> dict[str, Any]:
    try:
        key = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise _unreadable(path, exc) from exc
    except json.JSONDecodeError as exc:
        raise CompareError(f"کلید {path.name} JSON معتبر نیست: {exc}") from exc
    if not isinstance(key, dict) or key.get("version") != KEY_VERSION:
        raise CompareError("کلید با این نسخه‌ی ابزار نمی‌خواند")
    return key


def make_report(key_path: Path, graded_path: Path) -> str:
    key = load_key(key_path)
    grades, problems = load_grades(graded_path, position_count=len(key["candidates"]))
    return analyse_and_render(key, grades, problems)


def write_report(text_value: str, out_dir: Path) -> Path:
    path = out_dir / REPORT_NAME
    _write_private(path, text_value + "\n")
    return path
