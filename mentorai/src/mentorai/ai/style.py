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

_QUOTES = re.compile('[«»“”"]')
_EXCLAMATION = re.compile(r"!+(?=\s|$)")
_ELLIPSIS = re.compile(r"…|\.{3,}")
_SEMICOLON = re.compile(r"[؛;](?=\s|$)")
_COLON = re.compile(r":(?=\s|$)")
_SPACES_BEFORE_COMMA = re.compile(r"[ \t]+([،.])")
_DOUBLE_COMMA = re.compile(r"،(\s*،)+")


def humanize_punctuation(text: str) -> str:
    """متن بدون گیومه، علامت تعجب، سه‌نقطه، نقطه‌ویرگول و دونقطه‌ی پایان‌جمله.

    دونقطه و نقطه‌ویرگول به ویرگول فارسی تبدیل می‌شوند و بقیه حذف. خطوط خالی میان پیام‌ها
    (جداکننده‌ی تکه‌ها) حفظ می‌شود.
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
    return cleaned or text.strip()
