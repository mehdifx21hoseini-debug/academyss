"""فراخوانی مدل.

قاعده‌ی اصلی این ماژول: **هرگز استثنا پرتاب نمی‌کند.** هر شکستی به ModelCall با فیلد
error برمی‌گردد. دلیلش این است که جهت شکست در این سیستم همیشه به سمت انسان است؛ اگر
خطا بالا برود و جایی گرفته نشود، ممکن است به تلاش دوباره یا پاسخ نیمه‌کاره ختم شود.
"""

from __future__ import annotations

import base64
import json
import time
from dataclasses import dataclass
from typing import Any, Literal, Protocol

import structlog
from pydantic import ValidationError

from mentorai.ai.schema import JSON_SCHEMA, ModelAnswer

log = structlog.get_logger(__name__)

Effort = Literal["low", "medium", "high", "xhigh", "max"]

# مقدار واقعی از `.env` می‌آید (`ANTHROPIC_MODEL`)؛ این‌ها فقط برای ساخت مستقیم
# کلاینت در آزمون و ابزارند. انتخاب و دلیلش در `ADR-034`.
DEFAULT_MODEL = "claude-sonnet-5-5"
# تلاش مدل. برای گفتگوی کوتاه با قوانین صریح، متوسط نقطه‌ی معقولی است؛ عدد نهایی
# باید با اندازه‌گیری روی مجموعه‌ی ارزیابی انتخاب شود، نه با حدس.
DEFAULT_EFFORT: Effort = "medium"
DEFAULT_MAX_TOKENS = 8000

# مدل‌هایی که پارامتر effort را نمی‌پذیرند. این کلاینت همیشه effort می‌فرستد، پس
# با این‌ها هر فراخوانی رد می‌شد و کل سیستم بی‌صدا ساکت می‌ماند.
_NO_EFFORT_MODELS = frozenset({"claude-haiku-4-5"})


@dataclass(frozen=True)
class RawCall:
    """یک فراخوانی، پیش از آنکه معنی خروجی تفسیر شود.

    هر مصرف‌کننده شکل خودش را دارد — پاسخ گفتگو، یافته‌های حافظه — ولی همه به همان
    اندازه‌گیری‌ها نیاز دارند. جدا کردن این لایه از فشردن یک شکل داخل شکل دیگر
    جلوگیری می‌کند.
    """

    text: str | None
    model: str
    latency_ms: int
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    error: str | None = None
    # چرا مدل ایستاد (end_turn، max_tokens، refusal، ...). برای تشخیص «پاسخ بریده
    # شد» از «پاسخ بد بود»، که درمان‌شان متفاوت است.
    stop_reason: str | None = None


@dataclass(frozen=True)
class ModelCall:
    answer: ModelAnswer | None
    model: str
    latency_ms: int
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    error: str | None = None

    @classmethod
    def from_raw(
        cls, raw: RawCall, answer: ModelAnswer | None, *, error: str | None = None
    ) -> ModelCall:
        return cls(
            answer=answer,
            model=raw.model,
            latency_ms=raw.latency_ms,
            input_tokens=raw.input_tokens,
            output_tokens=raw.output_tokens,
            cache_read_tokens=raw.cache_read_tokens,
            error=error or raw.error,
        )


class ModelClient(Protocol):
    model: str
    effort: Effort

    async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> RawCall: ...

    async def complete(self, *, system: str, user: str) -> ModelCall: ...


class VisionClient(Protocol):
    """خواندن تصویر. عمداً جدا از `ModelClient` است.

    هر مصرف‌کننده‌ی پاسخ متنی لازم نیست تصویر هم بخواند، و مسیر دریافت هم فقط همین
    یکی را لازم دارد؛ جدا نگه داشتنشان یعنی هیچ‌کدام مجبور به پیاده‌سازی دیگری نیست.
    """

    model: str

    async def describe_image(
        self, *, system: str, prompt: str, image: bytes, media_type: str
    ) -> RawCall: ...


