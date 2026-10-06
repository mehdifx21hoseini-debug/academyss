"""آخرین دروازه پیش از رسیدن پاسخ به دانشجو — در کد، نه در دستور مدل.

دستور مدل یک **درخواست** است، نه تضمین. «قیمت را فقط از منبع رسمی بگو» در
`SYSTEM_PROMPT` هست و معمولاً رعایت می‌شود، ولی «معمولاً» برای عددی که دانشجو
ممکن است رویش پول بفرستد کافی نیست.

این ماژول روی **متن تولیدشده** کار می‌کند و به حرف مدل کاری ندارد. ورودی‌اش رشته
است و خروجی‌اش دلیلِ رد یا `None`. هیچ نشست و هیچ تماس شبکه‌ای ندارد تا بشود کامل
تستش کرد.

قاعده‌ی حاکم همان جهت شکست همیشگی است: اگر شک داشتیم، سکوت و ارجاع به منتور.
"""

from __future__ import annotations

import re

from mentorai.knowledge.retrieval import Hit
from mentorai.text import normalize_for_search

# واحدهایی که عدد کنارشان «مبلغ» است، نه «اندازه».
#
# «درصد» عمداً اینجا نیست: «قانون ۲ درصد» آموزش است نه قیمت، و بیشتر پایگاه دانش
# از همین جنس است. «پیپ» و «لات» هم به همین دلیل نیستند.
MONEY_UNITS: tuple[str, ...] = (
    "تومان",
    "تومن",
    "ریال",
    "دلار",
    "یورو",
    "درهم",
    "تتر",
)

# عددی که کنار واحد پول نشسته. فاصله‌ی میان‌شان می‌تواند واژه‌ی مقیاس باشد:
# «۵۰۰ هزار تومان» یا «۲ میلیون تومان».
_SCALE = r"(?:\s*(?:هزار|میلیون|میلیارد))*"
_AMOUNT = re.compile(
    r"(\d[\d,٬.]*)" + _SCALE + r"\s*(?:" + "|".join(MONEY_UNITS) + r")",
)


def money_amounts(text: str) -> list[str]:
    """مبلغ‌های متن، به شکل نرمال‌شده‌ی رقمی.

    روی متن نرمال‌شده کار می‌کند، پس «۵۰۰» و «500» یکی حساب می‌شوند — وگرنه محافظ
    را می‌شد تنها با عوض کردن شکل ارقام دور زد.
    """
    normalized = normalize_for_search(text)
    return [_digits(m.group(1)) for m in _AMOUNT.finditer(normalized)]


def _digits(raw: str) -> str:
    return re.sub(r"[^\d]", "", raw)


def ungrounded_money(answer: str, *, hits: list[Hit], question: str = "") -> str | None:
    """مبلغی که در هیچ منبع رسمی و در خود سؤال نیست — یا `None`.

    **چرا این سخت‌ترین قاعده‌ی سیستم است.** بدترین خطای ممکن این دستیار، گفتن یک
    قیمت اشتباه به دانشجوست: برخلاف توضیح آموزشی ناقص، این یکی قابل جبران نیست و
    مستقیم به پول آدم‌ها می‌خورد. پس شرط، تکرار عینِ عدد از منبع است، نه قضاوت
    مدل درباره‌ی اینکه «منبع داشتم یا نه».

    سؤال خود دانشجو هم منبع مجاز است: اگر او پرسیده «با ۱۰۰ دلار می‌شه شروع کرد؟»،
    تکرار همان ۱۰۰ در پاسخ، اختراع قیمت نیست.

    جهت خطا عمدی است. اگر منبع رسمی «پانصد هزار تومان» را با حرف نوشته باشد و مدل
    «۵۰۰ هزار تومان» بنویسد، این تابع ردش می‌کند و پیام به منتور می‌رود. سکوتِ
    بی‌دلیل، بهای ارزانی است در برابر قیمتِ ساختگی.
    """
    amounts = money_amounts(answer)
    if not amounts:
        return None

    allowed: set[str] = set()
    for hit in hits:
        if hit.source_class == "official":
            allowed.update(money_amounts(hit.content))
            allowed.update(_digits(x) for x in re.findall(r"\d[\d,٬.]*", hit.content))
    allowed.update(_digits(x) for x in re.findall(r"\d[\d,٬.]*", normalize_for_search(question)))

    for amount in amounts:
        if amount not in allowed:
            return amount
    return None


__all__ = ["MONEY_UNITS", "money_amounts", "ungrounded_money"]
