"""تقویم شمسی.

تبدیل تقویم جایی است که خطا بی‌سروصدا می‌ماند: یک روز اختلاف در تاریخ انقضای یک سند
پایگاه دانش تا وقتی کسی جواب غلط نگیرد دیده نمی‌شود. پس هم روی تاریخ‌های شناخته‌شده
آزموده می‌شود و هم با رفت‌وبرگشت روی یک قرن، روز به روز.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest

from mentorai.jalali import (
    MONTHS,
    format_date,
    format_date_long,
    from_gregorian,
    is_leap,
    to_gregorian,
)

# تاریخ‌های شناخته‌شده. اولی روز ثبت همین تصمیم در پروژه است، دومی ۲۲ بهمن ۵۷، سومی
# آغاز سال ۲۰۰۰ میلادی.
KNOWN = [
    (date(2026, 9, 2), (1405, 6, 11)),
    (date(1979, 2, 11), (1357, 11, 22)),
    (date(2000, 1, 1), (1378, 10, 11)),
    (date(2026, 3, 21), (1405, 1, 1)),
    # ۱۴۰۴ کبیسه نیست، پس اسفندش ۲۹ روز است.
    (date(2026, 3, 20), (1404, 12, 29)),
    # ۱۴۰۳ کبیسه است و اسفند ۳۰ روزه دارد.
    (date(2025, 3, 20), (1403, 12, 30)),
    (date(2024, 3, 20), (1403, 1, 1)),
]


@pytest.mark.parametrize(("gregorian", "jalali"), KNOWN)
async def test_known_dates_convert_both_ways(gregorian: date, jalali: tuple[int, int, int]) -> None:
    assert from_gregorian(gregorian) == jalali
    assert to_gregorian(*jalali) == gregorian


async def test_a_century_round_trips_day_by_day() -> None:
    """هر روز از ۱۹۵۰ تا ۲۰۵۰ باید به شمسی و برگشت همان روز بماند.

    این آزمون همان چیزی است که جای یک کتابخانه‌ی بیرونی را می‌گیرد: اگر قاعده‌ی کبیسه
    یا گرد کردن تقسیم جایی اشتباه باشد، در این بازه خودش را نشان می‌دهد.
    """
    day = date(1950, 1, 1)
    end = date(2050, 12, 31)
    step = timedelta(days=1)
    while day <= end:
        assert to_gregorian(*from_gregorian(day)) == day, day
        day += step


async def test_new_year_always_lands_on_the_first_of_farvardin() -> None:
    """اول فروردین هر سال باید دقیقاً یک روز بعد از آخرین روز اسفند سال قبل باشد."""
    for jy in range(1350, 1451):
        nowruz = to_gregorian(jy, 1, 1)
        assert from_gregorian(nowruz) == (jy, 1, 1)
        assert from_gregorian(nowruz - timedelta(days=1))[0] == jy - 1


async def test_year_length_matches_the_leap_rule() -> None:
    for jy in range(1350, 1451):
        length = (to_gregorian(jy + 1, 1, 1) - to_gregorian(jy, 1, 1)).days
        assert length == (366 if is_leap(jy) else 365), jy


async def test_first_six_months_have_thirty_one_days() -> None:
    for jm in range(1, 7):
        assert (to_gregorian(1405, jm + 1, 1) - to_gregorian(1405, jm, 1)).days == 31
    for jm in range(7, 12):
        assert (to_gregorian(1405, jm + 1, 1) - to_gregorian(1405, jm, 1)).days == 30


async def test_formats() -> None:
    assert format_date(date(2026, 9, 2)) == "1405/06/11"
    assert format_date_long(date(2026, 9, 2)) == "11 شهریور 1405"
    assert MONTHS[0] == "فروردین"


async def test_a_year_outside_the_table_is_refused() -> None:
    """بیرون از بازه‌ی جدول، خطا داده می‌شود و نه تاریخ حدسی."""
    with pytest.raises(ValueError):
        to_gregorian(3178, 1, 1)
