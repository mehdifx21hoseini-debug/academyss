"""تقویم هجری شمسی.

**چرا کتابخانه استفاده نشده.** تبدیل تقویم یک محاسبه‌ی بسته و کاملاً قابل آزمون است:
ورودی و خروجی هر دو عدد، بدون شبکه، بدون حالت، بدون پیکربندی. در برابرش، هر وابستگی
تازه در سامانه‌ای که نشست کامل حساب‌های تلگرام را نگه می‌دارد یک سطح تماس اضافه است.
درستی این پیاده‌سازی با تبدیل رفت‌وبرگشت روی صد سال، روز به روز، آزموده می‌شود؛ همان
چیزی که یک کتابخانه هم بیش از آن نمی‌داد.

الگوریتم همان روش شناخته‌شده‌ی مبتنی بر «نقطه‌های شکست» چرخه‌ی سی‌وسه‌ساله است. سال کبیسه
در تقویم شمسی الگوی ساده‌ای ندارد و همین جدول است که آن را دقیق نگه می‌دارد.
"""

from __future__ import annotations

from datetime import date

MONTHS = (
    "فروردین",
    "اردیبهشت",
    "خرداد",
    "تیر",
    "مرداد",
    "شهریور",
    "مهر",
    "آبان",
    "آذر",
    "دی",
    "بهمن",
    "اسفند",
)

# نقطه‌های شکست چرخه‌ی کبیسه. بازه‌ی معتبر همین جدول است و بیرون از آن خطا داده می‌شود
# نه حدس: تاریخ اشتباه بی‌سروصدا بدتر از خطاست.
_BREAKS = (
    -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181,
    1210, 1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
)  # fmt: skip

MIN_YEAR = _BREAKS[0]
MAX_YEAR = _BREAKS[-1] - 1


def _div(a: int, b: int) -> int:
    """تقسیم صحیح با گرد شدن به سمت صفر.

    عمداً `//` پایتون نیست: آن به سمت منهابی‌نهایت گرد می‌کند و در این الگوریتم چند
    جا ورودی منفی می‌آید. تفاوت یک واحد آنجا یعنی یک روز خطا.
    """
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def _mod(a: int, b: int) -> int:
    return a - _div(a, b) * b


def _cycle(jy: int) -> tuple[int, int, int]:
    """(کبیسه بودن، سال میلادی متناظر، روز مارس که اول فروردین است)."""
    if jy < MIN_YEAR or jy > MAX_YEAR:
        raise ValueError(f"سال {jy} بیرون از بازه‌ی معتبر تقویم است")

    gy = jy + 621
    leap_j = -14
    jp = _BREAKS[0]
    jump = 0
    for jm in _BREAKS[1:]:
        jump = jm - jp
        if jy < jm:
            break
        leap_j += _div(jump, 33) * 8 + _div(_mod(jump, 33), 4)
        jp = jm

    n = jy - jp
    leap_j += _div(n, 33) * 8 + _div(_mod(n, 33) + 3, 4)
    if _mod(jump, 33) == 4 and jump - n == 4:
        leap_j += 1

    leap_g = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150
    march = 20 + leap_j - leap_g

    if jump - n < 6:
        n = n - jump + _div(jump + 4, 33) * 33
    leap = _mod(_mod(n + 1, 33) - 1, 4)
    if leap == -1:
        leap = 4
    return leap, gy, march


def _gregorian_to_jdn(gy: int, gm: int, gd: int) -> int:
    d = (
        _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4)
        + _div(153 * _mod(gm + 9, 12) + 2, 5)
        + gd
        - 34840408
    )
    return d - _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) + 752


def _jdn_to_gregorian_year(jdn: int) -> int:
    j = 4 * jdn + 139361631
    j += _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908
    i = _div(_mod(j, 1461), 4) * 5 + 308
    gm = _mod(_div(i, 153), 12) + 1
    return _div(j, 1461) - 100100 + _div(8 - gm, 6)


def from_gregorian(value: date) -> tuple[int, int, int]:
    """(سال، ماه، روز) شمسی."""
    jdn = _gregorian_to_jdn(value.year, value.month, value.day)
    gy = _jdn_to_gregorian_year(jdn)
    jy = gy - 621
    leap, _, march = _cycle(jy)
    k = jdn - _gregorian_to_jdn(gy, 3, march)

    if k >= 0:
        if k <= 185:
            return jy, 1 + _div(k, 31), _mod(k, 31) + 1
        k -= 186
    else:
        jy -= 1
        k += 179
        if leap == 1:
            k += 1
    return jy, 7 + _div(k, 30), _mod(k, 30) + 1


def to_gregorian(jy: int, jm: int, jd: int) -> date:
    _, gy, march = _cycle(jy)
    jdn = _gregorian_to_jdn(gy, 3, march) + (jm - 1) * 31 - _div(jm, 7) * (jm - 7) + jd - 1

    j = 4 * jdn + 139361631
    j += _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908
    i = _div(_mod(j, 1461), 4) * 5 + 308
    day = _div(_mod(i, 153), 5) + 1
    month = _mod(_div(i, 153), 12) + 1
    year = _div(j, 1461) - 100100 + _div(8 - month, 6)
    return date(year, month, day)


def is_leap(jy: int) -> bool:
    return _cycle(jy)[0] == 0


def format_date(value: date) -> str:
    """تاریخ عددی، مثل ۱۴۰۵/۰۶/۱۱."""
    jy, jm, jd = from_gregorian(value)
    return f"{jy:04d}/{jm:02d}/{jd:02d}"


def format_date_long(value: date) -> str:
    """تاریخ با نام ماه، مثل ۱۱ شهریور ۱۴۰۵."""
    jy, jm, jd = from_gregorian(value)
    return f"{jd} {MONTHS[jm - 1]} {jy}"
