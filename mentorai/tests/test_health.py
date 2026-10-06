"""سلامت سیستم.

دو شکست پشت این تست‌هاست. اول: خرابی‌ای که هیچ‌کس نمی‌بیند — کارگر مرده، صف پر از
کار مرده، تحویل رهاشده. دوم: مسیر سلامتی که برای دیده شدن ساخته شده ولی خودش
اطلاعات لو می‌دهد.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import health
from mentorai.db.models import MentorAccount, Sender
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound
from mentorai.web.app import create_app

NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=create_app())
    async with AsyncClient(transport=transport, base_url="https://panel.test") as c:
        yield c


# ---------------------------------------------------------------------------
# سلامت کارگر
# ---------------------------------------------------------------------------


async def test_no_worker_heartbeat_reads_as_down(session: AsyncSession) -> None:
    """شکستی که می‌بندد: کارگر نصف شب می‌میرد و تا صبح کسی نمی‌فهمد.

    هیچ کارگر زنده‌ای یعنی هیچ پیامی پردازش نمی‌شود — بدترین خرابی ممکن.
    """
    check = await health.workers(session)
    assert check.level is health.Level.down


async def test_a_fresh_heartbeat_reads_as_ok(session: AsyncSession) -> None:
    await health.beat(session, "worker-1", detail={"accounts": ["mentor-a"]})
    await session.commit()

    check = await health.workers(session)
    assert check.level is health.Level.ok


async def test_a_stale_heartbeat_reads_as_down(session: AsyncSession) -> None:
    """امضای کهنه بدتر از نبود امضاست: انگار همه چیز خوب است.

    اگر کهنگی بررسی نشود، کارگری که ساعت‌ها پیش مرده هنوز «زنده» گزارش می‌شود.
    """
    await health.beat(session, "worker-1", detail={})
    await session.commit()

    later = datetime.now(UTC) + health.WORKER_STALE_AFTER + timedelta(seconds=1)
    check = await health.workers(session, now=later)
    assert check.level is health.Level.down


async def test_the_heartbeat_keeps_one_row_per_worker(session: AsyncSession) -> None:
    """تاریخچه‌ی تپش ارزشی ندارد و جدول را بی‌دلیل بزرگ می‌کند."""
    for _ in range(5):
        await health.beat(session, "worker-1", detail={})
    await session.commit()

    rows = (
        await session.execute(text("select count(*) from worker_heartbeats"))
    ).scalar_one()
    assert rows == 1


# ---------------------------------------------------------------------------
# صف‌ها
# ---------------------------------------------------------------------------


async def test_a_dead_job_degrades_the_queue_check(session: AsyncSession) -> None:
    """کار مرده باید دیده شود، نه اینکه بی‌صدا جمع شود."""
    await session.execute(
        text("insert into jobs (kind, payload, status) values ('answer_message', '{}', 'dead')")
    )
    await session.commit()

    check = await health.job_queue(session)
    assert check.level is health.Level.degraded


async def test_an_abandoned_delivery_degrades_the_outbox_check(
    session: AsyncSession, account: MentorAccount
) -> None:
    """تحویل رهاشده یعنی پاسخی که شاید نرفته و هیچ‌کس خبر ندارد."""
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=700,
        message_id=1,
        sender_user_id=700,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text="سؤال",
        media_type=None,
        reply_to_message_id=None,
        sent_at=NOON,
        is_private=True,
        is_outgoing=False,
    )
    stored = await record_inbound(session, account, inbound, sender=Sender.student)
    await session.execute(
        text(
            "insert into deliveries (conversation_id, answered_message_id, body, status) "
            "values (:c, :m, 'پاسخ', 'abandoned')"
        ),
        {"c": stored.conversation_id, "m": stored.message_id},
    )
    await session.commit()

    check = await health.outbox(session)
    assert check.level is health.Level.degraded


# ---------------------------------------------------------------------------
# مسیرهای HTTP
# ---------------------------------------------------------------------------


async def test_liveness_answers_without_touching_the_database(client: AsyncClient) -> None:
    """اگر سلامت به پایگاه داده وابسته باشد، قطعی پایگاه داده کل فرایند را
    «مرده» نشان می‌دهد و ناظر بی‌دلیل راه‌اندازی مجددش می‌کند."""
    response = await client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_readiness_is_unauthenticated_but_says_nothing_useful(
    client: AsyncClient,
) -> None:
    """شکستی که می‌بندد: مسیر سلامتِ باز که ساختار داخلی را لو می‌دهد.

    بدون ورود باید فقط یک کلمه برگردد — نه تعداد، نه نام حساب، نه پیام خطا.
    """
    response = await client.get("/readyz")

    body = response.json()
    assert set(body) == {"status"}, f"مسیر باز جزئیات لو داد: {sorted(body)}"
    assert body["status"] in {"ok", "degraded", "down"}


async def test_detailed_health_requires_a_session(client: AsyncClient) -> None:
    """جزئیات — تعداد ارجاع باز، خرج مدل، نرخ رد پیش‌نویس — پشت ورود است."""
    response = await client.get("/health.json", follow_redirects=False)
    assert response.status_code in (302, 303, 307), "جزئیات سلامت بدون ورود برگشت"


async def test_the_snapshot_carries_no_personal_data(
    session: AsyncSession, account: MentorAccount
) -> None:
    """قاعده‌ی این ماژول: فقط شمارش و زمان.

    اگر روزی کسی متن پیام یا نام دانشجو را به گزارش سلامت اضافه کند، این تست
    شکست می‌خورد — و آن گزارش جایی می‌رود که ناظر بیرونی می‌بیندش.
    """
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=700,
        message_id=1,
        sender_user_id=700,
        username="secret_username",
        first_name="نام محرمانه",
        last_name=None,
        raw_text="متن محرمانه‌ی پیام دانشجو",
        media_type=None,
        reply_to_message_id=None,
        sent_at=NOON,
        is_private=True,
        is_outgoing=False,
    )
    await record_inbound(session, account, inbound, sender=Sender.student)
    await session.commit()

    report = await health.snapshot(session)
    rendered = repr(report)
    for secret in ("متن محرمانه", "نام محرمانه", "secret_username", "700"):
        assert secret not in rendered, f"گزارش سلامت «{secret}» را افشا کرد"