class AnthropicClient:
    """کلاینت واقعی.

    دستور سیستمی به‌عنوان یک بلوک با cache_control فرستاده می‌شود. بخش متغیر یعنی
    منابع و سؤال، در پیام کاربر می‌آید و بعد از پیشوند نهان‌شده قرار می‌گیرد.
    """

    def __init__(
        self,
        *,
        model: str = DEFAULT_MODEL,
        effort: Effort = DEFAULT_EFFORT,
        max_tokens: int = DEFAULT_MAX_TOKENS,
        timeout: float = 45.0,
    ) -> None:
        from anthropic import AsyncAnthropic

        self.model = model
        self.effort = effort
        self._max_tokens = max_tokens
        self._client = AsyncAnthropic(timeout=timeout)

    @classmethod
    def from_settings(cls) -> AnthropicClient:
        """کلاینت با مدل و سقف‌های `.env`.

        مدل ناشناخته یا نامناسب همین‌جا رد می‌شود، هنگام روشن شدن. اگر نمی‌شد،
        غلط تایپی در نام مدل یعنی هر فراخوانی خطا بدهد و سیستم ساکت بماند — دقیقاً
        همان چیزی که از بیرون شبیه «همه‌چیز سالم، فقط جواب نمی‌دهد» دیده می‌شود.
        """
        from mentorai.ai.budget import PRICES
        from mentorai.config import get_settings

        settings = get_settings()
        model = settings.anthropic_model
        if model not in PRICES:
            known = ", ".join(sorted(PRICES))
            raise ValueError(
                f"ANTHROPIC_MODEL={model!r} شناخته‌شده نیست. مدل‌های شناخته‌شده: {known}. "
                "قیمتش هم باید در جدول `budget.PRICES` باشد، وگرنه سقف هزینه واقعی نیست."
            )
        if model in _NO_EFFORT_MODELS:
            raise ValueError(f"{model} پارامتر effort را نمی‌پذیرد و با این کلاینت کار نمی‌کند.")
        return cls(
            model=model,
            effort=settings.anthropic_effort,
            max_tokens=settings.anthropic_max_tokens,
            timeout=settings.anthropic_timeout_seconds,
        )

    async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> RawCall:
        """یک فراخوانی با خروجی ساختاریافته. هرگز استثنا پرتاب نمی‌کند."""
        started = time.monotonic()
        try:
            response = await self._client.messages.create(
                model=self.model,
                max_tokens=self._max_tokens,
                system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
                messages=[{"role": "user", "content": user}],
                output_config={
                    "format": {"type": "json_schema", "schema": JSON_SCHEMA},
                    "effort": self.effort,
                },
            )
        except Exception as exc:  # noqa: BLE001 - هر شکستی به سکوت ختم می‌شود
            return RawCall(
                text=None,
                model=self.model,
                latency_ms=int((time.monotonic() - started) * 1000),
                error=f"{type(exc).__name__}: {exc}",
            )

        return self._finish(response, started)

    def _finish(self, response: Any, started: float) -> RawCall:
        """اندازه‌گیری‌ها و متن پاسخ، مشترک بین همه‌ی فراخوانی‌ها."""
        usage: Any = getattr(response, "usage", None)
        body = next((b.text for b in response.content if b.type == "text"), None)
        stop_reason = getattr(response, "stop_reason", None)

        # پاسخی که نیمه‌کاره بریده شده هرگز موفق حساب نمی‌شود، حتی اگر تصادفاً
        # JSON معتبر باشد. فکر کردن مدل هم از همین سقف کم می‌شود؛ بریده شدن یعنی
        # سقف کم است، نه اینکه مدل «پاسخی نداشته».
        error: str | None = None
        if stop_reason == "max_tokens":
            error = f"پاسخ مدل به سقف {self._max_tokens} توکن خورد و بریده شد"
            body = None
        elif stop_reason == "refusal":
            details: Any = getattr(response, "stop_details", None)
            category = getattr(details, "category", None)
            error = f"مدل پاسخ را رد کرد (دسته: {category or 'نامشخص'})"
            body = None
        elif body is None:
            error = "پاسخ مدل هیچ بلوک متنی نداشت"

        if error is not None:
            log.warning("model_call_failed", model=self.model, stop_reason=stop_reason, error=error)
        return RawCall(
            text=body,
            model=self.model,
            latency_ms=int((time.monotonic() - started) * 1000),
            input_tokens=int(getattr(usage, "input_tokens", 0) or 0),
            output_tokens=int(getattr(usage, "output_tokens", 0) or 0),
            cache_read_tokens=int(getattr(usage, "cache_read_input_tokens", 0) or 0),
            error=error,
            stop_reason=stop_reason,
        )

    async def describe_image(
        self, *, system: str, prompt: str, image: bytes, media_type: str
    ) -> RawCall:
        """تصویر را توصیف کن. مثل بقیه‌ی این ماژول، هرگز استثنا پرتاب نمی‌کند.

        خروجی متن آزاد است نه ساختار: توصیف تصویر شکل ثابتی ندارد، و تحمیل یک طرح
        روی آن فقط مدل را وادار به پر کردن فیلدهایی می‌کند که در تصویر نیستند.
        """
        started = time.monotonic()
        # تصویر پیش از متن می‌آید: مدل باید اول ببیند، بعد بخواند چه خواسته‌ای دارد.
        messages: Any = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": base64.standard_b64encode(image).decode("ascii"),
                        },
                    },
                    {"type": "text", "text": prompt},
                ],
            }
        ]
        try:
            response = await self._client.messages.create(
                model=self.model,
                max_tokens=self._max_tokens,
                system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
                messages=messages,
                output_config={"effort": self.effort},
            )
        except Exception as exc:  # noqa: BLE001 - هر شکستی به سکوت ختم می‌شود
            return RawCall(
                text=None,
                model=self.model,
                latency_ms=int((time.monotonic() - started) * 1000),
                error=f"{type(exc).__name__}: {exc}",
            )
        return self._finish(response, started)

    async def complete(self, *, system: str, user: str) -> ModelCall:
        raw = await self.raw(system=system, user=user, schema=JSON_SCHEMA)
        if raw.text is None:
            return ModelCall.from_raw(raw, None)
        try:
            answer = ModelAnswer.model_validate(json.loads(raw.text))
        except (json.JSONDecodeError, ValidationError) as exc:
            return ModelCall.from_raw(
                raw, None, error=f"خروجی مدل با شکل مورد انتظار نخواند: {exc}"
            )
        return ModelCall.from_raw(raw, answer)


