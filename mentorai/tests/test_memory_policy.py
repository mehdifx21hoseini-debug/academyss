"""سیاست حافظه.

هر چیزی که دانشجو می‌گوید وارد حافظه‌ی بلندمدت نمی‌شود. این تست‌ها همان مرز را
می‌سنجند، و مهم‌ترینشان تست‌های رد کردن‌اند.
"""

from __future__ import annotations

import pytest

from mentorai.memory.policy import (
    Accepted,
    Candidate,
    MemoryCategory,
    Rejected,
    RejectReason,
    detect_pii,
    evaluate,
)


def _candidate(**kw: object) -> Candidate:
    base = {"category": "interest", "content": "به پرایس اکشن علاقه دارد.", "confidence": 0.9}
    return Candidate(**{**base, **kw})  # type: ignore[arg-type]


def test_an_ordinary_fact_is_accepted() -> None:
    verdict = evaluate(_candidate())
    assert isinstance(verdict, Accepted)
    assert verdict.category is MemoryCategory.interest


@pytest.mark.parametrize(
    ("content", "label"),
    [
        ("شماره‌اش ۰۹۱۲۳۴۵۶۷۸۹ است.", "phone"),
        ("شماره کارتش ۶۰۳۷۹۹۱۲۳۴۵۶۷۸۹۰ است.", "card"),
        ("کد ملی او ۰۰۱۲۳۴۵۶۷۸ است.", "national_id"),
        ("ایمیلش ali@example.com است.", "email"),
        ("شبای او IR062960000000100324200001 است.", "iban"),
    ],
)
def test_personal_identifiers_are_never_stored(content: str, label: str) -> None:
    """ارقام فارسی هم گرفته می‌شوند، چون نرمال‌سازی آن‌ها را لاتین می‌کند."""
    verdict = evaluate(_candidate(content=content))
    assert isinstance(verdict, Rejected)
    assert verdict.reason is RejectReason.contains_pii
    assert verdict.detail == label


@pytest.mark.parametrize(
    "content",
    [
        "پرداختش را انجام داده است.",
        "از آکادمی شکایت دارد.",
        "رمز حسابش را فراموش کرده.",
        "درگیر بیماری است.",
    ],
)
def test_sensitive_topics_are_not_kept_as_memory(content: str) -> None:
    """این موضوعات به منتور سپرده می‌شوند؛ جایشان در ارجاع است نه حافظه‌ی دائمی."""
    verdict = evaluate(_candidate(content=content))
    assert isinstance(verdict, Rejected)
    assert verdict.reason is RejectReason.contains_sensitive_topic


def test_pii_is_rejected_before_anything_else() -> None:
    """حتی با دسته‌ی نامعتبر و اطمینان پایین، دلیل رد باید اطلاعات شخصی باشد."""
    verdict = evaluate(
        Candidate(category="نامعتبر", content="شماره‌اش ۰۹۱۲۳۴۵۶۷۸۹ است.", confidence=0.1)
    )
    assert isinstance(verdict, Rejected)
    assert verdict.reason is RejectReason.contains_pii


def test_unknown_category_is_rejected() -> None:
    """فهرست سفید است: دسته‌ای که تعریف نشده، ذخیره نمی‌شود."""
    verdict = evaluate(_candidate(category="payment_status"))
    assert isinstance(verdict, Rejected)
    assert verdict.reason is RejectReason.unknown_category


def test_low_confidence_is_rejected() -> None:
    verdict = evaluate(_candidate(confidence=0.3))
    assert isinstance(verdict, Rejected)
    assert verdict.reason is RejectReason.low_confidence


@pytest.mark.parametrize(
    ("content", "reason"),
    [("ا", RejectReason.too_short), ("ب" * 500, RejectReason.too_long)],
)
def test_length_bounds(content: str, reason: RejectReason) -> None:
    verdict = evaluate(_candidate(content=content))
    assert isinstance(verdict, Rejected)
    assert verdict.reason is reason


def test_course_and_stage_are_single_valued() -> None:
    """دانشجو در یک دوره است، نه در سه دوره‌ای که در سه ماه مختلف گفته."""
    for category in ("course", "learning_stage"):
        verdict = evaluate(_candidate(category=category, content="در دوره پیشرفته است."))
        assert isinstance(verdict, Accepted)
        assert verdict.single_valued is True

    verdict = evaluate(_candidate(category="interest"))
    assert isinstance(verdict, Accepted)
    assert verdict.single_valued is False


def test_content_key_ignores_persian_spelling_differences() -> None:
    """همان واقعیت با نگارش دیگر نباید دو بار ذخیره شود."""
    a = evaluate(_candidate(content="به پرايس اکشن علاقه دارد."))
    b = evaluate(_candidate(content="به پرایس اکشن علاقه دارد."))
    assert isinstance(a, Accepted) and isinstance(b, Accepted)
    assert a.content_key == b.content_key


def test_detect_pii_returns_none_for_clean_text() -> None:
    assert detect_pii("به تحلیل تکنیکال علاقه دارد.") is None
