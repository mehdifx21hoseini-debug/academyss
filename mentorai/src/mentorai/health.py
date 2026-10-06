"""سلامت سیستم، در یک نگاه.

تا پیش از این هیچ راهی جز باز کردن دستی پنل وجود نداشت. اگر کارگر نصف شب می‌مرد،
اگر صف پر از کار مرده می‌شد، یا اگر نرخ سکوت از ۱۰٪ به ۹۰٪ می‌رفت، هیچ‌کس تا صبح
نمی‌فهمید.

قاعده‌ی این ماژول: **هیچ داده‌ی شخصی‌ای از اینجا بیرون نمی‌رود.** نه متن پیام، نه
نام، نه شناسه‌ی تلگرامی. فقط شمارش و زمان (`ADR-032`).
"""

from __future__ import annotations

import enum
import json
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai import budget

# کارگری که این‌قدر امضا نگذاشته، مرده حساب می‌شود. حلقه‌ی بی‌کار هر دو ثانیه
# می‌چرخد، پس یک دقیقه فاصله‌ی امنی است.
WORKER_STALE_AFTER = timedelta(minutes=2)


class Level(enum.StrEnum):
    ok = "ok"
    degraded = "degraded"
    down = "down"


@dataclass
class Check:
    name: str
    level: Level
    detail: str = ""


@dataclass
class Health:
    level: Level
    checks: list[Check] = field(default_factory=list)
    facts: dict[str, object] = field(default_factory=dict)

    @property
    def ready(self) -> bool:
        return self.level is not Level.down


async def _scalar(session: AsyncSession, sql: str, **params: object) -> int:
    return int((await session.execute(text(sql), params)).scalar_one())


async def database(session: AsyncSession) -> Check:
    """آیا پایگاه داده پاسخ می‌دهد و طرحش به‌روز است."""
    try:
        await session.execute(text("select 1"))
    except Exception as exc:  # noqa: BLE001 - هر شکستی یعنی پایین است
        return Check("database", Level.down, type(exc).__name__)

    revision = (
        await session.execute(text("select version_num from alembic_version"))
    ).scalar_one_or_none()
    if revision is None:
        return Check("database", Level.down, "هیچ مهاجرتی اجرا نشده")
    return Check("database", Level.ok, f"revision {revision}")


async def workers(session: AsyncSession, *, now: datetime | None = None) -> Check:
    """آیا کارگری زنده است.

    هیچ کارگر زنده‌ای یعنی هیچ پیامی پردازش نمی‌شود — بدترین خرابی ممکن، و همانی
    که تا امروز بی‌صدا رخ می‌داد.
    """
    moment = now or datetime.now(UTC)
    rows = (
        await session.execute(text("select worker_id, updated_at from worker_heartbeats"))
    ).all()
    if not rows:
        return Check("worker", Level.down, "هیچ کارگری امضا نگذاشته")

    fresh = [r for r in rows if moment - r.updated_at <= WORKER_STALE_AFTER]
    if not fresh:
        oldest = min((moment - r.updated_at).total_seconds() for r in rows)
        return Check("worker", Level.down, f"آخرین امضا {int(oldest)} ثانیه پیش")
    return Check("worker", Level.ok, f"{len(fresh)} کارگر زنده")


async def job_queue(session: AsyncSession) -> Check:
    """صف کار: کار مرده باید دیده شود، نه اینکه بی‌صدا جمع شود."""
    dead = await _scalar(session, "select count(*) from jobs where status = 'dead'")
    pending = await _scalar(session, "select count(*) from jobs where status = 'pending'")
    if dead:
        return Check("jobs", Level.degraded, f"{dead} کار مرده، {pending} در انتظار")
    return Check("jobs", Level.ok, f"{pending} در انتظار")


