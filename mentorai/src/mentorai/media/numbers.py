"""خواندن عددی که آدم نوشته یا ترمینال چاپ کرده.

گزارش متاتریدر بسته به زبان و تنظیمات ویندوزِ دانشجو، عدد را به شکل‌های مختلفی
می‌نویسد: با فاصله‌ی هزارگان، با کاما، با ارقام فارسی، و منفی گاهی داخل پرانتز.
خواندن اشتباه یک عدد در استیتمنت یعنی نتیجه‌گیری اشتباه درباره‌ی حساب کسی، پس این
تبدیل جای حدس زدن نیست.
"""

from __future__ import annotations

import re

_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
# فاصله‌ی معمولی، فاصله‌ی بدون‌شکست، فاصله‌ی باریک، و جداکننده‌ی هزارگان یونیکد.
_SPACES = re.compile(r"[\s    ]+")
_ALLOWED = re.compile(r"^-?\d+(\.\d+)?$")
# کاما با یک یا دو رقم بعدش نمی‌تواند جداکننده‌ی هزارگان باشد؛ گروه هزارگان همیشه
# سه‌رقمی است. پس «۱٫۵۰» اعشار است و «۱٫۵۰۰» هزارگان.
_COMMA_DECIMAL = re.compile(r"^(-?\d+),(\d{1,2})$")


def parse_number(raw: str | None) -> float | None:
    """عدد، یا None اگر این رشته عدد نیست.

    None یعنی «نخواندم»، نه صفر. صفر گرفتنِ چیزی که خوانده نشده، در محاسبه‌ی سود و
    زیان خطای بی‌صدا می‌سازد.
    """
    if raw is None:
        return None
    text = _SPACES.sub("", str(raw).translate(_DIGITS))
    if not text:
        return None

    negative = False
    if text.startswith("(") and text.endswith(")"):
        negative = True
        text = text[1:-1]
    text = text.replace("−", "-").replace("+", "")

    if "," in text and "." in text:
        # هرکدام آخر آمده، اعشار است و دیگری جداکننده‌ی هزارگان.
        if text.rfind(",") > text.rfind("."):
            text = text.replace(".", "").replace(",", ".")
        else:
            text = text.replace(",", "")
    elif "," in text:
        match = _COMMA_DECIMAL.match(text)
        text = f"{match.group(1)}.{match.group(2)}" if match else text.replace(",", "")

    if not _ALLOWED.match(text):
        return None
    value = float(text)
    return -value if negative else value
