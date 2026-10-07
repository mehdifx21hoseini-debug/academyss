"""انتخاب ارائه‌دهنده‌ی هوش مصنوعی (ADR-035).

بقیه‌ی سیستم فقط به `ModelClient` و `VisionClient` وابسته است (`client.py`)؛ هیچ‌جا نام
یک ارائه‌دهنده نیامده. اینجا تنها جایی است که `AI_PROVIDER` به یک کلاس تبدیل می‌شود.

**افزودن ارائه‌دهنده‌ی تازه:**
1. کلاسی بنویسید که `ChatAndVision` را پیاده کند: `model`، `effort`، `raw`، `complete`،
   `describe_image`. هرگز استثنا پرتاب نکند؛ هر شکستی را در `RawCall.error` برگرداند و
   پاسخ بریده‌شده یا ردشده را موفق حساب نکند.
2. `from_settings` داشته باشد که هر کمبودی را **هنگام روشن شدن** رد کند.
3. نامش را به `Literal` در `config.Settings.ai_provider` و به `_PROVIDERS` اینجا بیفزایید.
4. آزمون بنویسید: درخواست ارسالی، شمارش مصرف، و بریده شدن. از `tests/test_openai_client.py`
   الگو بگیرید. قیمت مدل‌ها در `.env` می‌آید، نه در کد.
5. پیش از استفاده روی سرور `mentorai model-check` بزنید.
"""

from __future__ import annotations

from collections.abc import Callable

from mentorai.ai.client import AnthropicClient, ChatAndVision
from mentorai.config import get_settings


def _openai() -> ChatAndVision:
    # ایمپورت درون تابع: فقط وقتی openai انتخاب شده بارگذاری می‌شود.
    from mentorai.ai.openai_client import OpenAIClient

    return OpenAIClient.from_settings()


_PROVIDERS: dict[str, Callable[[], ChatAndVision]] = {
    "anthropic": AnthropicClient.from_settings,
    "openai": _openai,
}


def build_client() -> ChatAndVision:
    """کلاینت ارائه‌دهنده‌ی انتخاب‌شده. هر پیکربندی ناقص همین‌جا و با `ValueError` رد می‌شود."""
    name = get_settings().ai_provider
    try:
        factory = _PROVIDERS[name]
    except KeyError:
        raise ValueError(f"AI_PROVIDER={name!r} ناشناخته است: {', '.join(_PROVIDERS)}") from None
    return factory()
