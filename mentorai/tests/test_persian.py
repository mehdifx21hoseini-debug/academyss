"""نرمال‌سازی فارسی.

این تست‌ها همان چیزی را می‌سنجند که در سیستم قبلی نبود و باعث می‌شد جستجو بی‌دلیل
چیزی پیدا نکند.
"""

from __future__ import annotations

import pytest

from mentorai.text import normalize_for_search, normalize_for_storage

ZWNJ = "‌"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("كتاب", "کتاب"),  # ك عربی
        ("يک", "یک"),  # ي عربی
        ("علي", "علی"),
        ("مدرسة", "مدرسه"),  # ة
        ("أحمد", "احمد"),
        ("۱۲۳", "123"),  # ارقام فارسی
        ("٤٥٦", "456"),  # ارقام عربی
        ("مُعامله", "معامله"),  # اعراب
        ("خــط", "خط"),  # کشیده
    ],
)
def test_storage_canonicalises_letters_and_digits(raw: str, expected: str) -> None:
    assert normalize_for_storage(raw) == expected


def test_storage_keeps_zwnj_so_text_stays_readable() -> None:
    assert ZWNJ in normalize_for_storage(f"می{ZWNJ}روم")


def test_storage_collapses_spaces_but_keeps_paragraphs() -> None:
    assert normalize_for_storage("سلام    دنیا") == "سلام دنیا"
    assert normalize_for_storage("خط اول\n\n\n\nخط دوم") == "خط اول\n\nخط دوم"


def test_search_key_joins_across_zwnj() -> None:
    """«می‌روم» و «میروم» باید یک کلید بدهند."""
    assert normalize_for_search(f"می{ZWNJ}روم") == normalize_for_search("میروم")


def test_search_key_unifies_arabic_and_persian_forms() -> None:
    assert normalize_for_search("كتابهاي علي") == normalize_for_search("کتابهای علی")


def test_search_key_unifies_digit_systems() -> None:
    assert normalize_for_search("دوره ۲") == normalize_for_search("دوره 2")
    assert normalize_for_search("دوره ٢") == normalize_for_search("دوره 2")


def test_search_key_is_idempotent() -> None:
    once = normalize_for_search(f"مُعامله{ZWNJ}گري ۱۲۳")
    assert normalize_for_search(once) == once


def test_search_key_strips_invisible_direction_marks() -> None:
    assert normalize_for_search("سلام‏‎") == "سلام"


def test_alef_madda_is_preserved() -> None:
    """آ حرف مستقلی در فارسی است و نباید به ا تبدیل شود."""
    assert "آ" in normalize_for_storage("آموزش")
