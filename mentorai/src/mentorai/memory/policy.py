"""سیاست حافظه.

هر چیزی که دانشجو می‌گوید وارد حافظه‌ی بلندمدت نمی‌شود. این ماژول تصمیم می‌گیرد چه
چیزی می‌ماند، و عمداً کد قطعی است نه قضاوت مدل: مدل پیشنهاد می‌دهد، سیاست تصمیم
می‌گیرد. اگر تصمیم را هم به مدل بسپاریم، هیچ مرز قابل اتکایی باقی نمی‌ماند.

جهت پیش‌فرض رد است. دسته‌ای که اینجا نیست، ذخیره نمی‌شود.
"""

from __future__ import annotations

import enum
import re
from dataclasses import dataclass

from mentorai.text import normalize_for_search, normalize_for_storage
from mentorai.text.matching import first_match


class MemoryCategory(enum.StrEnum):
    """دسته‌های مجاز. فهرست سفید است."""

    course = "course"
    learning_stage = "learning_stage"
    interest = "interest"
    goal = "goal"
    constraint = "constraint"
    note = "note"


# دسته‌هایی که فقط یک مقدار دارند: مقدار تازه جای قبلی را می‌گیرد. دانشجو در یک
# دوره است، نه در سه دوره‌ای که در سه ماه مختلف گفته.
SINGLE_VALUED = frozenset({MemoryCategory.course, MemoryCategory.learning_stage})

MAX_CONTENT_CHARS = 300
MIN_CONTENT_CHARS = 3
MIN_CONFIDENCE = 0.6


class RejectReason(enum.StrEnum):
    unknown_category = "unknown_category"
    too_short = "too_short"
    too_long = "too_long"
    low_confidence = "low_confidence"
    contains_pii = "contains_pii"
    contains_sensitive_topic = "contains_sensitive_topic"


# الگوهای اطلاعات شخصی که هرگز نباید در حافظه بمانند. ارقام روی متن نرمال‌شده لاتین‌اند،
# چون نرمال‌سازی ارقام فارسی و عربی را تبدیل می‌کند.
_PII_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("phone", re.compile(r"(?<!\d)(?:\+?98|0)9\d{9}(?!\d)")),
    ("card", re.compile(r"(?<!\d)\d{16}(?!\d)")),
    ("national_id", re.compile(r"(?<!\d)\d{10}(?!\d)")),
    ("iban", re.compile(r"(?i)\bir\d{24}\b")),
    ("email", re.compile(r"[^\s@]+@[^\s@]+\.[^\s@]+")),
    ("long_digits", re.compile(r"(?<!\d)\d{11,}(?!\d)")),
)

# موضوعاتی که حتی اگر در دسته‌ی مجاز بیایند، ماندنشان درست نیست. مسائل مالی و
# شکایت به منتور سپرده می‌شوند و جایشان در ارجاع است، نه در حافظه‌ی دائمی دانشجو.
_SENSITIVE_PHRASES: tuple[str, ...] = (
    "پرداخت",
    "واریز",
    "کارت به کارت",
    # به همان دلیل decision.py: «رسید» تنها با فعل رسیدن اشتباه می‌شود.
    "رسید واریز",
    "رسید پرداخت",
    "فیش واریز",
    "فاکتور",
    "بدهی",
    "قسط",
    "شکایت",
    "بیماری",
    "افسردگی",
    "طلاق",
    "رمز",
    "پسورد",
)


@dataclass(frozen=True)
class Candidate:
    category: str
    content: str
    confidence: float


@dataclass(frozen=True)
class Accepted:
    category: MemoryCategory
    content: str
    content_key: str
    confidence: float
    single_valued: bool


@dataclass(frozen=True)
class Rejected:
    candidate: Candidate
    reason: RejectReason
    detail: str | None = None


def detect_pii(text: str) -> str | None:
    """اولین الگوی اطلاعات شخصی که در متن پیدا شود."""
    for label, pattern in _PII_PATTERNS:
        if pattern.search(text):
            return label
    return None


def detect_sensitive(text: str) -> str | None:
    """موضوع حساس، با تطبیق روی مرز واژه.

    زیررشته کافی نیست: «رسید» داخل «رسیده» می‌افتد و «رمز» داخل «رمزارز»، که هر دو
    واژه‌های کاملاً عادی در گفتگوی یک آکادمی معامله‌گری‌اند.
    """
    return first_match(normalize_for_search(text), _SENSITIVE_PHRASES)


def evaluate(candidate: Candidate) -> Accepted | Rejected:
    """آیا این یافته اجازه‌ی ماندن دارد.

    ترتیب بررسی از ارزان به گران نیست، از خطرناک به کم‌خطر است: اطلاعات شخصی پیش از
    هر چیز دیگری رد می‌شود، حتی اگر دسته‌اش هم نامعتبر باشد.
    """
    content = normalize_for_storage(candidate.content)

    pii = detect_pii(content)
    if pii is not None:
        return Rejected(candidate, RejectReason.contains_pii, pii)

    sensitive = detect_sensitive(content)
    if sensitive is not None:
        return Rejected(candidate, RejectReason.contains_sensitive_topic, sensitive)

    try:
        category = MemoryCategory(candidate.category)
    except ValueError:
        return Rejected(candidate, RejectReason.unknown_category, candidate.category)

    if len(content) < MIN_CONTENT_CHARS:
        return Rejected(candidate, RejectReason.too_short)
    if len(content) > MAX_CONTENT_CHARS:
        return Rejected(candidate, RejectReason.too_long)
    if candidate.confidence < MIN_CONFIDENCE:
        return Rejected(candidate, RejectReason.low_confidence)

    return Accepted(
        category=category,
        content=content,
        # کلید یکتایی روی شکل نرمال‌شده، تا همان واقعیت با نگارش دیگر دوباره ذخیره نشود.
        content_key=normalize_for_search(content)[:200],
        confidence=candidate.confidence,
        single_valued=category in SINGLE_VALUED,
    )
