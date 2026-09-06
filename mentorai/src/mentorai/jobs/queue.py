"""صف کار روی پستگرس.

برداشتن کار در یک دستور اتمی با FOR UPDATE SKIP LOCKED انجام می‌شود: هر کارگر کار قفل‌شده
را رد می‌کند و سراغ بعدی می‌رود، به‌جای اینکه منتظر بماند.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


@dataclass(frozen=True)
class ClaimedJob:
    id: int
    kind: str
    payload: dict[str, Any]
    attempts: int


async def enqueue(
    session: AsyncSession,
    kind: str,
    payload: dict[str, Any],
    *,
    run_after: datetime | None = None,
) -> int:
    row = await session.execute(
        text(
            """
            insert into jobs (kind, payload, run_after)
            values (:kind, :payload, coalesce(:run_after, now()))
            returning id
            """
        ),
        {"kind": kind, "payload": json.dumps(payload, ensure_ascii=False), "run_after": run_after},
    )
    return int(row.scalar_one())


async def claim(
    session: AsyncSession, worker_id: str, *, kinds: list[str] | None = None
) -> ClaimedJob | None:
    """یک کار در انتظار را بردار و به در حال پردازش تغییر بده.

    کل کار در یک دستور انجام می‌شود، پس بین انتخاب و به‌روزرسانی هیچ فاصله‌ای نیست که
    کارگر دیگری در آن همان سطر را بردارد.
    """
    kind_filter = "and kind = any(:kinds)" if kinds else ""
    row = await session.execute(
        text(
            f"""
            update jobs
            set status = 'processing',
                attempts = attempts + 1,
                locked_by = :worker_id,
                locked_at = now()
            where id = (
                select id from jobs
                where status = 'pending' and run_after <= now() {kind_filter}
                order by run_after, id
                limit 1
                for update skip locked
            )
            returning id, kind, payload, attempts
            """
        ),
        {"worker_id": worker_id, "kinds": kinds} if kinds else {"worker_id": worker_id},
    )
    record = row.first()
    if record is None:
        return None
    return ClaimedJob(
        id=record.id, kind=record.kind, payload=json.loads(record.payload), attempts=record.attempts
    )


async def complete(session: AsyncSession, job_id: int) -> None:
    await session.execute(
        text("update jobs set status = 'done', locked_by = null where id = :id"), {"id": job_id}
    )


async def fail(session: AsyncSession, job_id: int, error: str, *, retry_in: timedelta) -> None:
    """شکست را ثبت کن و یا دوباره زمان‌بندی کن یا به صف مرده بفرست.

    کاری که تلاش‌هایش تمام شده «مرده» می‌شود، نه اینکه بی‌صدا ناپدید شود. باید بشود بعداً
    نگاهش کرد.
    """
    await session.execute(
        text(
            """
            update jobs
            set status = case when attempts >= max_attempts then 'dead' else 'pending' end,
                last_error = :error,
                run_after = now() + cast(:retry_in as interval),
                locked_by = null,
                locked_at = null
            where id = :id
            """
        ),
        {"id": job_id, "error": error[:4000], "retry_in": retry_in},
    )


async def release_stale(session: AsyncSession, *, older_than: timedelta) -> int:
    """کارهایی که کارگرشان مرده و قفلشان مانده را آزاد کن."""
    result = await session.execute(
        text(
            """
            update jobs
            set status = 'pending', locked_by = null, locked_at = null
            where status = 'processing'
              and locked_at < now() - cast(:older_than as interval)
            returning id
            """
        ),
        {"older_than": older_than},
    )
    return len(result.fetchall())


def utcnow() -> datetime:
    return datetime.now(UTC)
