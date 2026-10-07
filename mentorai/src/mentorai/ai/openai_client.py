"""کلاینت OpenAI، از راه Responses API (ADR-035).

دو قاعده‌ی این ماژول همان قاعده‌های `client.py` است: **هرگز استثنا پرتاب نمی‌کند** (هر
شکستی به `RawCall.error` برمی‌گردد و سیستم ساکت می‌ماند)، و **بدنه‌ی خطا لاگ نمی‌شود**
(ممکن است بخشی از پیام دانشجو را بازتاب دهد؛ فقط کد و نوع خطا ثبت می‌شود).

چرا Responses، نه Chat Completions: مستندات امروز OpenAI آن را برای هر پروژه‌ی تازه
توصیه می‌کند و شکل تصویر ورودی فقط برای آن مستند است. Chat Completions برای سرویس‌های
«سازگار با OpenAI» (سرور خودی، سرویس‌های دیگر) مفید است؛ اگر روزی لازم شد، فقط
`_payload` و `_interpret` عوض می‌شوند و بقیه‌ی این فایل می‌ماند.

⚠️ **`store` همیشه `false` فرستاده می‌شود.** پیش‌فرض Responses API `true` است و یعنی
پاسخ، و ورودی‌اش، دست‌کم ۳۰ روز روی سرور OpenAI می‌ماند. پیام دانشجو نباید بی‌خبر آنجا
بماند.

بدون SDK رسمی عمداً: `httpx2` از پیش در قفل است (سرویس رونویسی و خود Anthropic)، پس
وابستگی تازه‌ای به تصویر تولید و سطح حمله اضافه نمی‌شود. بهایش این است که تلاش دوباره
و تفسیر پاسخ اینجا نوشته شده‌اند و باید خودشان آزموده شوند (`tests/test_openai_client.py`).
"""

from __future__ import annotations

import asyncio
import base64
import time
from collections.abc import Awaitable, Callable
from typing import Any

import structlog

from mentorai.ai.client import ModelCall, RawCall, answer_from_raw
from mentorai.ai.schema import JSON_SCHEMA

log = structlog.get_logger(__name__)

# همه‌ی مقادیری که مستندات OpenAI برای `reasoning.effort` نام می‌برند. اینکه هر مدل کدام را
# می‌پذیرد با خود API است؛ مقدار نامجاز با `mentorai model-check` روز اول دیده می‌شود.
OPENAI_EFFORTS = ("none", "minimal", "low", "medium", "high", "xhigh", "max")

# تلاش دوباره فقط برای شکست‌هایی که **نتیجه‌شان نامعلوم یا موقتی** است. ۴۰۰ و ۴۰۱ و ۴۰۴
# هرگز تکرار نمی‌شوند: همان خطا را دوباره می‌گیرند و فقط وقت را می‌گیرند.
RETRY_STATUSES = frozenset({408, 409, 429, 500, 502, 503, 504})
MAX_RETRIES = 2
MAX_BACKOFF_SECONDS = 8.0

Sleeper = Callable[[float], Awaitable[None]]