class ScriptedClient:
    """کلاینت آزمایشی. پاسخ از پیش تعیین‌شده می‌دهد و به شبکه دست نمی‌زند."""

    def __init__(
        self,
        answer: ModelAnswer | None = None,
        *,
        error: str | None = None,
        raw_text: str | None = None,
        model: str = "scripted-test-only",
        effort: Effort = "low",
    ) -> None:
        self.model = model
        self.effort = effort
        self._answer = answer
        self._error = error
        self._raw_text = raw_text
        self.calls: list[tuple[str, str]] = []

    async def describe_image(
        self, *, system: str, prompt: str, image: bytes, media_type: str
    ) -> RawCall:
        self.calls.append((system, prompt))
        return RawCall(
            text=self._raw_text,
            model=self.model,
            latency_ms=1,
            input_tokens=10,
            output_tokens=5,
            error=self._error,
        )

    async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> RawCall:
        self.calls.append((system, user))
        return RawCall(
            text=self._raw_text,
            model=self.model,
            latency_ms=1,
            input_tokens=10,
            output_tokens=5,
            error=self._error,
        )

    async def complete(self, *, system: str, user: str) -> ModelCall:
        self.calls.append((system, user))
        return ModelCall(
            answer=self._answer,
            model=self.model,
            latency_ms=1,
            input_tokens=10,
            output_tokens=5,
            error=self._error,
        )
