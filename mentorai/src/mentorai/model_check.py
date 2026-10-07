"""بررسی زنده‌ی ارائه‌دهنده‌ی هوش مصنوعی، برای روز اول روی سرور (`mentorai model-check`).

چرا لازم است. تمام آزمون‌های این پروژه با کلاینت ساختگی انجام می‌شوند: هیچ‌کدام نمی‌گویند
که نام مدل درست است، کلید کار می‌کند، پارامترها را مدل می‌پذیرد، و خروجی ساختاریافته
واقعاً به شکل مورد انتظار می‌رسد. این فرمان همان چهار مسیری را که سیستم در تولید صدا می‌زند
هر کدام یک بار با یک ورودی ساختگی (نه پیام دانشجو) اجرا می‌کند و نتیجه را نشان می‌دهد.

هزینه‌اش چند سنت است و در سقف هزینه ثبت **نمی‌شود** (به پایگاه داده دست نمی‌زند).
هیچ رازی چاپ نمی‌شود.
"""

from __future__ import annotations

import json
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path

from mentorai.ai import budget
from mentorai.ai.client import ChatAndVision, RawCall
from mentorai.ai.expand import expand
from mentorai.ai.prompt import SYSTEM_PROMPT, build_user_content
from mentorai.ai.schema import PROMPT_VERSION
from mentorai.knowledge.retrieval import Hit
from mentorai.media import vision
from mentorai.memory.extract import EXTRACTION_SCHEMA
from mentorai.memory.extract import SYSTEM_PROMPT as MEMORY_PROMPT
from mentorai.memory.extract import build_user_content as build_memory_content

# سند ساختگی. هیچ‌چیز از پایگاه دانش یا دانشجو در این بررسی به بیرون نمی‌رود.
_DOC = Hit(
    chunk_id=1,
    document_id=1,
    content="دوره مقدماتی شامل شانزده جلسه است.",
    source_class="official",
    authority="fact",
    category="دوره‌ها",
    title="دوره مقدماتی",
)
_QUESTION = "دوره مقدماتی چند جلسه است؟"
_MEMORY_TURNS = [
    ("student", "من سه ماهه ترید می‌کنم و فقط شب‌ها وقت دارم."),
    ("assistant", "ممنون که گفتید."),
]
# یک PNG سفید ۸×۸. تصویر واقعی لازم نیست؛ فقط مسیر ارسال تصویر سنجیده می‌شود. باید
# PNG معتبر باشد (چک‌سام هر بخش درست)؛ آزمون test_providers.py همین را تضمین می‌کند.
_PIXEL = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000080000000808020000004b6d29dc0000000f4944415478da63"
    "f88f03300c2d0900ba1ebf4189e8b6bb0000000049454e44ae426082"
)


@dataclass
class Step:
    name: str
    ok: bool
    detail: str
    micros: int = 0


def _cost(call: RawCall) -> int:
    return budget.cost_micros(
        call.model,
        input_tokens=call.input_tokens,
        output_tokens=call.output_tokens,
        cache_read_tokens=call.cache_read_tokens,
    )[0]


def _facts(call: RawCall) -> str:
    return (
        f"{call.latency_ms} ms، {call.input_tokens} توکن ورودی، {call.output_tokens} خروجی، "
        f"دلیل ایستادن: {call.stop_reason or '-'}"
    )


async def check_answer(client: ChatAndVision) -> Step:
    """مسیر پاسخ به دانشجو، با همان دستور سیستمی و همان قالب ورودی تولید."""
    call = await client.complete(
        system=SYSTEM_PROMPT, user=build_user_content(question=_QUESTION, hits=[_DOC])
    )
    raw = RawCall(
        text="x",
        model=call.model,
        latency_ms=call.latency_ms,
        input_tokens=call.input_tokens,
        output_tokens=call.output_tokens,
        cache_read_tokens=call.cache_read_tokens,
    )
    if call.answer is None:
        return Step("پاسخ به دانشجو", False, call.error or "بی‌پاسخ", _cost(raw))
    a = call.answer
    return Step(
        "پاسخ به دانشجو",
        True,
        f"{_facts(raw)}\n      پاسخ: «{a.answer}»\n      اطمینان {a.confidence}، "
        f"نیاز به انسان: {a.needs_human}",
        _cost(raw),
    )


