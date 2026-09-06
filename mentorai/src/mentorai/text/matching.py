"""تطبیق عبارت روی متن فارسی.

مقایسه‌ی زیررشته‌ای در فارسی مثبت کاذب می‌سازد و مثال‌هایش در همین پروژه واقعی‌اند:
«رسید» زیررشته‌ی «رسیده» است، و «رمز» زیررشته‌ی «رمزارز» — که در یک آکادمی معامله‌گری
کلمه‌ی پرکاربردی است. تطبیق باید روی مرز واژه انجام شود.

دو شکل هر عبارت بررسی می‌شود: با فاصله و بدون فاصله. نرمال‌سازی جستجو نیم‌فاصله را
حذف می‌کند، پس «حساب‌کاربری» به یک واژه‌ی «حسابکاربری» تبدیل می‌شود در حالی که عبارت
قاعده «حساب کاربری» است. جمع کردن کل متن به یک رشته‌ی بی‌فاصله این را حل نمی‌کند، چون
آن‌وقت کل جمله یک واژه می‌شود و مرز واژه بی‌معنی.

مرز واژه‌ی سخت هم به‌تنهایی کافی نیست: فارسی ضمیر ملکی را می‌چسباند، پس «پرداختم» و
«رمزم» باید همان واژه شمرده شوند. پسوندهای مجاز فهرست بسته‌ای هستند، نه هر ادامه‌ای.

جهت خطا عمدی است. مثبت کاذب یعنی مکالمه بی‌دلیل به منتور می‌رسد؛ منفی کاذب یعنی دستیار
به سؤال پرداخت جواب می‌دهد. اولی هزینه‌ی وقت دارد، دومی هزینه‌ی اعتبار.
"""

from __future__ import annotations

import re
from functools import lru_cache

from mentorai.text import normalize_for_search

# پسوندهای متصل فارسی که واژه را عوض نمی‌کنند: ضمایر ملکی و جمع.
# «پرداختم» و «رمزم» باید همان «پرداخت» و «رمز» شمرده شوند.
#
# «ه» عمداً نیست: «رسیده» واژه‌ی دیگری است، نه «رسید» با پسوند. همین یک استثنا
# تفاوت بین گرفتن رسید پرداخت و گرفتن هر جمله‌ای است که فعلش به «رسیده» ختم می‌شود.
_SUFFIXES = (
    "هایمان",
    "هایتان",
    "هایشان",
    "هایم",
    "هایت",
    "هایش",
    "مان",
    "تان",
    "شان",
    "های",
    "ها",
    "ام",
    "ات",
    "اش",
    "م",
    "ت",
    "ش",
    "ی",
)


@lru_cache(maxsize=512)
def _pattern(phrase: str) -> re.Pattern[str]:
    normalized = normalize_for_search(phrase)
    forms = {normalized}
    if " " in normalized:
        forms.add(normalized.replace(" ", ""))
    alternatives = "|".join(re.escape(form) for form in sorted(forms, key=len, reverse=True))
    suffixes = "|".join(re.escape(s) for s in _SUFFIXES)
    return re.compile(rf"(?<!\w)(?:{alternatives})(?:{suffixes})?(?!\w)")


def contains_phrase(normalized_text: str, phrase: str) -> bool:
    """آیا این عبارت به‌عنوان یک واژه‌ی کامل در متن نرمال‌شده هست."""
    return _pattern(phrase).search(normalized_text) is not None


def first_match(normalized_text: str, phrases: tuple[str, ...]) -> str | None:
    for phrase in phrases:
        if contains_phrase(normalized_text, phrase):
            return phrase
    return None
