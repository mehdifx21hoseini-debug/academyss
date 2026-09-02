"""قطعه‌بندی متن.

بازیابی روی قطعه کار می‌کند، نه روی سند. یک متن ده‌صفحه‌ای که همه‌چیز را دارد، برای
هیچ سؤالی نتیجه‌ی دقیق نمی‌دهد.
"""

from __future__ import annotations

import re

# مرز جمله در فارسی: نقطه، علامت سؤال و تعجب فارسی و لاتین.
_SENTENCE_END = re.compile(r"(?<=[.؟?!۔])\s+")
_PARAGRAPH = re.compile(r"\n\s*\n")

DEFAULT_TARGET = 700
DEFAULT_OVERLAP = 120
MIN_CHUNK = 80


def _split_long_paragraph(paragraph: str, target: int) -> list[str]:
    """پاراگراف بلندتر از هدف را روی مرز جمله می‌شکند.

    شکستن وسط جمله معنی را از بین می‌برد و قطعه‌ی بی‌فایده تولید می‌کند.
    """
    sentences = _SENTENCE_END.split(paragraph)
    parts: list[str] = []
    current = ""
    for sentence in sentences:
        candidate = f"{current} {sentence}".strip() if current else sentence
        if len(candidate) > target and current:
            parts.append(current)
            current = sentence
        else:
            current = candidate
    if current:
        parts.append(current)
    return parts


def chunk_text(
    text: str, *, target: int = DEFAULT_TARGET, overlap: int = DEFAULT_OVERLAP
) -> list[str]:
    """متن را به قطعه‌های حدوداً هم‌اندازه با هم‌پوشانی تقسیم کن.

    هم‌پوشانی برای این است که جمله‌ای که درست روی مرز افتاده، در یکی از دو قطعه کامل
    باشد. متن کوتاه اصلاً شکسته نمی‌شود؛ یک پرسش و پاسخ معمولی یک قطعه است.
    """
    text = text.strip()
    if not text:
        return []
    if len(text) <= target:
        return [text]

    units: list[str] = []
    for paragraph in _PARAGRAPH.split(text):
        paragraph = paragraph.strip()
        if not paragraph:
            continue
        if len(paragraph) > target:
            units.extend(_split_long_paragraph(paragraph, target))
        else:
            units.append(paragraph)

    chunks: list[str] = []
    current = ""
    for unit in units:
        candidate = f"{current}\n\n{unit}" if current else unit
        if len(candidate) > target and current:
            chunks.append(current)
            tail = current[-overlap:] if overlap else ""
            current = f"{tail}\n\n{unit}".strip() if tail else unit
        else:
            current = candidate
    if current:
        chunks.append(current)

    # قطعه‌ی خیلی کوتاه در انتها به قبلی چسبانده می‌شود؛ به‌تنهایی بازیابی نمی‌شود.
    if len(chunks) > 1 and len(chunks[-1]) < MIN_CHUNK:
        chunks[-2] = f"{chunks[-2]}\n\n{chunks[-1]}"
        chunks.pop()
    return chunks
