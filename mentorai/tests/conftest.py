from __future__ import annotations

import os

os.environ.setdefault(
    "DATABASE_URL", "postgresql+asyncpg://mentorai:mentorai@localhost:5432/mentorai_test"
)
os.environ.setdefault("SESSION_ENCRYPTION_KEY", "TfB5m6h0nsGGmZ2Zt2sD1u9wY9NClsMkVQ8mXvJqZ7A=")
os.environ.setdefault("TELEGRAM_API_ID", "12345")
os.environ.setdefault("TELEGRAM_API_HASH", "test-hash")

import pathlib  # noqa: E402
import subprocess  # noqa: E402
import sys  # noqa: E402
from collections.abc import AsyncIterator  # noqa: E402

import pytest  # noqa: E402
from sqlalchemy import text  # noqa: E402
from sqlalchemy.ext.asyncio import AsyncSession  # noqa: E402

from mentorai.db.models import Base, MentorAccount  # noqa: E402
from mentorai.db.session import get_engine, get_sessionmaker  # noqa: E402

_TABLES = [t.name for t in reversed(Base.metadata.sorted_tables)]


@pytest.fixture(scope="session", autouse=True)
async def _schema() -> AsyncIterator[None]:
    """طرح داده از خود مهاجرت‌ها ساخته می‌شود، نه از مدل‌ها.

    منبع حقیقت طرح داده، فایل‌های مهاجرت است. اگر تست روی طرحی اجرا شود که از مدل‌ها
    ساخته شده، هر واگرایی بین این دو تا محیط تولید پنهان می‌ماند. alembic در یک فرایند
    جدا اجرا می‌شود چون env.py خودش asyncio.run صدا می‌زند.
    """
    engine = get_engine()
    async with engine.begin() as conn:
        # همه‌ی جدول‌ها پاک می‌شوند، از جمله جدول نسخه‌ی alembic؛ وگرنه alembic فکر
        # می‌کند مهاجرت قبلاً اجرا شده و هیچ‌چیز نمی‌سازد. شما پاک نمی‌شود چون
        # افزونه‌ها داخل آن نصب‌اند و نقش برنامه اجازه‌ی ساخت دوباره‌شان را ندارد.
        tables = (
            await conn.execute(text("select tablename from pg_tables where schemaname = 'public'"))
        ).scalars()
        for table in list(tables):
            await conn.execute(text(f'drop table if exists "{table}" cascade'))

    root = pathlib.Path(__file__).resolve().parent.parent
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"اجرای مهاجرت‌ها شکست خورد:\n{result.stdout}\n{result.stderr}")

    yield
    await engine.dispose()


@pytest.fixture(autouse=True)
async def _clean() -> AsyncIterator[None]:
    """جدول‌ها بین تست‌ها خالی می‌شوند.

    عمداً از «تراکنشی که برگشت می‌خورد» استفاده نمی‌شود، چون بعضی تست‌ها باید دو نشست
    واقعاً هم‌زمان داشته باشند و آن الگو این را ناممکن می‌کند.
    """
    yield
    async with get_sessionmaker()() as session:
        await session.execute(text(f"truncate {', '.join(_TABLES)} restart identity cascade"))
        await session.commit()


@pytest.fixture
async def session() -> AsyncIterator[AsyncSession]:
    async with get_sessionmaker()() as s:
        yield s


@pytest.fixture
async def account(session: AsyncSession) -> MentorAccount:
    acc = MentorAccount(
        slug="mentor-a",
        mentor_name="منتور الف",
        phone="+989000000001",
        device_model="Desktop",
        system_version="Linux",
        app_version="1.0",
    )
    session.add(acc)
    await session.commit()
    return acc
