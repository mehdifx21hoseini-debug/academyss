"""فرض‌هایی درباره‌ی وابستگی‌ها که اگر عوض شوند باید بشکنند.

استدلال در توضیحات کد اثبات نیست. هر ادعایی درباره‌ی یک وابستگی که تصمیم بر پایه‌اش
گرفته شده، باید آزمونی داشته باشد که وقتی ادعا دیگر درست نیست شکست بخورد.
"""

from __future__ import annotations

from importlib import metadata

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

    `httpx` فقط در وابستگی‌های توسعه است و در تصویر داکر — که با `pip install .`
    ساخته می‌شود — نصب نیست؛ پس کد تولید نباید به آن تکیه کند.
    """
    pytest.importorskip("httpx2")
    import httpx2

    assert hasattr(httpx2, "AsyncClient")
