"""صف کار روی پستگرس."""

from __future__ import annotations

import asyncio
from datetime import timedelta

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.session import get_sessionmaker
from mentorai.jobs import queue


async def test_enqueue_then_claim_returns_the_payload(session: AsyncSession) -> None:
    await queue.enqueue(session, "answer_message", {"conversation_id": 5})
    await session.commit()

    job = await queue.claim(session, worker_id="w1")
    await session.commit()

    assert job is not None
    assert job.kind == "answer_message"
    assert job.payload == {"conversation_id": 5}
    assert job.attempts == 1


async def test_claim_returns_none_when_queue_is_empty(session: AsyncSession) -> None:
    assert await queue.claim(session, worker_id="w1") is None


async def test_two_workers_never_get_the_same_job() -> None:
    """SKIP LOCKED یعنی کارگر دوم منتظر نمی‌ماند و سراغ کار بعدی می‌رود."""
    maker = get_sessionmaker()
    async with maker() as s:
        for i in range(2):
            await queue.enqueue(s, "answer_message", {"n": i})
        await s.commit()

    async def worker(name: str) -> int | None:
        async with maker() as s:
            job = await queue.claim(s, worker_id=name)
            await s.commit()
            return job.id if job else None

    a, b = await asyncio.gather(worker("w1"), worker("w2"))
    assert a is not None and b is not None
    assert a != b


async def test_failure_reschedules_until_attempts_run_out(session: AsyncSession) -> None:
    job_id = await queue.enqueue(session, "answer_message", {})
    await session.execute(text("update jobs set max_attempts = 2 where id = :id"), {"id": job_id})
    await session.commit()

    claimed = await queue.claim(session, worker_id="w1")
    assert claimed is not None
    await queue.fail(session, claimed.id, "boom", retry_in=timedelta(seconds=0))
    await session.commit()

    status = (
        await session.execute(text("select status from jobs where id = :id"), {"id": job_id})
    ).scalar_one()
    assert status == "pending", "هنوز تلاش باقی مانده"

    claimed = await queue.claim(session, worker_id="w1")
    assert claimed is not None
    await queue.fail(session, claimed.id, "boom", retry_in=timedelta(seconds=0))
    await session.commit()

    status = (
        await session.execute(text("select status from jobs where id = :id"), {"id": job_id})
    ).scalar_one()
    assert status == "dead", "کار تمام‌شده باید مرده شود، نه اینکه بی‌صدا ناپدید شود"


async def test_future_jobs_are_not_claimed_early(session: AsyncSession) -> None:
    await queue.enqueue(
        session, "answer_message", {}, run_after=queue.utcnow() + timedelta(hours=1)
    )
    await session.commit()
    assert await queue.claim(session, worker_id="w1") is None


async def test_stale_locks_are_released(session: AsyncSession) -> None:
    """اگر کارگری بمیرد، کارش نباید برای همیشه قفل بماند."""
    await queue.enqueue(session, "answer_message", {})
    await session.commit()
    claimed = await queue.claim(session, worker_id="dead-worker")
    await session.commit()
    assert claimed is not None

    await session.execute(text("update jobs set locked_at = now() - interval '1 hour'"))
    await session.commit()

    released = await queue.release_stale(session, older_than=timedelta(minutes=10))
    await session.commit()
    assert released == 1
    assert await queue.claim(session, worker_id="w2") is not None


async def test_claim_can_filter_by_kind(session: AsyncSession) -> None:
    await queue.enqueue(session, "other_kind", {})
    await session.commit()
    assert await queue.claim(session, worker_id="w1", kinds=["answer_message"]) is None
