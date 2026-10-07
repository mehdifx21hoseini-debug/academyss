"""دستورهای راهنمای استقرار باید با فایل compose جور باشند.

این آزمون پس از آن نوشته شد که راهنما برای به‌روزرسانی `docker compose build` ساده را
می‌گفت. سرویس `cli` پروفایل `tools` دارد و آن دستور فقط سرویس‌های بدون پروفایل را
می‌سازد؛ تصویر `cli` قدیمی ماند و `model-check` روی سرور با کد قدیمی اجرا شد (تصویر
آزمایشیِ خراب پس از اصلاحش هم همچنان شکست می‌خورد). هیچ خطایی دیده نمی‌شد، و هیچ آزمونی
راهنما را با compose مقایسه نمی‌کرد.
"""

from __future__ import annotations

import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
COMPOSE = ROOT / "docker-compose.yml"
GUIDE = ROOT.parent / "docs" / "SERVER_SETUP.md"

# `docker compose [گزینه‌ها] build` بدون نام سرویس؛ یعنی «همه‌ی سرویس‌های فعال».
_BUILD_ALL = re.compile(r"^docker compose\b(?P<flags>[^|&;]*?)\bbuild\s*$")


def _build_all_commands() -> list[str]:
    return [
        line.strip()
        for line in GUIDE.read_text(encoding="utf-8").splitlines()
        if _BUILD_ALL.match(line.strip())
    ]


def _profiles_enabled(command: str) -> set[str]:
    return set(re.findall(r"--profile\s+(\S+)", command))


def test_the_guide_has_a_build_all_command() -> None:
    """بدون این، آزمون بعدی بی‌صدا هیچ‌چیز را نمی‌سنجد."""
    assert _build_all_commands(), "راهنما دیگر دستور «ساخت همه» ندارد؛ این آزمون را به‌روز کنید"


def test_every_build_all_command_in_the_guide_builds_the_cli_image() -> None:
    cli = yaml.safe_load(COMPOSE.read_text(encoding="utf-8"))["services"]["cli"]
    cli_profiles = set(cli.get("profiles", []))
    assert cli_profiles, "cli پروفایل ندارد؛ این آزمون و راهنما را دوباره بسنجید"

    for command in _build_all_commands():
        assert _profiles_enabled(command) & cli_profiles, (
            f"«{command}» تصویر cli را نمی‌سازد؛ تصویرش قدیمی می‌ماند. "
            f"بنویسید: docker compose --profile {sorted(cli_profiles)[0]} build"
        )
