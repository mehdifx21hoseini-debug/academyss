"""شکل خروجی ساختاریافته‌ی مدل."""

from __future__ import annotations

from pydantic import BaseModel, Field

# v2: قاعده‌ی چندپیامی شدن پاسخ به دستور اضافه شد. نسخه عوض می‌شود تا در
# `ai_runs` بشود پاسخ‌های پیش و پس از آن را از هم جدا کرد.
# v3: «صدای منتور» (ADR-053): اول‌شخص با نام منتور هر حساب، فارسی محاوره، دانش بازار برای
# پرسش‌های بیرون از پایگاه دانش. بندهای ایمنی ۳ تا ۶ و ۱۰ و ۱۱ بایت‌به‌بایت مثل v2 ماندند.
PROMPT_VERSION = "v3"


class ModelAnswer(BaseModel):
    """آنچه مدل باید برگرداند.

    `needs_human` و `confidence` هر دو لازم‌اند و هر دو استفاده می‌شوند. در سیستم قبلی
    آکادمی، `confidence` گرفته می‌شد ولی در تصمیم هیچ نقشی نداشت؛ اینجا آستانه‌اش
    صریح است و در ai_runs ثبت می‌شود تا بعداً بشود کالیبره‌اش کرد.
    """

    answer: str = Field(description="متن پاسخ به فارسی، خطاب به دانشجو")
    confidence: float = Field(ge=0.0, le=1.0, description="اطمینان از درستی پاسخ")
    needs_human: bool = Field(description="اگر این سؤال باید به منتور برسد")
    reason: str = Field(description="دلیل کوتاه تصمیم، برای ثبت داخلی نه برای دانشجو")
    used_chunk_ids: list[int] = Field(
        default_factory=list, description="شناسه‌ی قطعه‌هایی که واقعاً استفاده شدند"
    )


JSON_SCHEMA: dict[str, object] = {
    "type": "object",
    "properties": {
        "answer": {"type": "string"},
        "confidence": {"type": "number"},
        "needs_human": {"type": "boolean"},
        "reason": {"type": "string"},
        "used_chunk_ids": {"type": "array", "items": {"type": "integer"}},
    },
    "required": ["answer", "confidence", "needs_human", "reason", "used_chunk_ids"],
    "additionalProperties": False,
}
