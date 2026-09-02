"""فراخوانی مدل.

قاعده‌ی اصلی این ماژول: **هرگز استثنا پرتاب نمی‌کند.** هر شکستی به ModelCall با فیلد
error برمی‌گردد. دلیلش این است که جهت شکست در این سیستم همیشه به سمت انسان است؛ اگر
خطا بالا برود و جایی گرفته نشود، ممکن است به تلاش دوباره یا پاسخ نیمه‌کاره ختم شود.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, Literal, Protocol

from pydantic import ValidationError

from mentorai.ai.schema import JSON_SCHEMA, ModelAnswer

if TYPE_CHECKING:
    pass

Effort = Literal["low", "medium", "high", "xhigh", "max"]

DEFAULT_MODEL = "claude-opus-5"
# تلاش مدل. برای گفتگوی کوتاه با قوانین صریح، متوسط نقطه‌ی معقولی است؛ عدد نهایی
# باید با اندازه‌گیری روی مجموعه‌ی ارزیابی انتخاب شود، نه با حدس.
DEFAULT_EFFORT: Effort = "medium"
DEFAULT_MAX_TOKENS = 2048


@dataclass(frozen=True)
class ModelCall:
    answer: ModelAnswer | None
    model: str
    latency_ms: int
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    error: str | None = None


class ModelClient(Protocol):
    model: str
    effort: Effort

    async def complete(self, *, system: str, user: str) -> ModelCall: ...


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

    async def complete(self, *, system: str, user: str) -> ModelCall:
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
            return ModelCall(
                answer=None,
                model=self.model,
                latency_ms=int((time.monotonic() - started) * 1000),
                error=f"{type(exc).__name__}: {exc}",
            )

        latency_ms = int((time.monotonic() - started) * 1000)
        usage: Any = getattr(response, "usage", None)
        input_tokens = int(getattr(usage, "input_tokens", 0) or 0)
        output_tokens = int(getattr(usage, "output_tokens", 0) or 0)
        cache_read_tokens = int(getattr(usage, "cache_read_input_tokens", 0) or 0)

        text = next((b.text for b in response.content if b.type == "text"), None)
        if text is None:
            return ModelCall(
                answer=None,
                model=self.model,
                latency_ms=latency_ms,
                error="پاسخ مدل هیچ بلوک متنی نداشت",
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                cache_read_tokens=cache_read_tokens,
            )

        try:
            answer = ModelAnswer.model_validate(json.loads(text))
        except (json.JSONDecodeError, ValidationError) as exc:
            return ModelCall(
                answer=None,
                model=self.model,
                latency_ms=latency_ms,
                error=f"خروجی مدل با شکل مورد انتظار نخواند: {exc}",
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                cache_read_tokens=cache_read_tokens,
            )

        return ModelCall(
            answer=answer,
            model=self.model,
            latency_ms=latency_ms,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cache_read_tokens=cache_read_tokens,
        )


class ScriptedClient:
    """کلاینت آزمایشی. پاسخ از پیش تعیین‌شده می‌دهد و به شبکه دست نمی‌زند."""

    def __init__(
        self,
        answer: ModelAnswer | None = None,
        *,
        error: str | None = None,
        model: str = "scripted-test-only",
        effort: Effort = "low",
    ) -> None:
        self.model = model
        self.effort = effort
        self._answer = answer
        self._error = error
        self.calls: list[tuple[str, str]] = []

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