class OpenAIClient:
    """پاسخ متنی و خواندن تصویر با مدل‌های OpenAI."""

    def __init__(
        self,
        *,
        model: str,
        api_key: str,
        base_url: str = "https://api.openai.com/v1",
        effort: str | None = None,
        max_tokens: int = 8000,
        timeout: float = 90.0,
        transport: Any = None,
        sleep: Sleeper = asyncio.sleep,
    ) -> None:
        self.model = model
        self._effort = effort or None
        self._api_key = api_key
        self._url = base_url.rstrip("/") + "/responses"
        self._max_tokens = max_tokens
        self._timeout = timeout
        self._transport = transport
        self._sleep = sleep

    def __repr__(self) -> str:
        # کلید هرگز در نمایش شیء نمی‌آید؛ لاگ و traceback هم از همین استفاده می‌کنند.
        return f"OpenAIClient(model={self.model!r}, url={self._url!r})"

    @property
    def effort(self) -> str | None:
        return self._effort

    @classmethod
    def from_settings(cls) -> OpenAIClient:
        """کلاینت با تنظیمات `.env`؛ هر کمبودی همین‌جا و هنگام روشن شدن رد می‌شود."""
        from mentorai.ai.budget import price_for
        from mentorai.config import get_settings

        settings = get_settings()
        if settings.openai_api_key is None or not settings.openai_api_key.get_secret_value():
            raise ValueError("با AI_PROVIDER=openai، OPENAI_API_KEY لازم است")
        model = settings.ai_model
        if not model:
            raise ValueError(
                "با AI_PROVIDER=openai، AI_MODEL لازم است؛ نام مدل OpenAI در کد حدس زده نمی‌شود"
            )
        if not price_for(model)[1]:
            raise ValueError(
                f"AI_MODEL={model!r} قیمت شناخته‌شده ندارد. AI_PRICE_INPUT_USD و "
                "AI_PRICE_OUTPUT_USD (دلار برای هر میلیون توکن) را از صفحه‌ی قیمت OpenAI "
                "بگذارید؛ بدون قیمت، سقف هزینه واقعی نیست."
            )
        if settings.ai_effort and settings.ai_effort not in OPENAI_EFFORTS:
            raise ValueError(
                f"AI_EFFORT={settings.ai_effort!r} برای openai مجاز نیست. مقادیر مجاز: "
                f"{', '.join(OPENAI_EFFORTS)}"
            )
        return cls(
            model=model,
            api_key=settings.openai_api_key.get_secret_value(),
            base_url=settings.openai_base_url,
            effort=settings.ai_effort or None,
            max_tokens=settings.ai_max_tokens,
            timeout=settings.ai_timeout_seconds,
        )

    # ------------------------------------------------------------------
    # ساخت درخواست
    # ------------------------------------------------------------------

    def _payload(
        self, *, system: str, user_input: Any, schema: dict[str, object] | None
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "model": self.model,
            "instructions": system,
            "input": user_input,
            "max_output_tokens": self._max_tokens,
            # پیش‌فرض سرور `true` است: ۳۰ روز نگهداری. پیام دانشجو نباید آنجا بماند.
            "store": False,
        }
        if schema is not None:
            payload["text"] = {
                "format": {
                    "type": "json_schema",
                    "name": "mentorai_output",
                    "strict": True,
                    "schema": schema,
                }
            }
        if self._effort:
            payload["reasoning"] = {"effort": self._effort}
        return payload

    # ------------------------------------------------------------------
    # شبکه
    # ------------------------------------------------------------------

    async def _post(self, payload: dict[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
        """(بدنه، خطا). دقیقاً یکی از این دو None است."""
        import httpx2

        headers = {"Authorization": f"Bearer {self._api_key}"}
        last_error = "بی‌پاسخ"
        for attempt in range(MAX_RETRIES + 1):
            wait = min(2.0**attempt, MAX_BACKOFF_SECONDS)
            try:
                async with httpx2.AsyncClient(
                    timeout=self._timeout, transport=self._transport
                ) as http:
                    response = await http.post(self._url, headers=headers, json=payload)
            except Exception as exc:  # noqa: BLE001 - هر شکستی به سکوت ختم می‌شود
                # فقط نام خطا؛ متنش ممکن است نشانی کامل یا تکه‌ای از درخواست را داشته باشد.
                last_error = f"خطای اتصال به OpenAI ({type(exc).__name__})"
            else:
                if response.status_code == 200:
                    try:
                        body = response.json()
                    except ValueError:
                        return None, "پاسخ OpenAI JSON نبود"
                    if isinstance(body, dict):
                        return body, None
                    return None, "پاسخ OpenAI شکل مورد انتظار را نداشت"
                last_error = _http_error(response)
                if response.status_code not in RETRY_STATUSES:
                    return None, last_error
                wait = _retry_after(response, default=wait)
            if attempt < MAX_RETRIES:
                await self._sleep(wait)
        return None, last_error

    # ------------------------------------------------------------------
    # تفسیر پاسخ
    # ------------------------------------------------------------------

    def _interpret(self, body: dict[str, Any], started: float) -> RawCall:
        usage = body.get("usage") or {}
        text, error, stop_reason = _read_output(body, self._max_tokens)
        if error is not None:
            log.warning("model_call_failed", model=self.model, stop_reason=stop_reason, error=error)
        return RawCall(
            text=None if error is not None else text,
            model=self.model,
            latency_ms=int((time.monotonic() - started) * 1000),
            # `input_tokens` در OpenAI **شامل** توکن‌های نهان است (برخلاف Anthropic که
            # جدایشان می‌کند). همه با قیمت کامل ورودی حساب می‌شوند: کمی گران‌تر از واقع،
            # یعنی سقف هزینه زودتر می‌بندد، نه دیرتر.
            input_tokens=_count(usage, "input_tokens", "prompt_tokens"),
            # توکن‌های فکر کردن هم داخل `output_tokens` حساب و صورتحساب می‌شوند.
            output_tokens=_count(usage, "output_tokens", "completion_tokens"),
            cache_read_tokens=0,
            error=error,
            stop_reason=stop_reason,
        )

    async def _call(
        self, *, system: str, user_input: Any, schema: dict[str, object] | None
    ) -> RawCall:
        started = time.monotonic()
        body, error = await self._post(
            self._payload(system=system, user_input=user_input, schema=schema)
        )
        if body is None:
            log.warning("model_call_failed", model=self.model, stop_reason=None, error=error)
            return RawCall(
                text=None,
                model=self.model,
                latency_ms=int((time.monotonic() - started) * 1000),
                error=error,
            )
        return self._interpret(body, started)

    # ------------------------------------------------------------------
    # رابط مشترک با بقیه‌ی سیستم (`ChatAndVision`)
    # ------------------------------------------------------------------

    async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> RawCall:
        return await self._call(system=system, user_input=user, schema=schema)

    async def complete(self, *, system: str, user: str) -> ModelCall:
        return answer_from_raw(await self.raw(system=system, user=user, schema=JSON_SCHEMA))

    async def describe_image(
        self, *, system: str, prompt: str, image: bytes, media_type: str
    ) -> RawCall:
        """توصیف تصویر. متن آزاد است، نه ساختار؛ همان دلیل کلاینت Anthropic."""
        data = base64.standard_b64encode(image).decode("ascii")
        user_input = [
            {
                "role": "user",
                "content": [
                    # تصویر پیش از متن می‌آید: مدل باید اول ببیند، بعد بخواند چه خواسته‌ای دارد.
                    {
                        "type": "input_image",
                        "image_url": f"data:{media_type};base64,{data}",
                        "detail": "auto",
                    },
                    {"type": "input_text", "text": prompt},
                ],
            }
        ]
        return await self._call(system=system, user_input=user_input, schema=None)


def _count(usage: Any, *names: str) -> int:
    for name in names:
        value = usage.get(name) if isinstance(usage, dict) else None
        if isinstance(value, int) and not isinstance(value, bool):
            return value
    return 0


def _http_error(response: Any) -> str:
    """کد و نوع خطا، بدون متن آن: متن ممکن است بخشی از پیام دانشجو را بازتاب دهد.

    `param` نگه داشته می‌شود چون بیشتر خطاهای تنظیم (مثل effort نامجاز) را بی‌نیاز از متن
    نشان می‌دهد: `param=reasoning.effort`.
    """
    detail = ""
    try:
        err = response.json().get("error") or {}
        parts = [f"{k}={err[k]}" for k in ("type", "code", "param") if err.get(k)]
        detail = f" ({', '.join(parts)})" if parts else ""
    except (ValueError, AttributeError):
        pass
    return f"OpenAI کد {response.status_code} برگرداند{detail}"


def _retry_after(response: Any, *, default: float) -> float:
    try:
        value = float(response.headers.get("retry-after", ""))
    except (TypeError, ValueError):
        return default
    return max(0.0, min(value, MAX_BACKOFF_SECONDS))


def _read_output(body: dict[str, Any], max_tokens: int) -> tuple[str | None, str | None, str]:
    """(متن، خطا، دلیل ایستادن). نام دلیل‌ها همان نام‌های Anthropic است تا بقیه‌ی سیستم یکسان ببیند."""
    texts: list[str] = []
    refused = False
    for item in body.get("output") or []:
        if not isinstance(item, dict) or item.get("type") != "message":
            continue  # آیتم‌های فکر کردن و غیره متن پاسخ نیستند
        for part in item.get("content") or []:
            if not isinstance(part, dict):
                continue
            if part.get("type") == "output_text" and isinstance(part.get("text"), str):
                texts.append(part["text"])
            elif part.get("type") == "refusal":
                refused = True

    status = body.get("status")
    if body.get("error"):
        return None, "OpenAI در بدنه‌ی پاسخ خطا گزارش کرد", "error"
    if status == "incomplete":
        reason = (body.get("incomplete_details") or {}).get("reason")
        if reason == "max_output_tokens":
            # فکر کردن مدل هم از همین سقف کم می‌شود؛ بریده شدن یعنی سقف کم است.
            return None, f"پاسخ مدل به سقف {max_tokens} توکن خورد و بریده شد", "max_tokens"
        return None, f"پاسخ ناقص ماند ({reason or 'نامشخص'})", "incomplete"
    if refused:
        return None, "مدل پاسخ را رد کرد", "refusal"
    if status not in (None, "completed"):
        return None, f"وضعیت پاسخ OpenAI «{status}» بود", str(status)
    if not texts:
        return None, "پاسخ مدل هیچ بلوک متنی نداشت", "end_turn"
    return "".join(texts), None, "end_turn"
