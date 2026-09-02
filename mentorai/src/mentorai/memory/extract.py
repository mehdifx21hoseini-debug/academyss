"""استخراج یافته‌های حافظه از یک مکالمه.

عمداً جدا از مسیر پاسخ اجرا می‌شود. استخراج حافظه نباید بین سؤال دانشجو و پاسخ
تأخیر بیندازد؛ کاری است که بعداً و در پس‌زمینه انجام می‌شود.

مدل فقط **پیشنهاد** می‌دهد. تصمیم اینکه چه چیزی می‌ماند با سیاست است، نه با مدل.
"""

from __future__ import annotations

import json
from collections.abc import Sequence

from pydantic import BaseModel, Field, ValidationError

from mentorai.ai.client import ModelClient, RawCall
from mentorai.memory.policy import Candidate, MemoryCategory

EXTRACTION_PROMPT_VERSION = "memory-v1"

SYSTEM_PROMPT = """\
از گفتگوی زیر، فقط واقعیت‌های پایدار درباره‌ی خود دانشجو را بیرون بکش.

دسته‌های مجاز و تنها دسته‌های مجاز:
- course: دوره‌ای که در آن است
- learning_stage: سطح یا مرحله‌ی آموزشی او
- interest: موضوعی که به آن علاقه نشان داده
- goal: هدفی که بیان کرده
- constraint: محدودیتی که گفته، مثل زمان کم یا سرمایه محدود
- note: نکته‌ی پایدار دیگری که برای منتور مفید است

قوانین:
۱. فقط چیزی که دانشجو درباره‌ی خودش گفته. حرف دستیار یا منتور را برنگردان.
۲. چیزی که موقتی است برنگردان: حال امروز، سؤال همین لحظه، تعارف.
۳. هیچ اطلاعات تماس، شماره، کد ملی، شماره کارت یا ایمیل برنگردان.
۴. مسائل مالی، پرداخت، شکایت و موضوعات شخصی حساس را برنگردان.
۵. هر یافته یک جمله‌ی کوتاه و مستقل باشد، به فارسی، در سوم‌شخص.
۶. اگر چیز پایداری نبود، فهرست خالی برگردان. خالی برگرداندن کاملاً درست است.
۷. confidence را واقع‌بینانه بده؛ حدس با اطمینان بالا بدترین حالت است.
"""


class MemoryCandidateOut(BaseModel):
    category: str = Field(description="یکی از دسته‌های مجاز")
    content: str = Field(description="یک جمله‌ی کوتاه فارسی، سوم‌شخص")
    confidence: float = Field(ge=0.0, le=1.0)


class MemoryExtraction(BaseModel):
    candidates: list[MemoryCandidateOut] = Field(default_factory=list)


EXTRACTION_SCHEMA: dict[str, object] = {
    "type": "object",
    "properties": {
        "candidates": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "category": {"type": "string", "enum": [c.value for c in MemoryCategory]},
                    "content": {"type": "string"},
                    "confidence": {"type": "number"},
                },
                "required": ["category", "content", "confidence"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["candidates"],
    "additionalProperties": False,
}


def build_user_content(turns: Sequence[tuple[str, str]]) -> str:
    rendered = "\n".join(f"{role}: {body}" for role, body in turns)
    return f"گفتگو:\n\n{rendered}"


def parse(call: RawCall) -> list[Candidate]:
    """خروجی مدل را به یافته تبدیل کن.

    خروجی نامعتبر یعنی هیچ یافته‌ای، نه استثنا. نتوانستن در استخراج حافظه هرگز نباید
    مسیر پاسخ یا کارگر را بشکند؛ نداشتن حافظه بدتر از داشتن حافظه‌ی غلط نیست.
    """
    if call.error is not None or not call.text:
        return []
    try:
        parsed = MemoryExtraction.model_validate(json.loads(call.text))
    except (json.JSONDecodeError, ValidationError):
        return []
    return [
        Candidate(category=c.category, content=c.content, confidence=c.confidence)
        for c in parsed.candidates
    ]


class MemoryExtractor:
    """پوشش نازک روی کلاینت مدل، با شکل خروجی مخصوص حافظه."""

    def __init__(self, client: ModelClient) -> None:
        self._client = client

    @property
    def model(self) -> str:
        return self._client.model

    async def extract(self, turns: Sequence[tuple[str, str]]) -> list[Candidate]:
        if not turns:
            return []
        call = await self._client.raw(
            system=SYSTEM_PROMPT,
            user=build_user_content(turns),
            schema=EXTRACTION_SCHEMA,
        )
        return parse(call)
