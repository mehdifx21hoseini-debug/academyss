from __future__ import annotations

from mentorai.knowledge.chunking import MIN_CHUNK, chunk_text


def test_short_text_stays_one_chunk() -> None:
    """یک پرسش و پاسخ معمولی نباید شکسته شود."""
    assert chunk_text("دوره مقدماتی شامل ۱۶ جلسه است.") == ["دوره مقدماتی شامل ۱۶ جلسه است."]


def test_empty_text_produces_nothing() -> None:
    assert chunk_text("   \n  ") == []


def test_long_text_is_split() -> None:
    paragraphs = [
        f"پاراگراف شماره {i} با متن نسبتاً بلند برای آزمایش قطعه‌بندی." * 4 for i in range(6)
    ]
    chunks = chunk_text("\n\n".join(paragraphs), target=400, overlap=50)
    assert len(chunks) > 1


def test_chunks_stay_near_the_target_size() -> None:
    text = "\n\n".join(f"جمله‌ی {i}. " * 30 for i in range(8))
    chunks = chunk_text(text, target=500, overlap=60)
    # هم‌پوشانی باعث می‌شود کمی از هدف رد شود؛ رشد بی‌حد نباید باشد.
    assert max(len(c) for c in chunks) < 500 * 2


def test_no_tiny_trailing_chunk() -> None:
    """قطعه‌ی خیلی کوتاه به‌تنهایی بازیابی نمی‌شود، پس به قبلی می‌چسبد."""
    text = "\n\n".join(["الف" * 300, "ب" * 300, "کوتاه"])
    chunks = chunk_text(text, target=320, overlap=20)
    assert all(len(c) >= MIN_CHUNK for c in chunks)


def test_very_long_paragraph_is_split_on_sentence_boundaries() -> None:
    paragraph = " ".join(f"این جمله‌ی شماره {i} است." for i in range(60))
    chunks = chunk_text(paragraph, target=300, overlap=0)
    assert len(chunks) > 1
    # هیچ قطعه‌ای نباید وسط یک جمله شروع شود که با فاصله آغاز شده باشد.
    assert all(c == c.strip() for c in chunks)


def test_all_content_survives_chunking() -> None:
    text = "\n\n".join(f"بخش {i} با محتوای منحصربه‌فرد {i}." for i in range(10))
    joined = " ".join(chunk_text(text, target=200, overlap=0))
    for i in range(10):
        assert f"محتوای منحصربه‌فرد {i}." in joined
