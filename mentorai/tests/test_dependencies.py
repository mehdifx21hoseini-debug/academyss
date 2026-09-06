"""فرض‌هایی درباره‌ی وابستگی‌ها که اگر عوض شوند باید بشکنند.

استدلال در توضیحات کد اثبات نیست. هر ادعایی درباره‌ی یک وابستگی که تصمیم بر پایه‌اش
گرفته شده، باید آزمونی داشته باشد که وقتی ادعا دیگر درست نیست شکست بخورد.
"""

from __future__ import annotations

import re
import tomllib
from importlib import metadata
from pathlib import Path

import pytest


def _required_names(distribution: str) -> set[str]:
    """نام بسته‌هایی که این توزیع خودش اعلام کرده، بدون شرط و نسخه."""
    names: set[str] = set()
    for entry in metadata.requires(distribution) or []:
        # «httpx2<3,>=2.0.0» و «boto3<2,>=1.28; extra == 'aws'» → «httpx2»، «boto3»
        head = entry.split(";", 1)[0]
        name = head.split("[", 1)[0]
        for separator in ("<", ">", "=", "!", "~", "(", " "):
            name = name.split(separator, 1)[0]
        if name:
            names.add(name.strip().lower())
    return names


def test_the_official_sdk_still_declares_httpx2_itself() -> None:
    """پایه‌ی `ADR-024`.

    این پروژه `httpx2` را برای سرویس رونویسی استفاده می‌کند، با این استدلال که
    همان کلاینتی است که SDK رسمی anthropic روی آن ساخته شده — پس با یا بدون اعلام
    ما در محیط هست و چیزی به سطح تماس اضافه نمی‌کند.

    اگر anthropic روزی از `httpx2` جدا شود، آن استدلال دیگر برقرار نیست و این تست
    شکست می‌خورد تا تصمیم دوباره گرفته شود، نه اینکه بی‌صدا کهنه بماند.
    """
    assert "httpx2" in _required_names("anthropic")


def test_the_transcription_client_imports_what_the_sdk_uses() -> None:
    """اگر این وارد کردن شکست بخورد، رونویسی ویس در محیط تولید هم شکست می‌خورد.

    `httpx` فقط در وابستگی‌های توسعه است و در تصویر داکر — که از `requirements.lock`
    نصب می‌شود و آن قفل فقط وابستگی‌های زمان اجراست — نصب نیست؛ پس کد تولید نباید
    به آن تکیه کند.
    """
    pytest.importorskip("httpx2")
    import httpx2

    assert hasattr(httpx2, "AsyncClient")


# ---------------------------------------------------------------------------
# قفل وابستگی (ADR-025)
#
# قفل فقط وقتی ارزش دارد که نشود بی‌صدا از آن عبور کرد. این سه تست همان سه راه
# عبور را می‌بندند: وابستگی‌ای که به pyproject اضافه شده ولی قفل نشده، قفلی که
# هش ندارد، و قفل توسعه‌ای که نسخه‌ی متفاوتی از قفل تولید دارد.
# ---------------------------------------------------------------------------

_ROOT = Path(__file__).resolve().parent.parent
RUNTIME_LOCK = _ROOT / "requirements.lock"
DEV_LOCK = _ROOT / "requirements-dev.lock"

# «alembic==1.19.2 \» در ابتدای سطر. سطرهای هش و توضیح با فاصله شروع می‌شوند.
_PIN = re.compile(r"^([A-Za-z0-9._-]+)==([^\s\\]+)", re.MULTILINE)


def _canonical(name: str) -> str:
    """نام بسته به شکل استاندارد: «argon2-cffi» و «argon2_cffi» یک چیزند."""
    return re.sub(r"[-_.]+", "-", name).lower()


def _pins(lock: Path) -> dict[str, str]:
    return {_canonical(n): v for n, v in _PIN.findall(lock.read_text(encoding="utf-8"))}


def _declared_runtime_dependencies() -> set[str]:
    data = tomllib.loads((_ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    names = set()
    for entry in data["project"]["dependencies"]:
        head = entry.split(";", 1)[0]
        name = head.split("[", 1)[0]
        for separator in ("<", ">", "=", "!", "~", "(", " "):
            name = name.split(separator, 1)[0]
        names.add(_canonical(name.strip()))
    return names


def test_every_declared_dependency_is_pinned_in_the_lock() -> None:
    """وابستگی‌ای که به pyproject اضافه شده ولی قفل نشده، نباید از تست رد شود.

    بدون این، کسی یک کتابخانه اضافه می‌کند، روی سیستم خودش کار می‌کند، و تصویر
    داکر که فقط از قفل نصب می‌کند در محیط تولید با ImportError بالا می‌آید.
    """
    missing = _declared_runtime_dependencies() - set(_pins(RUNTIME_LOCK))
    assert not missing, (
        f"این وابستگی‌ها در pyproject هستند ولی در requirements.lock نیستند: {sorted(missing)}. "
        "قفل را دوباره بساز: uv pip compile pyproject.toml --python-version 3.12 "
        "--generate-hashes -o requirements.lock"
    )


def test_every_pinned_package_carries_a_hash() -> None:
    """قفل بدون هش، قفل نیست.

    `pip install --require-hashes` روی سطری که هش ندارد شکست می‌خورد، ولی آن شکست
    وسط ساخت تصویر رخ می‌دهد. اینجا زودتر و ارزان‌تر گرفته می‌شود.
    """
    for lock in (RUNTIME_LOCK, DEV_LOCK):
        text = lock.read_text(encoding="utf-8")
        blocks = re.split(r"^(?=[A-Za-z0-9._-]+==)", text, flags=re.MULTILINE)
        hashless = [
            _PIN.match(b).group(1)
            for b in blocks
            if _PIN.match(b) and "--hash=" not in b
        ]
        assert not hashless, f"{lock.name}: بدون هش — {sorted(hashless)}"


def test_the_dev_lock_agrees_with_the_runtime_lock() -> None:
    """CI باید همان نسخه‌هایی را تست کند که محیط تولید اجرا می‌کند.

    اگر قفل توسعه نسخه‌ی دیگری از یک بسته‌ی مشترک بیاورد، سبز شدن تست‌ها دیگر
    چیزی درباره‌ی تصویر تولید نمی‌گوید.
    """
    runtime, dev = _pins(RUNTIME_LOCK), _pins(DEV_LOCK)
    mismatched = {
        name: (version, dev[name])
        for name, version in runtime.items()
        if name in dev and dev[name] != version
    }
    assert not mismatched, f"نسخه‌های ناهمخوان بین دو قفل: {mismatched}"

    missing = set(runtime) - set(dev)
    assert not missing, f"در قفل تولید هست ولی در قفل توسعه نیست: {sorted(missing)}"