async def outbox(session: AsyncSession) -> Check:
    """صندوق خروج: تحویل رهاشده یعنی پاسخی که شاید نرفته و کسی خبر ندارد."""
    counts = {
        status: await _scalar(
            session, "select count(*) from deliveries where status = :s", s=status
        )
        for status in ("pending", "sending", "failed", "abandoned")
    }
    if counts["abandoned"] or counts["failed"]:
        return Check(
            "deliveries",
            Level.degraded,
            f"{counts['abandoned']} رهاشده، {counts['failed']} ناموفق",
        )
    return Check("deliveries", Level.ok, f"{counts['pending']} در انتظار")


async def escalations(session: AsyncSession) -> Check:
    """ارجاع بازی که روزها مانده، همان چیزی است که آزمایش باید بگیرد."""
    open_count = await _scalar(
        session, "select count(*) from escalations where resolved_at is null"
    )
    oldest_hours = (
        await session.execute(
            text(
                "select extract(epoch from now() - min(created_at)) / 3600 "
                "from escalations where resolved_at is null"
            )
        )
    ).scalar_one()
    if oldest_hours is not None and float(oldest_hours) > 24:
        return Check(
            "escalations", Level.degraded, f"{open_count} باز، قدیمی‌ترین {int(oldest_hours)} ساعت"
        )
    return Check("escalations", Level.ok, f"{open_count} باز")


async def spend(session: AsyncSession) -> Check:
    decision = await budget.evaluate(session)
    detail = f"امروز {decision.spend.day_usd:.2f}$ / این ماه {decision.spend.month_usd:.2f}$"
    if decision.state is budget.BudgetState.exhausted:
        return Check("budget", Level.down, f"سقف پر شده — {detail}")
    if decision.state is budget.BudgetState.alert:
        return Check("budget", Level.degraded, detail)
    return Check("budget", Level.ok, detail)


async def _rates(session: AsyncSession) -> dict[str, object]:
    """اعدادی که آزمایش هفتگی با آن‌ها سنجیده می‌شود."""
    runs = dict(
        (r.outcome, int(r.n))
        for r in (
            await session.execute(
                text("select outcome, count(*) as n from ai_runs group by outcome")
            )
        ).all()
    )
    drafts = dict(
        (r.status, int(r.n))
        for r in (
            await session.execute(
                text("select status, count(*) as n from drafts group by status")
            )
        ).all()
    )
    total_runs = sum(runs.values())
    decided = drafts.get("sent", 0) + drafts.get("edited", 0) + drafts.get("rejected", 0)
    return {
        "ai_runs": total_runs,
        "answer_rate": round(runs.get("answer", 0) / total_runs, 3) if total_runs else None,
        "silence_rate": round(runs.get("silence", 0) / total_runs, 3) if total_runs else None,
        "drafts": drafts,
        "draft_rejection_rate": (
            round(drafts.get("rejected", 0) / decided, 3) if decided else None
        ),
    }


async def snapshot(session: AsyncSession, *, now: datetime | None = None) -> Health:
    """همه‌ی بررسی‌ها. بدترین سطح، سطح کل سیستم است."""
    checks = [
        await database(session),
        await workers(session, now=now),
        await job_queue(session),
        await outbox(session),
        await escalations(session),
        await spend(session),
    ]
    if any(c.level is Level.down for c in checks):
        level = Level.down
    elif any(c.level is Level.degraded for c in checks):
        level = Level.degraded
    else:
        level = Level.ok
    return Health(level=level, checks=checks, facts=await _rates(session))


async def beat(session: AsyncSession, worker_id: str, *, detail: dict[str, object]) -> None:
    """امضای کارگر. یک سطر به‌ازای هر کارگر، نه یک سطر به‌ازای هر تپش."""
    await session.execute(
        text(
            """
            insert into worker_heartbeats (worker_id, updated_at, detail)
            values (:worker_id, now(), cast(:detail as jsonb))
            on conflict (worker_id)
            do update set updated_at = now(), detail = excluded.detail
            """
        ),
        {"worker_id": worker_id, "detail": json.dumps(detail, ensure_ascii=False)},
    )
