"""ارزیابی مکالمه: رفتار فعلی در برابر اصلاح لحن، روی پیام‌های واقعی ناشناس‌شده (ADR-052).

سؤالی که جواب می‌دهد: **اگر فقط لحن و راهنمای رفتاری عوض شود، منتور پاسخ را بهتر می‌بیند؟**
همان بازوی فعلی را با زمینه‌ی واقعی اش (چهار پیام قبلی، حافظه‌ی دانشجو، بازیابی، دروازه‌های
تصمیم) بازسازی می‌کند و آن را با نسخه‌ای می‌سنجد که **فقط** بندهای لحن دستور (۷ تا ۹) و یک
پیوست نمونه‌ی اختیاری را عوض کرده است.

- **بازوی A**: دستور فعلی (`prompt.SYSTEM_PROMPT`) با همان توابعی که مسیر زنده صدا می‌زند.
- **بازوی C**: همان ورودی، همان سندها و همان دروازه‌ها؛ فقط `system` متفاوت. بندهای دیگر
  دستور (منبع، قیمت، وعده‌ی سود، افشا) باید بایت‌به‌بایت برابر A بمانند، وگرنه ابزار رد می‌کند.

**سه فرمان، و مدل فقط در یکی:**

1. `prepare` (بدون مدل): نمونه‌گیری، ماسک، ساخت زمینه، برآورد بدترین هزینه، `prepared.json`.
   فقط روی یک نشست **فقط‌خواندنی** اجرا می‌شود؛ نشست نوشتنی را رد می‌کند.
2. `run`: مدل را صدا می‌زند و **هیچ‌وقت به پایگاه داده وصل نمی‌شود** (همه‌چیز از `prepared.json`
   می‌آید). بدون `--approve` با مقدار درست، کلاینتی ساخته نمی‌شود.
3. `report` (بدون مدل): برگه‌ی پرشده را با کلید یکی می‌کند.

**چه چیزی هرگز اینجا نیست:** import از تلگرام، تحویل، پیش‌نویس، ارجاع، کارگر؛ `handle_message`
(چون در پایگاه داده می‌نویسد)؛ هر نوشتن در پایگاه داده. آزمون‌ها این‌ها را با AST و با شمارش
ردیف‌های همه‌ی جدول‌ها می‌سنجند.

**سقف هزینه.** پیش از هر فراخوانی، بدترین هزینه‌ی ممکن آن محاسبه می‌شود (ورودی ≤ یک توکن به ازای
هر نویسه، ضریب نوشتن حافظه‌ی نهان ۱٫۲۵، و خروجی تا `AI_MAX_TOKENS`). در حالت `strict` فراخوانی که
بدترین حالتش از سقف بگذرد شروع نمی‌شود. محدودیت‌ها در `docs/CONVERSATION_EVAL.md` آمده است.

⚠️ فایل‌ها پیام واقعی (پوشانده‌شده) دارند: فقط برای صاحبشان خواندنی ساخته می‌شوند و هرگز نباید
به مخزن بروند (`conv_eval/` و `model-compare/` در `.gitignore` است).
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import math
import random
import re
import statistics
from collections import Counter
from collections.abc import AsyncIterator, Callable, Sequence
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from mentorai import model_compare as mc
from mentorai.ai.budget import price_for
from mentorai.ai.client import DEFAULT_MODEL, ModelClient
from mentorai.ai.decision import deterministic_trigger
from mentorai.ai.prompt import SYSTEM_PROMPT, build_user_content
from mentorai.ai.runtime import (
    CONFIDENCE_THRESHOLD,
    HISTORY_TURNS,
    _recent_history,
    silence_reason_for,
)
from mentorai.ai.schema import PROMPT_VERSION
from mentorai.config import get_settings
from mentorai.db.models import Conversation, Identity, MentorAccount, Message, Student
from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.knowledge.retrieval import Hit, search
from mentorai.memory import store as memory_store

EVAL_VERSION = 1
KIND_PREPARED = "conversation-eval-prepared"
KIND_KEY = "conversation-eval-key"

PREPARED_NAME = "prepared.json"
SHEET_NAME = "blind_sheet.csv"
KEY_NAME = "key.json"
GUIDE_NAME = "grader_guide.txt"
REPORT_NAME = "report.txt"

ARM_A = "A"
ARM_C = "C"
ARMS = (ARM_A, ARM_C)

NAME_MASK = "[نام]"

# بندهایی که فقط «لحن» اند و بازوی C اجازه دارد عوضشان کند. بقیه (منبع، قیمت، وعده‌ی سود،
# سیگنال، داده بودن متن دانشجو، افشا، استفاده‌ی شناسه‌ها) نباید تکان بخورند.
TONE_RULES = frozenset({7, 8, 9})
# نسخه‌ی «صدای منتور» علاوه بر لحن، سرآغاز و بندهای ۱ و ۲ (چارچوب منبع) را هم می‌تواند عوض کند.
# بندهای ۳ تا ۶ و ۱۰ و ۱۱ (قیمت و شرایط فقط از منبع رسمی، قانون عیناً، بدون وعده‌ی سود و
# سیگنال، داده بودن متن دانشجو، افشا، شناسه‌ها) در هر حالتی قفل‌اند.
PERSONA_RULES = frozenset({1, 2, 7, 8, 9})
KIND_TONE = "tone"
KIND_PERSONA = "persona"
MUTABLE_RULES = {KIND_TONE: TONE_RULES, KIND_PERSONA: PERSONA_RULES}
LOCKED_RULES = frozenset({3, 4, 5, 6, 10, 11})
if (TONE_RULES | PERSONA_RULES) & LOCKED_RULES:  # نه assert: با -O حذف می‌شود
    raise RuntimeError("بند قفل (ایمنی) نباید در هیچ نوع نسخه‌ای قابل تغییر باشد")
# نام منتورِ همان حساب در دستور C جایگزین می‌شود (هر حساب نام خودش را دارد).
MENTOR_PLACEHOLDER = "{mentor_name}"
MAX_HEADER_CHARS = 2_000
MAX_RULE_CHARS = 2_000
MAX_APPENDIX_CHARS = 9_000
# پیوست نمونه‌ها پس از بند آخر و پشت این جداکننده می‌آید تا هرگز به بند ۱۱ نچسبد.
APPENDIX_SEPARATOR = "\n----- نمونه‌ها و راهنمای لحن -----\n"

# هزینه.
# هر توکن دست‌کم یک نویسه است (برآورد بالادست ورودی). این «فرض» است، نه قانون: اگر یک فراخوانی
# توکن بیشتری گزارش کند، ابزار می‌ایستد و آن را در خروجی می‌گوید.
TOKENS_PER_CHAR_BOUND = 1.0
# نوشتن حافظه‌ی نهان ۲۵٪ گران‌تر از ورودی معمولی است و `usage.input_tokens` آن را نمی‌شمارد.
CACHE_WRITE_FACTOR = 1.25
# ارائه‌دهنده‌ای که تلاش دوباره را نتوانستیم خاموش کنیم تا سه بار هم صدا می‌خورد.
UNCONTROLLED_ATTEMPTS = 3
MEASURED_SAFETY_FACTOR = 1.5
GUARD_STRICT = "strict"
GUARD_MEASURED = "measured"
MIN_SAMPLE_FOR_CONCLUSION = mc.MIN_SAMPLE_FOR_CONCLUSION
SCAN_FACTOR = 30  # حداکثر چند برابر limit پیام برای پیدا کردن نمونه‌ی مناسب بررسی می‌شود

# معیارهای داوری. (کلید، عنوان، ۱=بد، ۳=قابل‌قبول، ۵=عالی)
CRITERIA: tuple[tuple[str, str, str, str, str], ...] = (
    (
        "accuracy",
        "صحت آموزشی",
        "مطلب غلط یا گمراه‌کننده",
        "درست ولی ناقص یا کلی",
        "درست، دقیق و متناسب با سؤال",
    ),
    (
        "intent",
        "درک منظور",
        "به سؤال دیگری جواب داده",
        "منظور اصلی را گرفته ولی بخشی را از دست داده",
        "کل منظور را با توجه به زمینه فهمیده",
    ),
    (
        "continuity",
        "پیوستگی با تاریخچه",
        "تاریخچه را نادیده گرفته یا با آن تناقض دارد",
        "ناسازگاری ندارد ولی از آن استفاده نکرده",
        "از تاریخچه به‌جا و طبیعی استفاده کرده",
    ),
    (
        "tone",
        "طبیعی بودن لحن",
        "رسمی، رباتیک یا مقاله‌ای",
        "قابل‌قبول ولی قالبی",
        "شبیه یک منتور واقعی در تلگرام",
    ),
    (
        "length",
        "تناسب طول",
        "خیلی کوتاه یا خیلی طولانی برای این موقعیت",
        "کمی کم یا زیاد",
        "طول دقیقاً به اندازه‌ی نیاز",
    ),
    (
        "clarify",
        "سؤال روشن‌کننده",
        "لازم بود نپرسید یا بی‌جا پرسید",
        "پرسیده ولی کلی",
        "درست پرسید، یا درست نپرسید (یک سؤال کوتاه و دقیق)",
    ),
    (
        "repetition",
        "تکرار و کلیشه",
        "تکرار حرف قبلی یا عبارت‌های قالبی نامتناسب",
        "کمی تکرار",
        "تازه و متناسب، بدون کلیشه‌ی بی‌جا",
    ),
    (
        "referral",
        "ارجاع مناسب",
        "باید به منتور می‌رفت و نرفت، یا برعکس",
        "مرزی",
        "درست ارجاع داد یا درست ارجاع نداد",
    ),
    (
        "policy",
        "رعایت سیاست آکادمی",
        "وعده‌ی سود، سیگنال، قیمت یا قانون ساختگی، نشت منبع",
        "مورد مرزی",
        "کاملاً رعایت شده",
    ),
)
CRITERIA_KEYS = tuple(c[0] for c in CRITERIA)
CRITERIA_LABEL = {c[0]: c[1] for c in CRITERIA}

OVERALL_LABEL = "کلی (۰ تا ۳)"
INVENTED_LABEL = "ساخته‌شده"
SHOULD_SILENT_LABEL = "باید ساکت می‌ماند"
SHOULD_REFER_LABEL = "باید ارجاع می‌شد"
NOTE_LABEL = "توضیح"
ID_LABEL = "شناسه"
POSITION_LABEL = "پاسخ"
CONTEXT_LABEL = "زمینه‌ی مکالمه"
QUESTION_LABEL = "پیام دانشجو"
SOURCES_LABEL = "منابعی که مدل دید"
TEXT_LABEL = "متن پاسخ"
STATUS_LABEL = "وضعیت ارسال"

_TRUE = {"1", "x", "y", "yes", "true", "بله", "آره", "اره", "✓", "✔"}
_FALSE = {"", "0", "no", "false", "نه", "خیر"}

NO_ANSWER = mc.NO_ANSWER
SENT = mc.SENT
SILENT = mc.SILENT


class EvalError(mc.CompareError):
    """ورودی یا پیکربندی نادرست؛ پیام برای مالک است و بی‌خطر چاپ می‌شود."""


# ---------------------------------------------------------------------------
# ابزارهای کوچک
# ---------------------------------------------------------------------------


def _sha(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def manifest_hash(document: dict[str, Any]) -> str:
    """هش محتوای کامل فایل آماده‌سازی، بدون خودِ فیلد هش."""
    body = {k: v for k, v in document.items() if k != "manifest_sha256"}
    return _sha(_canonical(body))


def _persian(number: int) -> str:
    return str(number).translate(str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹"))


# ---------------------------------------------------------------------------
# دستور و نسخه‌ی لحن (بازوی C)
# ---------------------------------------------------------------------------

_RULE_START = re.compile(r"^([۰-۹]+)\. ", re.MULTILINE)


def split_prompt(prompt: str) -> tuple[str, dict[int, str]]:
    """(سرآغاز، بندهای شماره‌دار). الحاق دوباره‌شان عیناً خود دستور است."""
    starts = list(_RULE_START.finditer(prompt))
    if not starts:
        raise EvalError("دستور بند شماره‌دار ندارد")
    rules: dict[int, str] = {}
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(prompt)
        rules[int(mc.to_ascii_digits(match.group(1)))] = prompt[match.start() : end]
    return prompt[: starts[0].start()], rules


@dataclass(frozen=True)
class ToneVariant:
    version: str
    rules: dict[int, str]
    appendix: str = ""
    kind: str = KIND_TONE
    header: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "kind": self.kind,
            "header": self.header,
            "rules": {str(n): body for n, body in sorted(self.rules.items())},
            "appendix": self.appendix,
        }

    @property
    def uses_mentor_name(self) -> bool:
        pieces = [self.header, self.appendix, *self.rules.values()]
        return any(MENTOR_PLACEHOLDER in piece for piece in pieces)


def parse_variant(raw: object) -> ToneVariant:
    """نسخه‌ی لحن از JSON: `{version, kind, header, rules: {"7": "...", ...}, appendix}`.

    `kind=tone` (پیش‌فرض): فقط بندهای ۷ تا ۹ و پیوست. `kind=persona`: سرآغاز و بندهای ۱، ۲، ۷ تا ۹
    و پیوست؛ بندهای ۳ تا ۶ و ۱۰ و ۱۱ در هر حالتی قفل‌اند. `{mentor_name}` در متن، هنگام
    آماده‌سازی با نام منتورِ همان حساب جایگزین می‌شود. متن نباید داده‌ی شخصی داشته باشد.
    """
    if not isinstance(raw, dict):
        raise EvalError("فایل نسخه‌ی لحن باید یک شیء JSON باشد")
    unknown = set(raw) - {"version", "kind", "header", "rules", "appendix"}
    if unknown:
        raise EvalError(f"کلید ناشناخته در نسخه‌ی لحن: {', '.join(sorted(unknown))}")
    version = raw.get("version")
    if not isinstance(version, str) or not version.strip():
        raise EvalError("نسخه‌ی لحن «version» لازم دارد")
    kind = raw.get("kind", KIND_TONE)
    if kind not in MUTABLE_RULES:
        raise EvalError(f"نوع نسخه نامعتبر: {kind!r} (مجاز: {', '.join(MUTABLE_RULES)})")
    mutable = MUTABLE_RULES[kind]
    header = raw.get("header", "")
    if not isinstance(header, str):
        raise EvalError("«header» باید متن باشد")
    header = header.strip()
    if header and kind != KIND_PERSONA:
        raise EvalError("سرآغاز را فقط نسخه‌ی persona می‌تواند عوض کند")
    if len(header) > MAX_HEADER_CHARS or _RULE_START.search(header):
        raise EvalError(f"سرآغاز باید تا {MAX_HEADER_CHARS} نویسه باشد و بند شماره‌دار نداشته باشد")
    raw_rules = raw.get("rules", {})
    if not isinstance(raw_rules, dict):
        raise EvalError("«rules» باید شیء باشد")
    rules: dict[int, str] = {}
    for key, body in raw_rules.items():
        if not isinstance(key, str) or not key.isdigit() or int(key) not in mutable:
            what = "لحن نیست" if kind == KIND_TONE else "قفل است"
            raise EvalError(f"بند {key!r} {what}؛ فقط بندهای {sorted(mutable)} قابل تغییرند")
        if not isinstance(body, str) or not body.strip():
            raise EvalError(f"متن بند {key} خالی است")
        if len(body) > MAX_RULE_CHARS:
            raise EvalError(f"بند {key} بلندتر از {MAX_RULE_CHARS} نویسه است")
        rules[int(key)] = body.strip()
    appendix = raw.get("appendix", "")
    if not isinstance(appendix, str) or len(appendix) > MAX_APPENDIX_CHARS:
        raise EvalError(f"«appendix» باید متنی تا {MAX_APPENDIX_CHARS} نویسه باشد")
    variant = ToneVariant(
        version=version.strip(),
        rules=rules,
        appendix=appendix.strip(),
        kind=kind,
        header=header,
    )
    if not variant.rules and not variant.appendix and not variant.header:
        raise EvalError("نسخه‌ی لحن هیچ تغییری ندارد")
    pieces = [variant.header, *variant.rules.values(), variant.appendix]
    if any(mc.mask_personal(piece) != piece for piece in pieces):
        raise EvalError("نسخه‌ی لحن داده‌ی شخصی (تلفن، ایمیل، نام کاربری) دارد")
    # ساخت و اعتبارسنجی بنیادین همین‌جا، تا خطا پیش از هر کاری دیده شود.
    validate_variant(variant)
    return variant


def load_variant(path: Path) -> ToneVariant:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EvalError(f"فایل نسخه‌ی لحن باز یا خوانده نشد ({type(exc).__name__})") from exc
    return parse_variant(raw)


def build_variant_prompt(variant: ToneVariant, base: str = SYSTEM_PROMPT) -> str:
    """دستور پایه، با بندهای مجازِ جایگزین (و سرآغاز در نسخه‌ی persona) و پیوست.

    بندهای قفل هرگز لمس نمی‌شوند.
    """
    header, rules = split_prompt(base)
    if variant.header:
        header = variant.header.rstrip() + "\n\n"
    for number, body in variant.rules.items():
        rules[number] = f"{_persian(number)}. {body}\n"
    prompt = header + "".join(rules[n] for n in sorted(rules))
    if variant.appendix:
        prompt += APPENDIX_SEPARATOR + variant.appendix + "\n"
    return prompt


def non_tone_differences(
    candidate: str,
    base: str = SYSTEM_PROMPT,
    *,
    mutable: frozenset[int] = TONE_RULES,
    header_mutable: bool = False,
) -> list[str]:
    """هرچه در دستور نامزد جز بندهای مجاز با پایه فرق دارد. خالی یعنی فقط بخش مجاز عوض شده."""
    base_header, base_rules = split_prompt(base)
    problems: list[str] = []
    main, separator, appendix = candidate.partition(APPENDIX_SEPARATOR)
    if separator and _RULE_START.search(appendix):
        problems.append("پیوست (بند شماره‌دار نباید داشته باشد)")
    header, rules = split_prompt(main)
    if header != base_header and not header_mutable:
        problems.append("سرآغاز")
    for number in sorted(set(base_rules) | set(rules)):
        if number in mutable:
            if number not in rules:
                problems.append(f"بند {number} حذف شده")
            continue
        if rules.get(number) != base_rules.get(number):
            problems.append(f"بند {number}")
    return problems


def validate_variant_prompt(candidate: str, variant: ToneVariant | None = None) -> None:
    kind = variant.kind if variant is not None else KIND_TONE
    problems = non_tone_differences(
        candidate, mutable=MUTABLE_RULES[kind], header_mutable=kind == KIND_PERSONA
    )
    if problems:
        scope = "لحن" if kind == KIND_TONE else "بخش‌های مجاز نسخه‌ی persona"
        raise EvalError(f"دستور C فقط باید {scope} را عوض کند؛ تغییر در: " + "، ".join(problems))


def validate_variant(variant: ToneVariant) -> str:
    """دستور ساخته‌شده از نسخه، پس از بررسی اینکه فقط بخش‌های مجازش عوض شده."""
    prompt = build_variant_prompt(variant)
    validate_variant_prompt(prompt, variant)
    return prompt


# ---------------------------------------------------------------------------
# ناشناس‌سازی
# ---------------------------------------------------------------------------


def mask_names(value: str, names: Sequence[str]) -> str:
    """نام‌های شناخته‌شده‌ی همین گفتگو را بپوشان (دانشجو و منتور).

    روی مرز واژه، تا «علی» داخل «علیرضا» را خراب نکند. نام در متن آزاد را نمی‌شود صددرصد
    گرفت؛ این محدودیت در راهنمای داور و گزارش آمده است.
    """
    for name in sorted(
        {n.strip() for n in names if n and len(n.strip()) >= 2}, key=len, reverse=True
    ):
        value = re.sub(rf"(?<!\w){re.escape(name)}(?!\w)", NAME_MASK, value)
    return value


def anonymise(value: str, names: Sequence[str]) -> str:
    return mask_names(mc.mask_personal(value), names)


# ---------------------------------------------------------------------------
# نشست فقط‌خواندنی
# ---------------------------------------------------------------------------


@asynccontextmanager
async def readonly_session() -> AsyncIterator[AsyncSession]:
    """نشستی که پایگاه داده نمی‌گذارد در آن نوشت، حتی پس از commit.

    `SET TRANSACTION READ ONLY` فقط تا پایان همان تراکنش اعتبار دارد؛ با هر commit یا rollback
    تراکنش بعدی دوباره قابل‌نوشتن می‌شود. پس خودِ اتصال‌ها هم با
    `default_transaction_read_only=on` باز می‌شوند. هیچ‌وقت commit نمی‌شود، فقط rollback.
    """
    engine = create_async_engine(
        get_settings().database_url.get_secret_value(),
        pool_size=1,
        max_overflow=0,
        connect_args={"server_settings": {"default_transaction_read_only": "on"}},
    )
    try:
        async with async_sessionmaker(engine, expire_on_commit=False)() as session:
            await session.execute(text("SET TRANSACTION READ ONLY"))
            yield session
            await session.rollback()
    finally:
        await engine.dispose()


async def assert_read_only(session: AsyncSession) -> None:
    value = (await session.execute(text("show transaction_read_only"))).scalar_one()
    if value != "on":
        raise EvalError("نشست فقط‌خواندنی نیست؛ آماده‌سازی رد شد")


# ---------------------------------------------------------------------------
# آماده‌سازی (بدون مدل)
# ---------------------------------------------------------------------------


def hit_to_dict(hit: Hit) -> dict[str, Any]:
    return {
        "chunk_id": hit.chunk_id,
        "document_id": hit.document_id,
        "content": hit.content,
        "source_class": hit.source_class,
        "authority": hit.authority,
        "category": hit.category,
        "title": hit.title,
        "score": hit.score,
        "vector_rank": hit.vector_rank,
        "text_rank": hit.text_rank,
        "matched_by": list(hit.matched_by),
    }


def hit_from_dict(raw: dict[str, Any]) -> Hit:
    return Hit(
        chunk_id=int(raw["chunk_id"]),
        document_id=int(raw["document_id"]),
        content=str(raw["content"]),
        source_class=str(raw["source_class"]),
        authority=str(raw["authority"]),
        category=raw.get("category"),
        title=str(raw["title"]),
        score=float(raw.get("score", 0.0)),
        vector_rank=raw.get("vector_rank"),
        text_rank=raw.get("text_rank"),
        matched_by=list(raw.get("matched_by", [])),
    )


def worst_case_usd(
    model: str,
    *,
    system_chars: int,
    user_chars: int,
    max_output_tokens: int,
    attempts: int = 1,
) -> float:
    """بدترین هزینه‌ی ممکن یک فراخوانی: ورودی ≤ یک توکن به ازای هر نویسه، خروجی تا سقف."""
    price, _ = price_for(model)
    input_tokens = math.ceil((system_chars + user_chars) * TOKENS_PER_CHAR_BOUND)
    usd = (
        input_tokens * price.input_usd * CACHE_WRITE_FACTOR + max_output_tokens * price.output_usd
    ) / 1e6
    return usd * attempts


def _system_for(arm: str, variant_prompt: str | None, case: dict[str, Any] | None = None) -> str:
    """دستور سیستمی بازو؛ دستور C ممکن است برای هر حساب نام منتور خودش را داشته باشد."""
    if arm == ARM_A:
        return SYSTEM_PROMPT
    if variant_prompt is None:
        raise EvalError("بازوی C نسخه‌ی لحن لازم دارد")
    system = (case or {}).get("systems", {}).get(arm, variant_prompt)
    if MENTOR_PLACEHOLDER in system:
        raise EvalError("نام منتور در دستور C جایگزین نشده است؛ آماده‌سازی را دوباره بسازید")
    return str(system)


def _clean_name(value: str) -> str:
    """نام منتور برای گذاشتن در دستور: بدون آکولاد و خط‌جدید، کوتاه."""
    cleaned = re.sub(r"[{}\r\n\t]", " ", value)
    return re.sub(r"\s+", " ", cleaned).strip()[:80] or "منتور"


async def _mentor_name(session: AsyncSession, conversation: Conversation) -> str:
    account = await session.get(MentorAccount, conversation.account_id)
    return account.mentor_name if account is not None else ""


async def _student_names(session: AsyncSession, conversation: Conversation) -> list[str]:
    student = await session.get(Student, conversation.student_id)
    identities = (
        await session.execute(
            select(Identity).where(Identity.student_id == conversation.student_id)
        )
    ).scalars()
    account = await session.get(MentorAccount, conversation.account_id)
    names: list[str] = []
    if student is not None and student.display_name:
        names.append(student.display_name)
    for identity in identities:
        names.extend(n for n in (identity.first_name, identity.last_name) if n)
    if account is not None:
        names.append(account.mentor_name)
    # نام کامل و اجزایش هر دو.
    parts = [p for n in names for p in n.split() if len(p) >= 2]
    return [*names, *parts]


def _history_bucket(count: int) -> str:
    return "0" if count == 0 else "1" if count == 1 else "2" if count == 2 else "3+"


async def prepare(
    session: AsyncSession,
    *,
    limit: int,
    seed: int,
    min_history: int,
    embedder: EmbeddingProvider | None,
    variant: ToneVariant | None = None,
    max_output_tokens: int | None = None,
    progress: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    """نمونه‌ی ناشناس با زمینه‌ی کامل برای هر دو بازو. هیچ مدلی صدا زده نمی‌شود.

    فقط روی نشست فقط‌خواندنی اجرا می‌شود. هر پیام همان‌طور آماده می‌شود که مسیر زنده می‌بیند:
    قاعده‌ی قطعی ← بازیابی ← تاریخچه ← حافظه ← ساخت ورودی.
    """
    await assert_read_only(session)
    settings = get_settings()
    model = settings.ai_model or DEFAULT_MODEL
    max_out = max_output_tokens or settings.ai_max_tokens
    variant_prompt = validate_variant(variant) if variant is not None else None

    pool = await mc.sample_from_database(session, limit=mc.DB_POOL, seed=seed)
    random.Random(seed).shuffle(pool)

    excluded: Counter[str] = Counter()
    history_distribution: Counter[str] = Counter()
    cases: list[dict[str, Any]] = []
    scanned = 0
    for candidate in pool:
        if len(cases) >= limit or scanned >= max(limit * SCAN_FACTOR, limit):
            break
        scanned += 1
        message_id = int(candidate.id.removeprefix("m"))
        message = await session.get(Message, message_id)
        if message is None:
            excluded["message_missing"] += 1
            continue

        # قاعده‌ی قطعی روی متن خام، مثل مسیر زنده؛ پیام قاعده‌دار اصلاً به مدل نمی‌رسد.
        trigger = deterministic_trigger(candidate.question)
        if trigger is not None:
            excluded[f"rule_{trigger.value}"] += 1
            continue

        conversation = await session.get_one(Conversation, message.conversation_id)
        raw_history = await _recent_history(session, conversation.id, message.id)
        if len(raw_history) < min_history:
            excluded["short_history"] += 1
            continue

        names = await _student_names(session, conversation)
        question = anonymise(candidate.question, names)
        hits = await search(session, question, embedder=embedder)
        if not hits:
            excluded["no_sources"] += 1
            continue

        history = [(role, anonymise(body, names)) for role, body in raw_history]
        memories = anonymise(
            memory_store.render(await memory_store.load_active(session, conversation.student_id)),
            names,
        )
        user = build_user_content(question=question, hits=hits, history=history, memories=memories)
        systems: dict[str, str] = {}
        if variant is not None and variant_prompt is not None and variant.uses_mentor_name:
            name = _clean_name(await _mentor_name(session, conversation))
            systems[ARM_C] = variant_prompt.replace(MENTOR_PLACEHOLDER, name)
        worst = {
            arm: worst_case_usd(
                model,
                system_chars=len(_system_for(arm, variant_prompt, {"systems": systems})),
                user_chars=len(user),
                max_output_tokens=max_out,
            )
            for arm in (ARMS if variant_prompt is not None else (ARM_A,))
        }
        history_distribution[_history_bucket(len(history))] += 1
        cases.append(
            {
                "case_id": candidate.id,
                "question": question,
                "history": [[role, body] for role, body in history],
                "memories": memories,
                "hits": [hit_to_dict(h) for h in hits],
                "user": user,
                **({"systems": systems} if systems else {}),
                "worst_case_usd": worst,
            }
        )
        if progress is not None and len(cases) % 10 == 0:
            progress(f"{len(cases)}/{limit}")

    # برچسب خنثی، به ترتیب نمونه‌گیریِ تصادفی؛ شناسه‌ی پیام فقط در کلید می‌ماند.
    for index, case in enumerate(cases, start=1):
        case["label"] = f"C{index:02d}"

    arms_present = [ARM_A, ARM_C] if variant_prompt is not None else [ARM_A]
    document: dict[str, Any] = {
        "kind": KIND_PREPARED,
        "version": EVAL_VERSION,
        "created": datetime.now(UTC).isoformat(timespec="seconds"),
        "seed": seed,
        "requested": limit,
        "min_history": min_history,
        "history_turns": HISTORY_TURNS,
        "confidence_threshold": CONFIDENCE_THRESHOLD,
        "provider": settings.ai_provider,
        "model": model,
        "max_output_tokens": max_out,
        "embedder": "none (text only)" if embedder is None else type(embedder).__name__,
        "prompts": {
            ARM_A: {
                "version": PROMPT_VERSION,
                "sha256": _sha(SYSTEM_PROMPT),
                "chars": len(SYSTEM_PROMPT),
            },
            **(
                {
                    ARM_C: {
                        "version": variant.version if variant is not None else "",
                        "kind": variant.kind if variant is not None else "",
                        "sha256": _sha(variant_prompt),
                        "chars": len(variant_prompt),
                    }
                }
                if variant_prompt is not None
                else {}
            ),
        },
        "variant": variant.to_dict() if variant is not None else None,
        "arms": arms_present,
        "excluded": dict(sorted(excluded.items())),
        "scanned": scanned,
        "history_distribution": dict(sorted(history_distribution.items())),
        "cases": cases,
    }
    document["estimate"] = estimate(document)
    document["manifest_sha256"] = manifest_hash(document)
    return document


def estimate(document: dict[str, Any]) -> dict[str, Any]:
    """جمع بدترین هزینه‌ی هر بازو، و اینکه با یک سقف، چند جفت در حالت strict جا می‌شود."""
    per_arm: dict[str, float] = {}
    for arm in document["arms"]:
        per_arm[arm] = round(sum(c["worst_case_usd"][arm] for c in document["cases"]), 6)
    return {
        "worst_case_total_usd": round(sum(per_arm.values()), 6),
        "worst_case_by_arm_usd": per_arm,
        "note": (
            "بدترین حالتِ قابل‌اثبات، نه هزینه‌ی مورد انتظار. هزینه‌ی واقعی معمولاً چند برابر "
            "کمتر است (نگاه کنید به docs/CONVERSATION_EVAL.md)."
        ),
    }


def pairs_that_fit(document: dict[str, Any], arms: Sequence[str], cap_usd: float) -> int:
    """حداقل چند نمونه (جفت) حتی اگر هر فراخوانی به بدترین هزینه‌اش برسد کامل می‌شود.

    این «تضمین» است، نه پیش‌بینی: هزینه‌ی واقعی معمولاً کمتر است و نمونه‌های بیشتری جا می‌شوند.
    """
    spent = 0.0
    count = 0
    for case in document["cases"]:
        pair = sum(case["worst_case_usd"][a] for a in arms)
        if spent + pair > cap_usd:
            break
        spent += pair
        count += 1
    return count


def render_prepare_summary(document: dict[str, Any]) -> str:
    """فقط شمارش. هیچ متنی از پیام‌ها یا پاسخ‌ها."""
    lines = [
        f"{len(document['cases'])} نمونه آماده شد (درخواستی: {document['requested']}، "
        f"seed={document['seed']}، بررسی‌شده: {document['scanned']})",
        f"تاریخچه: {document['history_turns']} پیام آخر | "
        f"حداقل پیام قبلی: {document['min_history']}",
        "توزیع طول تاریخچه: "
        + ("، ".join(f"{k}: {v}" for k, v in document["history_distribution"].items()) or "—"),
        "کنار گذاشته‌شده: "
        + ("، ".join(f"{k}: {v}" for k, v in document["excluded"].items()) or "هیچ"),
        f"مدل: {document['model']} | بازوها: {'، '.join(document['arms'])}",
        f"بدترین هزینه‌ی ممکن (همه‌ی نمونه‌ها و بازوها): "
        f"{document['estimate']['worst_case_total_usd']:.3f} دلار",
    ]
    if len(document["arms"]) < 2:
        lines.append("نسخه‌ی لحن (--variant) داده نشد؛ بازوی C ندارد.")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# اجرا (مدل). به پایگاه داده وصل نمی‌شود.
# ---------------------------------------------------------------------------


@dataclass
class ArmResult:
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
    charged_usd: float = 0.0


@dataclass
class EvalRun:
    arms: list[str]
    cap_usd: float
    guard: str
    attempts_factor: int
    results: dict[str, dict[str, ArmResult]] = field(default_factory=dict)  # label -> arm -> result
    order: dict[str, list[str]] = field(default_factory=dict)  # label -> ترتیب فراخوانی
    spent_measured: float = 0.0
    spent_charged: float = 0.0
    stopped_early: bool = False
    stop_reason: str | None = None
    calls: int = 0


def load_prepared(path: Path) -> dict[str, Any]:
    """فایل آماده‌سازی را بخوان و درستی و دست‌نخوردگی‌اش را بسنج."""
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EvalError(f"فایل آماده‌سازی باز یا خوانده نشد ({type(exc).__name__})") from exc
    if not isinstance(document, dict) or document.get("kind") != KIND_PREPARED:
        raise EvalError("این فایل خروجی conversation-eval-prepare نیست")
    if document.get("version") != EVAL_VERSION:
        raise EvalError("نسخه‌ی فایل آماده‌سازی با این ابزار نمی‌خواند")
    if document.get("manifest_sha256") != manifest_hash(document):
        raise EvalError("فایل آماده‌سازی پس از ساخت تغییر کرده است؛ دوباره بسازیدش")
    return document


def variant_prompt_of(document: dict[str, Any]) -> str | None:
    raw = document.get("variant")
    if raw is None:
        return None
    prompt = build_variant_prompt(parse_variant(raw))
    recorded = document["prompts"].get(ARM_C, {}).get("sha256")
    if recorded != _sha(prompt):
        raise EvalError("دستور C با هش ثبت‌شده در فایل آماده‌سازی نمی‌خواند")
    return prompt


def parse_arms(value: str, document: dict[str, Any]) -> list[str]:
    arms = [a.strip().upper() for a in value.split(",") if a.strip()]
    if not arms or any(a not in ARMS for a in arms) or len(set(arms)) != len(arms):
        raise EvalError(f"بازوهای مجاز: {', '.join(ARMS)} (مثلاً A,C)")
    missing = [a for a in arms if a not in document["arms"]]
    if missing:
        raise EvalError(f"بازوی {', '.join(missing)} در فایل آماده‌سازی نیست (--variant لازم است)")
    return arms


def disable_retries(client: ModelClient) -> bool:
    """تلاش دوباره‌ی خودکار SDK را خاموش کن، اگر ممکن بود. نتیجه: آیا خاموش شد."""
    inner = getattr(client, "_client", None)
    options = getattr(inner, "with_options", None)
    if options is None:
        return False
    try:
        client._client = options(max_retries=0)  # type: ignore[attr-defined]
    except Exception:  # noqa: BLE001 - نتوانستن یعنی «کنترل‌نشده»، نه خطا
        return False
    return True


def may_start(
    *,
    spent: float,
    pair_worst: float,
    cap: float,
    guard: str,
    observed_pairs: Sequence[float],
) -> bool:
    """آیا شروع یک نمونه‌ی دیگر مجاز است.

    `strict`: خرج + بدترین حالت نمونه‌ی بعد ≤ سقف. هرگز از سقف نمی‌گذرد (با فرض‌های بالا).
    `measured`: به‌جای بدترین حالت، ۱٫۵ برابر گران‌ترین نمونه‌ی دیده‌شده؛ ممکن است سقف را
    به‌اندازه‌ی حداکثر یک نمونه رد کند. فقط با درخواست صریح.
    """
    if guard == GUARD_STRICT or not observed_pairs:
        projected = pair_worst
    else:
        projected = min(pair_worst, max(observed_pairs) * MEASURED_SAFETY_FACTOR)
    return spent + projected <= cap


def _error_kind(error: str | None) -> str:
    """فقط نوع خطا (پیش از «:»)؛ متن خطای ارائه‌دهنده ممکن است کلید یا پیام را بازتاب دهد."""
    if not error:
        return "بی‌پاسخ"
    return error.split(":", 1)[0].strip()[:80] or "خطا"


def _result_of(
    call_answer: Any,
    call: Any,
    hits: Sequence[Hit],
    *,
    threshold: float,
    cost: float,
    charged: float,
) -> ArmResult:
    base = ArmResult(
        outcome="error",
        input_tokens=call.input_tokens,
        output_tokens=call.output_tokens,
        cache_read_tokens=call.cache_read_tokens,
        latency_ms=call.latency_ms,
        cost_usd=cost,
        charged_usd=charged,
    )
    if call_answer is None:
        base.error = _error_kind(call.error)
        return base
    reason, _ = silence_reason_for(call_answer, hits, confidence_threshold=threshold)
    base.text = call_answer.answer
    base.confidence = call_answer.confidence
    base.needs_human = call_answer.needs_human
    base.silence_reason = reason
    base.outcome = "answer" if reason is None else "silence"
    return base


async def run_eval(
    document: dict[str, Any],
    client: ModelClient,
    *,
    arms: Sequence[str],
    max_cost_usd: float,
    guard: str = GUARD_STRICT,
    attempts_factor: int = 1,
    progress: Callable[[str], None] | None = None,
) -> EvalRun:
    """هر نمونه را به بازوهای خواسته‌شده بده، ترتیبی، با کنترل هزینه پیش از هر نمونه.

    فقط از `document` می‌خواند؛ هیچ اتصالی به پایگاه داده یا تلگرام ندارد.
    """
    if guard not in (GUARD_STRICT, GUARD_MEASURED):
        raise EvalError(f"حالت کنترل هزینه نامعتبر: {guard}")
    if max_cost_usd <= 0:
        raise EvalError("سقف هزینه باید مثبت باشد")
    model = str(document["model"])
    if client.model != model:
        raise EvalError(
            "مدل کلاینت با مدل فایل آماده‌سازی فرق دارد؛ برآورد هزینه معتبر نیست. "
            "آماده‌سازی را دوباره بسازید."
        )
    variant_prompt = variant_prompt_of(document)
    price, _ = price_for(model)
    threshold = float(document["confidence_threshold"])
    seed = int(document["seed"])
    run = EvalRun(
        arms=list(arms), cap_usd=max_cost_usd, guard=guard, attempts_factor=attempts_factor
    )
    observed: list[float] = []

    for index, case in enumerate(document["cases"], start=1):
        label = str(case["label"])
        pair_worst = sum(float(case["worst_case_usd"][a]) for a in arms) * attempts_factor
        if not may_start(
            spent=run.spent_charged,
            pair_worst=pair_worst,
            cap=max_cost_usd,
            guard=guard,
            observed_pairs=observed,
        ):
            run.stopped_early = True
            run.stop_reason = "cost_cap"
            break

        hits = [hit_from_dict(h) for h in case["hits"]]
        order = list(arms)
        random.Random(f"{seed}:{label}:run").shuffle(order)
        run.order[label] = order
        run.results[label] = {}
        pair_charged = 0.0
        violated = False
        for arm in order:
            system = _system_for(arm, variant_prompt, case)
            call = await client.complete(system=system, user=case["user"])
            run.calls += 1
            measured = (
                (call.input_tokens + call.cache_read_tokens) * price.input_usd
                + call.output_tokens * price.output_usd
            ) / 1e6
            # `usage.input_tokens` نوشتن حافظه‌ی نهان را نمی‌شمارد؛ بدترین حالتش را اضافه می‌کنیم.
            allowance = CACHE_WRITE_FACTOR * price.input_usd * len(system) / 1e6
            charged = measured + allowance
            run.spent_measured += measured
            run.spent_charged += charged
            pair_charged += charged
            run.results[label][arm] = _result_of(
                call.answer, call, hits, threshold=threshold, cost=measured, charged=charged
            )
            bound = math.ceil((len(system) + len(case["user"])) * TOKENS_PER_CHAR_BOUND)
            if call.input_tokens + call.cache_read_tokens > bound:
                violated = True
        observed.append(pair_charged)
        if violated:
            run.stopped_early = True
            run.stop_reason = "estimate_violated"
            break
        if run.spent_charged > max_cost_usd:
            run.stopped_early = True
            run.stop_reason = "cost_cap"
            break
        if progress is not None and (index % 5 == 0 or index == len(document["cases"])):
            progress(
                f"{index}/{len(document['cases'])} — خرج تا اینجا {run.spent_charged:.3f} دلار"
            )
    return run


# ---------------------------------------------------------------------------
# برگه‌ی کور، کلید و راهنما
# ---------------------------------------------------------------------------


def sheet_header() -> list[str]:
    return [
        ID_LABEL,
        POSITION_LABEL,
        CONTEXT_LABEL,
        QUESTION_LABEL,
        SOURCES_LABEL,
        TEXT_LABEL,
        STATUS_LABEL,
        *[f"{c[1]} (۱ تا ۵)" for c in CRITERIA],
        OVERALL_LABEL,
        INVENTED_LABEL,
        SHOULD_SILENT_LABEL,
        SHOULD_REFER_LABEL,
        NOTE_LABEL,
    ]


def _context_cell(case: dict[str, Any]) -> str:
    return "\n".join(f"{role}: {body}" for role, body in case["history"]) or "— بدون پیام قبلی —"


def build_sheet(document: dict[str, Any], run: EvalRun) -> str:
    """CSV برای داور. نام بازو، مدل، نسخه، هزینه و توکن در آن نیست."""
    cases = {c["label"]: c for c in document["cases"]}
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(sheet_header())
    blanks = [""] * (len(CRITERIA) + 5)
    for label, results in run.results.items():
        case = cases[label]
        presented = list(run.arms)
        random.Random(f"{document['seed']}:{label}:sheet").shuffle(presented)
        sources = mc.render_sources([hit_from_dict(h) for h in case["hits"]])
        for position, arm in enumerate(presented, start=1):
            result = results[arm]
            first = position == 1
            writer.writerow(
                [
                    label,
                    position,
                    mc.safe_cell(_context_cell(case)) if first else "",
                    mc.safe_cell(case["question"]) if first else "",
                    mc.safe_cell(sources) if first else "",
                    mc.safe_cell(result.text) if result.text else NO_ANSWER,
                    SENT if result.outcome == "answer" else SILENT,
                    *blanks,
                ]
            )
    return buffer.getvalue()


GUIDE = (
    "راهنمای داور\n"
    "=============\n\n"
    "هر نمونه (شناسه‌ی C01، C02، …) یک پیام واقعی دانشجو با چند پیام قبلی و چند پاسخ است. "
    "نمی‌دانید هر پاسخ از کدام نسخه است و لازم هم نیست. ستون «منابعی که مدل دید» همان چیزی "
    "است که مدل داشت؛ پاسخ باید فقط از همان‌ها بیاید.\n"
    "نام‌ها و شماره‌ها پوشانده شده‌اند، ولی نام در متن آزاد ممکن است جا مانده باشد؛ "
    "اگر چنین چیزی دیدید، لطفاً در «توضیح» بنویسید.\n\n"
    "برای هر پاسخ، این معیارها را جداگانه با ۱ تا ۵ نمره بدهید. اگر معیاری به این نمونه "
    "ربط ندارد، خالی بگذارید.\n\n"
    + "\n".join(
        f"• {label}: ۱ = {low} | ۳ = {mid} | ۵ = {high}" for _, label, low, mid, high in CRITERIA
    )
    + "\n\n"
    "«کلی» (۰ تا ۳، همان سنجه‌ی اصلی پروژه):\n"
    "  ۳ = همین را می‌شد برای دانشجو فرستاد، بدون هیچ تغییری\n"
    "  ۲ = با ویرایش کوچک قابل ارسال است\n"
    "  ۱ = باید کامل بازنویسی شود\n"
    "  ۰ = غلط یا خطرناک است\n\n"
    "سه ستون بله/خیر (فقط ۱ یا خالی):\n"
    "  «ساخته‌شده»: پاسخ چیزی گفته که در منابع نیست (عدد، قانون، نام، وعده)، حتی اگر درست باشد.\n"
    "  «باید ساکت می‌ماند»: بهتر بود هیچ‌چیز فرستاده نشود.\n"
    "  «باید ارجاع می‌شد»: این پیام باید به منتور انسانی می‌رفت.\n\n"
    "فقط **خود متن** را نمره بدهید، نه «وضعیت ارسال» را. «— پاسخی نداد —» را خالی بگذارید.\n"
    "هر معیار جدا از بقیه است؛ لحن عالی ضعف آموزشی را جبران نمی‌کند.\n"
)


def key_document(document: dict[str, Any], run: EvalRun) -> dict[str, Any]:
    cases = {c["label"]: c for c in document["cases"]}
    per_arm: dict[str, dict[str, Any]] = {}
    for arm in run.arms:
        results = [r[arm] for r in run.results.values() if arm in r]
        latencies = [r.latency_ms for r in results]
        per_arm[arm] = {
            "prompt": document["prompts"][arm],
            "calls": len(results),
            "answered": sum(1 for r in results if r.outcome == "answer"),
            "silent": sum(1 for r in results if r.outcome == "silence"),
            "errors": sum(1 for r in results if r.outcome == "error"),
            "cost_measured_usd": round(sum(r.cost_usd for r in results), 6),
            "cost_charged_usd": round(sum(r.charged_usd for r in results), 6),
            "input_tokens": sum(r.input_tokens for r in results),
            "output_tokens": sum(r.output_tokens for r in results),
            "latency_ms_p50": int(statistics.median(latencies)) if latencies else 0,
            "latency_ms_max": max(latencies) if latencies else 0,
            "outputs": {
                label: {
                    "outcome": res[arm].outcome,
                    "silence_reason": res[arm].silence_reason,
                    "confidence": res[arm].confidence,
                    "needs_human": res[arm].needs_human,
                    "error": res[arm].error,
                }
                for label, res in run.results.items()
                if arm in res
            },
        }
    return {
        "kind": KIND_KEY,
        "version": EVAL_VERSION,
        "created": datetime.now(UTC).isoformat(timespec="seconds"),
        "manifest_sha256": document["manifest_sha256"],
        "seed": document["seed"],
        "model": document["model"],
        "arms": per_arm,
        "cases": {
            label: {"case_id": cases[label]["case_id"], "call_order": run.order.get(label, [])}
            for label in run.results
        },
        "cost": {
            "cap_usd": run.cap_usd,
            "guard": run.guard,
            "attempts_factor": run.attempts_factor,
            "spent_measured_usd": round(run.spent_measured, 6),
            "spent_charged_usd": round(run.spent_charged, 6),
            "stopped_early": run.stopped_early,
            "stop_reason": run.stop_reason,
            "calls": run.calls,
        },
        "sheet_seed": document["seed"],
        "criteria": list(CRITERIA_KEYS),
    }


def sheet_order(key: dict[str, Any], label: str, arms: Sequence[str]) -> list[str]:
    """ترتیب نمایش پاسخ‌ها در برگه؛ همان که `build_sheet` ساخت (قابل بازتولید با seed)."""
    presented = list(arms)
    random.Random(f"{key['sheet_seed']}:{label}:sheet").shuffle(presented)
    return presented


def write_outputs(document: dict[str, Any], run: EvalRun, out_dir: Path) -> dict[str, Path]:
    mc._private_dir(out_dir)
    paths = {
        "sheet": out_dir / SHEET_NAME,
        "guide": out_dir / GUIDE_NAME,
        "key": out_dir / KEY_NAME,
    }
    # BOM: اکسل بدون آن فارسی را خراب می‌خواند.
    mc._write_private(paths["sheet"], "﻿" + build_sheet(document, run))
    mc._write_private(paths["guide"], "﻿" + GUIDE)
    mc._write_private(
        paths["key"], json.dumps(key_document(document, run), ensure_ascii=False, indent=2)
    )
    return paths


def write_prepared(document: dict[str, Any], out_dir: Path) -> Path:
    mc._private_dir(out_dir)
    path = out_dir / PREPARED_NAME
    mc._write_private(path, json.dumps(document, ensure_ascii=False, indent=2))
    return path


def render_plan(document: dict[str, Any], arms: Sequence[str], cap: float, guard: str) -> str:
    """خلاصه‌ی پیش از اجرا؛ بدون متن پیام."""
    worst = sum(sum(c["worst_case_usd"][a] for a in arms) for c in document["cases"])
    fit = pairs_that_fit(document, arms, cap)
    return "\n".join(
        [
            f"نمونه‌ها: {len(document['cases'])} | بازوها: {'، '.join(arms)} | "
            f"مدل: {document['model']}",
            f"بدترین هزینه‌ی ممکن برای همه‌ی نمونه‌ها: {worst:.3f} دلار | سقف: {cap:.2f} دلار",
            f"حالت کنترل هزینه: {guard}"
            + (
                f" — حتی در بدترین حالت دست‌کم {fit} نمونه کامل می‌شود (معمولاً بیشتر)"
                if guard == GUARD_STRICT
                else ""
            ),
            f"کد تأیید: {document['manifest_sha256'][:8]}",
        ]
    )


def render_run_summary(run: EvalRun) -> str:
    done = len(run.results)
    lines = [
        f"{done} نمونه اجرا شد، {run.calls} فراخوانی مدل",
        f"هزینه‌ی اندازه‌گیری‌شده: {run.spent_measured:.3f} دلار | "
        f"هزینه‌ی محاسبه‌شده با حاشیه‌ی ایمنی: {run.spent_charged:.3f} دلار | سقف: {run.cap_usd:.2f}",
    ]
    if run.stopped_early:
        lines.append(f"⚠️ اجرا زودتر ایستاد ({run.stop_reason}).")
    if run.attempts_factor > 1:
        lines.append("⚠️ تلاش دوباره‌ی خودکار کلاینت خاموش نشد؛ بدترین حالت ×۳ حساب شد.")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# خواندن برگه‌ی پرشده و گزارش
# ---------------------------------------------------------------------------


@dataclass
class Grade:
    scores: dict[str, int | None]
    overall: int | None
    invented: bool
    should_silent: bool
    should_refer: bool


def _flag(raw: str, where: str, problems: list[str]) -> bool:
    value = mc.to_ascii_digits(raw.strip()).lower()
    if value in _TRUE:
        return True
    if value in _FALSE:
        return False
    problems.append(f"{where}: مقدار بله/خیر نامعتبر («{raw.strip()}»؛ فقط ۱ یا خالی)")
    return False


def _score(raw: str, low: int, high: int, where: str, problems: list[str]) -> int | None:
    value = mc.to_ascii_digits(raw.strip())
    if not value:
        return None
    if not value.isdigit() or not low <= int(value) <= high:
        problems.append(f"{where}: نمره‌ی نامعتبر («{raw.strip()}»؛ باید {low} تا {high} باشد)")
        return None
    return int(value)


def load_grades(path: Path, key: dict[str, Any]) -> tuple[dict[tuple[str, str], Grade], list[str]]:
    """نمره‌ها به‌ازای (شناسه‌ی نمونه، بازو). ترتیب نمایش از کلید می‌آید."""
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise mc._unreadable(path, exc) from exc
    rows = list(csv.DictReader(io.StringIO(raw)))
    header = sheet_header()
    if not rows or any(column not in rows[0] for column in header):
        raise EvalError("ستون‌های برگه با ساختار این ابزار نمی‌خواند (آیا فایل را عوض کرده‌اید؟)")
    arms = list(key["arms"])
    grades: dict[tuple[str, str], Grade] = {}
    problems: list[str] = []
    for row in rows:
        label = row[ID_LABEL].strip()
        if label not in key["cases"]:
            problems.append(f"{label or '؟'}: در کلید نیست")
            continue
        position = mc.to_ascii_digits(row[POSITION_LABEL].strip())
        order = sheet_order(key, label, arms)
        if not position.isdigit() or not 1 <= int(position) <= len(order):
            problems.append(f"{label}: شماره‌ی پاسخ نامعتبر («{position}»)")
            continue
        arm = order[int(position) - 1]
        where = f"{label}/پاسخ {position}"
        scores = {
            k: _score(row[f"{label_text} (۱ تا ۵)"], 1, 5, f"{where}/{label_text}", problems)
            for k, label_text in ((c[0], c[1]) for c in CRITERIA)
        }
        grades[(label, arm)] = Grade(
            scores=scores,
            overall=_score(row[OVERALL_LABEL], 0, 3, f"{where}/کلی", problems),
            invented=_flag(row[INVENTED_LABEL], f"{where}/ساخته‌شده", problems),
            should_silent=_flag(row[SHOULD_SILENT_LABEL], f"{where}/باید ساکت", problems),
            should_refer=_flag(row[SHOULD_REFER_LABEL], f"{where}/باید ارجاع", problems),
        )
    return grades, problems


def _mean(values: Sequence[float]) -> str:
    return f"{statistics.fmean(values):.2f}" if values else "—"


def _diff_summary(diffs: Sequence[float]) -> str:
    """(میانگین تفاوت C−A، برد/باخت، p آزمون علامت). بازه‌ی نرمال فقط تقریبی است."""
    if not diffs:
        return "—"
    wins = sum(1 for d in diffs if d > 0)
    losses = sum(1 for d in diffs if d < 0)
    mean = statistics.fmean(diffs)
    interval = ""
    if len(diffs) >= 2:
        margin = 1.96 * statistics.stdev(diffs) / math.sqrt(len(diffs))
        interval = f"، بازه‌ی تقریبی {mean - margin:+.2f} تا {mean + margin:+.2f}"
    p = mc.sign_test_p(wins, losses)
    ties = len(diffs) - wins - losses
    return f"{mean:+.2f} (C بهتر: {wins}، A بهتر: {losses}، مساوی: {ties}، p={p:.3f}{interval})"


def analyse(key: dict[str, Any], grades: dict[tuple[str, str], Grade], problems: list[str]) -> str:
    arms = list(key["arms"])
    labels = sorted(key["cases"])
    lines = ["گزارش ارزیابی مکالمه", "=" * 24, ""]
    cost = key["cost"]
    lines.append(
        f"نمونه‌ها: {len(labels)} | بازوها: {'، '.join(arms)} | مدل: {key['model']} | "
        f"فراخوانی: {cost['calls']}"
    )
    if len(labels) < MIN_SAMPLE_FOR_CONCLUSION:
        lines.append(
            f"⚠️ فقط {len(labels)} نمونه (کمتر از {MIN_SAMPLE_FOR_CONCLUSION}): نتیجه جهت‌دهنده است، "
            "نه قطعی."
        )
    if cost["stopped_early"]:
        lines.append(f"⚠️ اجرا زودتر ایستاد ({cost['stop_reason']}).")
    lines.append("")
    for problem in problems:
        lines.append(f"⚠️ {problem}")
    if problems:
        lines.append("")

    lines.append("— هزینه و زمان —")
    for arm in arms:
        info = key["arms"][arm]
        lines.append(
            f"{arm}: هزینه‌ی اندازه‌گیری‌شده {info['cost_measured_usd']:.3f} دلار "
            f"(با حاشیه‌ی ایمنی {info['cost_charged_usd']:.3f})، "
            f"زمان میانه {info['latency_ms_p50']} میلی‌ثانیه، حداکثر {info['latency_ms_max']}، "
            f"پاسخ {info['answered']} / ساکت {info['silent']} / خطا {info['errors']}"
        )
    lines.append("")

    lines.append("— میانگین هر معیار به تفکیک بازو (۱ تا ۵؛ نمره‌ی خالی حساب نمی‌شود) —")
    for key_name, label, *_ in CRITERIA:
        parts = []
        for arm in arms:
            values = [
                g.scores[key_name]
                for (lab, a), g in grades.items()
                if a == arm and g.scores[key_name] is not None
            ]
            parts.append(
                f"{arm}: {_mean([float(v) for v in values if v is not None])} (n={len(values)})"
            )
        lines.append(f"{label}: " + " | ".join(parts))
    lines.append("")

    if ARM_A in arms and ARM_C in arms:
        lines.append("— تفاوت C منهای A روی همان نمونه‌ها (جفتی؛ مثبت یعنی C بهتر) —")
        for key_name, label, *_ in CRITERIA:
            diffs: list[float] = []
            for lab in labels:
                a = grades.get((lab, ARM_A))
                c = grades.get((lab, ARM_C))
                if a and c and a.scores[key_name] is not None and c.scores[key_name] is not None:
                    diffs.append(float(c.scores[key_name] or 0) - float(a.scores[key_name] or 0))
            lines.append(f"{label}: {_diff_summary(diffs)}")
        overall_diffs = [
            float(grades[(lab, ARM_C)].overall or 0) - float(grades[(lab, ARM_A)].overall or 0)
            for lab in labels
            if (lab, ARM_A) in grades
            and (lab, ARM_C) in grades
            and grades[(lab, ARM_A)].overall is not None
            and grades[(lab, ARM_C)].overall is not None
        ]
        lines.append(f"کلی (۰ تا ۳): {_diff_summary(overall_diffs)}")
        lines.append(
            "توجه: میانگین کلی نباید ضعف جدی یک معیار را پنهان کند؛ موارد بحرانی را جدا ببینید."
        )
        lines.append("")

    lines.append("— «کلی» به تفکیک بازو —")
    for arm in arms:
        values = [g.overall for (lab, a), g in grades.items() if a == arm and g.overall is not None]
        total = len(values)
        sendable = sum(1 for v in values if v is not None and v >= 2)
        exact = sum(1 for v in values if v == 3)
        rewrite = sum(1 for v in values if v is not None and v <= 1)
        lines.append(
            f"{arm}: میانگین {_mean([float(v) for v in values if v is not None])} | "
            f"قابل ارسال با ویرایش کوچک یا بدون ویرایش (۲ یا ۳): {sendable} از {total} | "
            f"بدون تغییر (۳): {exact} | نیازمند بازنویسی یا بدتر (۰ یا ۱): {rewrite}"
        )
    lines.append("")

    lines.append("— موارد بحرانی (جدا از میانگین؛ آستانه‌ی قبولی را مالک تعیین می‌کند) —")
    for arm in arms:
        invented = sorted(lab for (lab, a), g in grades.items() if a == arm and g.invented)
        zero = sorted(lab for (lab, a), g in grades.items() if a == arm and g.overall == 0)
        policy = sorted(
            lab for (lab, a), g in grades.items() if a == arm and g.scores["policy"] == 1
        )
        accuracy = sorted(
            lab for (lab, a), g in grades.items() if a == arm and g.scores["accuracy"] == 1
        )
        refer = sorted(lab for (lab, a), g in grades.items() if a == arm and g.should_refer)
        silent = sorted(lab for (lab, a), g in grades.items() if a == arm and g.should_silent)
        lines.append(f"{arm}: ساخته‌شده={invented or '—'}")
        lines.append(
            f"   کلی صفر={zero or '—'} | سیاست نمره‌ی ۱={policy or '—'} | "
            f"صحت نمره‌ی ۱={accuracy or '—'}"
        )
        lines.append(f"   باید ارجاع می‌شد={refer or '—'} | باید ساکت می‌ماند={silent or '—'}")
    lines.append("")
    lines.append(
        "محدودیت‌ها: کور بودن کامل نیست (سبک نوشتار لو می‌دهد)؛ حافظه‌ی دانشجو وضعیت امروز است؛ "
        "مدل غیرقطعی است؛ نام در متن آزاد ممکن است کاملاً پوشانده نشده باشد."
    )
    return "\n".join(lines)


def load_key(path: Path) -> dict[str, Any]:
    try:
        key = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EvalError(f"کلید باز یا خوانده نشد ({type(exc).__name__})") from exc
    if not isinstance(key, dict) or key.get("kind") != KIND_KEY:
        raise EvalError("این فایل کلید conversation-eval نیست")
    return key


def make_report(key_path: Path, graded_path: Path) -> str:
    key = load_key(key_path)
    grades, problems = load_grades(graded_path, key)
    return analyse(key, grades, problems)


def write_report(report: str, out_dir: Path) -> Path:
    path = out_dir / REPORT_NAME
    mc._write_private(path, report + "\n")
    return path


__all__ = [
    "ARMS",
    "ARM_A",
    "ARM_C",
    "CRITERIA",
    "EvalError",
    "EvalRun",
    "ToneVariant",
    "analyse",
    "anonymise",
    "build_sheet",
    "build_variant_prompt",
    "disable_retries",
    "estimate",
    "key_document",
    "load_grades",
    "load_key",
    "load_prepared",
    "load_variant",
    "make_report",
    "manifest_hash",
    "may_start",
    "non_tone_differences",
    "parse_arms",
    "parse_variant",
    "prepare",
    "readonly_session",
    "render_plan",
    "render_prepare_summary",
    "render_run_summary",
    "run_eval",
    "split_prompt",
    "validate_variant_prompt",
    "worst_case_usd",
    "write_outputs",
    "write_prepared",
    "write_report",
]
