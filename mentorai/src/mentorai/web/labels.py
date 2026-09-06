"""برگردان کدهای داخلی به زبان آدمیزاد.

پنل برای منتور است، نه برای برنامه‌نویس. کد `no_sources` به منتور نمی‌گوید چه اتفاقی
افتاده؛ «در پایگاه دانش چیزی برای این پرسش پیدا نشد» می‌گوید. این جدول عمداً اینجاست و
نه داخل قالب‌ها، تا یک جای واحد داشته باشد.
"""

from __future__ import annotations

SILENCE_REASONS: dict[str, str] = {
    "rule_money": "موضوع مالی بود؛ طبق قاعده به منتور سپرده شد",
    "rule_complaint": "شکایت یا نارضایتی بود؛ طبق قاعده به منتور سپرده شد",
    "rule_account": "موضوع حساب کاربری یا دسترسی بود؛ طبق قاعده به منتور سپرده شد",
    "rule_explicit_human_request": "دانشجو صریحاً منتور خواست",
    "no_sources": "در پایگاه دانش چیزی برای این پرسش پیدا نشد",
    "model_error": "فراخوانی مدل خطا داد",
    "model_flagged": "خود مدل گفت مطمئن نیست",
    "low_confidence": "اطمینان مدل از حد لازم کمتر بود",
    "empty_answer": "مدل پاسخی تولید نکرد",
}

CONVERSATION_STATUS: dict[str, str] = {
    "active": "فعال",
    "awaiting_mentor": "در انتظار منتور",
    "closed": "بسته",
}

SENDER: dict[str, str] = {
    "student": "دانشجو",
    "assistant": "دستیار",
    "mentor": "منتور",
}

SOURCE_CLASS: dict[str, str] = {
    "official": "رسمی",
    "mentor": "منتور",
}

AUTHORITY: dict[str, str] = {
    "fact": "واقعیت",
    "policy": "سیاست",
    "guidance": "راهنما",
}


def silence_reason(code: str) -> str:
    return SILENCE_REASONS.get(code, code)


def conversation_status(code: str) -> str:
    return CONVERSATION_STATUS.get(code, code)


def sender(code: str) -> str:
    return SENDER.get(code, code)


def source_class(code: str) -> str:
    return SOURCE_CLASS.get(code, code)


def authority(code: str) -> str:
    return AUTHORITY.get(code, code)