async def check_memory(client: ChatAndVision) -> Step:
    """شکل خروجی **حافظه**. پیش از رفع باگ `schema`، این مسیر شکل پاسخ را می‌گرفت."""
    call = await client.raw(
        system=MEMORY_PROMPT,
        user=build_memory_content(_MEMORY_TURNS),
        schema=EXTRACTION_SCHEMA,
    )
    if call.text is None:
        return Step("استخراج حافظه", False, call.error or "بی‌پاسخ", _cost(call))
    try:
        keys = set(json.loads(call.text))
    except (json.JSONDecodeError, TypeError):
        return Step("استخراج حافظه", False, "خروجی JSON نبود", _cost(call))
    if keys != {"candidates"}:
        return Step(
            "استخراج حافظه",
            False,
            f"شکل خروجی اشتباه است: کلیدها {sorted(keys)}، انتظار ['candidates']",
            _cost(call),
        )
    return Step("استخراج حافظه", True, _facts(call), _cost(call))


async def check_expansion(client: ChatAndVision) -> Step:
    """بسط دستور کوتاه منتور (`+`)."""
    result = await expand(
        client, instruction="بگو از ویدیو ۱۰ شروع کنه", question="از کجا شروع کنم؟"
    )
    if not result.ok:
        return Step("بسط دستور منتور", False, result.reason or "بی‌پاسخ", _cost(result.call))
    return Step(
        "بسط دستور منتور",
        True,
        f"{_facts(result.call)}\n      متن: «{result.text}»",
        _cost(result.call),
    )


async def check_image(client: ChatAndVision, image: bytes, media_type: str) -> Step:
    """خواندن تصویر. تصویر واقعی دانشجو هرگز اینجا نمی‌آید؛ فایل را خود شما می‌دهید."""
    text, error, call = await vision.describe(client, image=image, media_type=media_type)
    micros = _cost(call) if call is not None else 0
    if text is None or call is None:
        return Step("خواندن تصویر", False, error or "بی‌پاسخ", micros)
    return Step("خواندن تصویر", True, f"{_facts(call)}\n      توصیف: «{text[:200]}»", micros)


async def run_checks(client: ChatAndVision, *, image_path: Path | None = None) -> list[Step]:
    checks: list[Callable[[], Awaitable[Step]]] = [
        lambda: check_answer(client),
        lambda: check_memory(client),
        lambda: check_expansion(client),
    ]
    if image_path is not None:
        data = image_path.read_bytes()
        suffix = image_path.suffix.lower()
        media = {".png": "image/png", ".webp": "image/webp", ".gif": "image/gif"}.get(
            suffix, "image/jpeg"
        )
        checks.append(lambda: check_image(client, data, media))
    else:
        checks.append(lambda: check_image(client, _PIXEL, "image/png"))
    return [await check() for check in checks]


def render(client: ChatAndVision, steps: list[Step]) -> str:
    lines = [
        f"مدل: {client.model} | عمق فکر: {client.effort or 'پیش‌فرض ارائه‌دهنده'} "
        f"| نسخه‌ی دستور: {PROMPT_VERSION}",
        "",
    ]
    for step in steps:
        mark = "✅" if step.ok else "❌"
        lines.append(f"{mark} {step.name}")
        lines.append(f"      {step.detail}")
    total = sum(s.micros for s in steps) / budget.MICROS_PER_USD
    lines += [
        "",
        f"هزینه‌ی این بررسی (تخمین): {total:.4f} دلار. در سقف هزینه‌ی روزانه ثبت نشد.",
        "همه‌چیز سالم است." if all(s.ok for s in steps) else "⚠️ حداقل یک مسیر شکست خورد.",
    ]
    return "\n".join(lines)
