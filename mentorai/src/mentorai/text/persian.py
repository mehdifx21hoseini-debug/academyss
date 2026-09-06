"""نرمال‌سازی متن فارسی.

یک ماژول، دو تابع، و هر دو مسیر ذخیره و جستجو از همین‌جا صدا زده می‌شوند. اگر دو مسیر
پیاده‌سازی جدا داشته باشند، به‌مرور از هم واگرا می‌شوند و هیچ‌کس متوجه نمی‌شود تا وقتی
جستجو بی‌دلیل چیزی پیدا نکند.
"""

from __future__ import annotations

import re
import unicodedata

# حروف عربی که در فارسی شکل دیگری دارند.
_LETTER_MAP = {
    "ي": "ی",  # ي عربی  -> ی فارسی
    "ى": "ی",  # ى الف مقصوره -> ی
    "ك": "ک",  # ك عربی  -> ک فارسی
    "ة": "ه",  # ة       -> ه
    "ۀ": "ه",  # ۀ       -> ه
    "أ": "ا",  # أ       -> ا
    "إ": "ا",  # إ       -> ا
    "ٱ": "ا",  # ٱ       -> ا
    # آ (آ) عمداً دست‌نخورده می‌ماند؛ در فارسی حرف مستقلی است.
}

# ارقام فارسی ۰-۹ و عربی ٠-٩ به ارقام لاتین.
_DIGIT_MAP = {chr(0x06F0 + i): str(i) for i in range(10)} | {
    chr(0x0660 + i): str(i) for i in range(10)
}

_TRANSLATION = str.maketrans(_LETTER_MAP | _DIGIT_MAP)

# اعراب و علائم کوچک عربی، به‌علاوه کشیده.
_DIACRITICS = re.compile("[ً-ٰٟـ]")

# نویسه‌های نامرئی جهت‌دهی که هنگام کپی از منابع مختلف وارد متن می‌شوند.
# نیم‌فاصله (‌) اینجا نیست چون معنادار است و جداگانه اداره می‌شود.
_INVISIBLE = re.compile("[​‍‎‏⁦-⁩﻿]")

_ZWNJ = "‌"
_WHITESPACE = re.compile(r"\s+")


def _shared(text: str) -> str:
    """آنچه هر دو مسیر لازم دارند."""
    text = unicodedata.normalize("NFC", text)
    text = _INVISIBLE.sub("", text)
    text = text.translate(_TRANSLATION)
    text = _DIACRITICS.sub("", text)
    return text


def normalize_for_storage(text: str) -> str:
    """شکل متعارف برای ذخیره و نمایش.

    نیم‌فاصله نگه داشته می‌شود، چون متن باید همان‌طور که نوشته شده خوانا بماند.
    """
    text = _shared(text)
    # فاصله‌های تکراری جمع می‌شوند، ولی خطوط جدید حفظ می‌شوند.
    text = re.sub(r"[^\S\n]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def normalize_for_search(text: str) -> str:
    """کلید تطبیق برای جستجو و مقایسه.

    نیم‌فاصله حذف می‌شود تا «می‌روم» و «میروم» یک کلید بدهند.

    محدودیت شناخته‌شده: شکل با فاصله‌ی کامل، یعنی «می روم»، کلید دیگری می‌دهد. حل آن
    به ریشه‌یاب فارسی نیاز دارد و به مرحله‌ی بازیابی موکول شده، جایی که با مجموعه‌ی
    ارزیابی سنجیده می‌شود؛ حدس زدنش اینجا بی‌فایده است.
    """
    text = _shared(text).replace(_ZWNJ, "")
    text = _WHITESPACE.sub(" ", text)
    return text.strip().lower()
