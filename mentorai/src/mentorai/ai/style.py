"""پاک‌سازی علامت‌های نگارشی پاسخ، برای اینکه شبیه تایپ یک منتور در تلگرام شود.

منتور واقعی در تلگرام معمولاً فقط ویرگول و نهایتاً یک نقطه می‌گذارد؛ گیومه، علامت تعجب و
دونقطه حس آدم‌بودن را می‌گیرد. علامت سؤال گاهی مجاز است و حذف نمی‌شود. دستور مدل همین را
می‌خواهد، ولی مدل گاهی یادش می‌رود؛ این تابع همان قاعده را در کد تضمین می‌کند.
متن را عوض نمی‌کند، فقط علامت‌ها را برمی‌دارد.

عمداً محافظه‌کار است: دونقطه‌ی میان عدد و نشانی اینترنتی («10:30»، «https://...») دست نمی‌خورد،
چون حذفش خود پیام را خراب می‌کند.
"""

from __future__ import annotations

import re
import zlib

_QUOTES = re.compile('[«»“”"]')
_EXCLAMATION = re.compile(r"!+(?=\s|$)")
_ELLIPSIS = re.compile(r"…|\.{3,}")
_SEMICOLON = re.compile(r"[؛;](?=\s|$)")
_COLON = re.compile(r":(?=\s|$)")
_SPACES_BEFORE_COMMA = re.compile(r"[ \t]+([،.])")
_DOUBLE_COMMA = re.compile(r"،(\s*،)+")


# از هر ۱۰۰ تکه‌ی پایان‌یافته با نقطه، این‌قدر نقطه‌اش می‌ماند. منتور واقعی گاهی نقطه می‌گذارد،
# نه همیشه؛ مدل ولی تقریباً همیشه می‌گذارد.
KEEP_FINAL_PERIOD_PERCENT = 25


def _keeps_period(seed: int, index: int) -> bool:
    """تصمیم قطعی برای هر تکه: همان پیام دوباره ساخته شود همان متن را می‌دهد."""
    return zlib.crc32(f"{seed}:{index}".encode()) % 100 < KEEP_FINAL_PERIOD_PERCENT


def _thin_final_periods(text: str, seed: int) -> str:
    chunks = text.split("\n\n")
    for i, chunk in enumerate(chunks):
        if chunk.endswith(".") and not chunk.endswith("..") and not _keeps_period(seed, i):
            chunks[i] = chunk[:-1].rstrip()
    return "\n\n".join(chunks)


def humanize_punctuation(text: str, *, seed: int | None = None) -> str:
    """متن بدون گیومه، علامت تعجب، سه‌نقطه، نقطه‌ویرگول و دونقطه‌ی پایان‌جمله.

    دونقطه و نقطه‌ویرگول به ویرگول فارسی تبدیل می‌شوند و بقیه حذف. خطوط خالی میان پیام‌ها
    (جداکننده‌ی تکه‌ها) حفظ می‌شود. اگر `seed` داده شود، نقطه‌ی پایان بیشتر تکه‌ها هم برداشته می‌شود
    (قطعی برای هر seed)، چون منتور همیشه نقطه نمی‌گذارد.
    """
    out = _QUOTES.sub("", text)
    out = _ELLIPSIS.sub("", out)
    out = _EXCLAMATION.sub("", out)
    out = _SEMICOLON.sub("،", out)
    out = _COLON.sub("،", out)
    out = _SPACES_BEFORE_COMMA.sub(r"\1", out)
    out = _DOUBLE_COMMA.sub("،", out)
    # ویرگول آخر خط معنایی ندارد: «اول این،» می‌شود «اول این».
    out = re.sub(r"،[ \t]*$", "", out, flags=re.MULTILINE)
    lines = [re.sub(r"[ \t]{2,}", " ", line).strip() for line in out.split("\n")]
    cleaned = "\n".join(lines).strip()
    if seed is not None:
        cleaned = _thin_final_periods(cleaned, seed) or cleaned
    return cleaned or text.strip()
