"""ذخیره و بازخوانی نتیجه‌ی خواندن فایل.

خودِ فایل ذخیره نمی‌شود؛ فقط چیزی که از آن فهمیده شد. دلیلش در `MessageMedia` آمده.
"""

from __future__ import annotations

import hashlib
from dataclasses import asdict

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import MessageMedia
from mentorai.media.extract import Extraction


def fingerprint(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


async def record(
    session: AsyncSession,
    *,
    message_id: int,
    extraction: Extraction,
    mime: str | None = None,
    size_bytes: int | None = None,
    sha256: str | None = None,
) -> None:
    """نتیجه را ثبت کن، یک‌بار.

    تحویل تکراری تلگرام و اجرای دوباره‌ی یک کار، هر دو ممکن‌اند. قید یکتایی روی
    `message_id` تضمین می‌کند ردیف دوم ساخته نشود؛ اینجا هم به‌جای «بخوان و بعد
    بنویس» — که دو نویسنده هر دو از آن رد می‌شوند — از خود پایگاه داده کمک می‌گیریم.
    """
    metrics = asdict(extraction.metrics) if extraction.metrics is not None else None
    await session.execute(
        insert(MessageMedia)
        .values(
            message_id=message_id,
            kind=extraction.kind,
            mime=mime,
            size_bytes=size_bytes,
            sha256=sha256,
            refusal=extraction.refused.value if extraction.refused is not None else None,
            extracted_text=extraction.text or None,
            metrics=metrics,
        )
        .on_conflict_do_nothing(index_elements=["message_id"])
    )


async def load(session: AsyncSession, message_id: int) -> MessageMedia | None:
    return (
        await session.execute(select(MessageMedia).where(MessageMedia.message_id == message_id))
    ).scalar_one_or_none()
