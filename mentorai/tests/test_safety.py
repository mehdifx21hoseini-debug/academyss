from __future__ import annotations

from datetime import UTC, datetime
from zoneinfo import ZoneInfo

import pytest

from mentorai.telegram.safety import AccountGate, TokenBucket, human_delay_seconds, in_quiet_hours

TEHRAN = ZoneInfo("Asia/Tehran")


def _gate(**kw: object) -> AccountGate:
    defaults = {
        "slug": "mentor-a",
        "bucket": TokenBucket(rate_per_minute=6, burst=2),
        "quiet_start": 23,
        "quiet_end": 8,
        "tz": TEHRAN,
    }
    return AccountGate(**{**defaults, **kw})  # type: ignore[arg-type]


@pytest.mark.parametrize(
    ("hour", "expected"),
    [(23, True), (2, True), (7, True), (8, False), (12, False), (22, False)],
)
def test_quiet_hours_wrap_across_midnight(hour: int, expected: bool) -> None:
    """ساعت‌ها به وقت همان منطقه‌ای خوانده می‌شوند که به تابع داده شده."""
    now = datetime(2026, 9, 2, hour, 0, tzinfo=TEHRAN)
    assert in_quiet_hours(now, start_hour=23, end_hour=8, tz=TEHRAN) is expected


def test_quiet_hours_disabled_when_start_equals_end() -> None:
    now = datetime(2026, 9, 2, 3, 0, tzinfo=TEHRAN)
    assert in_quiet_hours(now, start_hour=0, end_hour=0, tz=TEHRAN) is False


# ---------------------------------------------------------------------------
# ساعت سکوت، ساعتِ دانشجوست نه ساعت سرور
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("utc_hour", "tehran_clock", "expected"),
    [
        # ۰۹:۰۰ تهران = ۰۵:۳۰ UTC. روز است و باید پاسخ برود.
        (5.5, "۰۹:۰۰", False),
        # ۱۱:۰۰ تهران = ۰۷:۳۰ UTC. صبح کاری است و باید پاسخ برود.
        (7.5, "۱۱:۰۰", False),
        # ۰۱:۰۰ تهران = ۲۱:۳۰ UTC روز قبل. نیمه‌شب است و نباید پاسخ برود.
        (21.5, "۰۱:۰۰", True),
        # ۰۳:۰۰ تهران = ۲۳:۳۰ UTC روز قبل. نیمه‌شب است و نباید پاسخ برود.
        (23.5, "۰۳:۰۰", True),
    ],
)
def test_quiet_hours_follow_the_student_clock_not_the_server_clock(
    utc_hour: float, tehran_clock: str, expected: bool
) -> None:
    """شکستی که می‌بندد، روی سرور اروپایی دیده نمی‌شد و در تلگرام دانشجو دیده می‌شد.

    تا پیش از این `in_quiet_hours` منطقه‌ی زمانی را دور می‌ریخت و ساعت UTC را
    می‌سنجید. یعنی سکوتِ «۲۳ تا ۸ تهران» در عمل «۲۳ تا ۸ UTC» بود — که به وقت
    تهران می‌شود ۰۲:۳۰ تا ۱۱:۳۰:

    * تمام صبح تا ۱۱:۳۰ — پرکارترین ساعت دانشجو — سیستم ساکت می‌ماند،
    * و بین ۲۳:۰۰ تا ۰۲:۳۰ تهران پیام می‌فرستاد؛ دقیقاً همان چیزی که ساعت سکوت
      برای جلوگیری از آن هست و در `docs/TELEGRAM_SAFETY.md` بند ۶ الزام شده.

    این تست در CI هم خودش را نشان داده بود: سه تست `test_worker` بین ۲۳:۰۰ و
    ۰۸:۰۰ UTC می‌افتادند و بعدش پاس می‌شدند.
    """
    hour = int(utc_hour)
    minute = int(round((utc_hour - hour) * 60))
    now = datetime(2026, 9, 2, hour, minute, tzinfo=UTC)
    assert (
        in_quiet_hours(now, start_hour=23, end_hour=8, tz=TEHRAN) is expected
    ), f"ساعت {tehran_clock} تهران اشتباه ارزیابی شد"


def test_the_gate_uses_its_own_zone_for_quiet_hours() -> None:
    """همان قاعده، این بار از مسیر واقعی: دروازه‌ای که `sender` صدا می‌زند."""
    # ۱۰:۰۰ تهران = ۰۶:۳۰ UTC — باید اجازه‌ی ارسال بدهد.
    morning = datetime(2026, 9, 2, 6, 30, tzinfo=UTC)
    assert _gate().blocked_reason(morning) is None

    # همان لحظه اگر منطقه UTC حساب شود، ۰۶:۳۰ داخل بازه‌ی سکوت می‌افتد.
    assert _gate(tz=UTC).blocked_reason(morning) == "quiet_hours"


def test_bucket_allows_burst_then_throttles() -> None:
    bucket = TokenBucket(rate_per_minute=6, burst=2)
    assert bucket.seconds_until_allowed() == 0.0
    bucket.consume()
    assert bucket.seconds_until_allowed() == 0.0
    bucket.consume()
    assert bucket.seconds_until_allowed() > 0.0


def test_flood_wait_blocks_the_whole_account() -> None:
    now = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)
    gate = _gate()
    assert gate.blocked_reason(now) is None
    gate.note_flood_wait(30, now=now)
    assert gate.blocked_reason(now) == "flood_wait"


def test_flood_wait_adds_margin_beyond_the_requested_wait() -> None:
    """لبه‌ی دقیق لمس نمی‌شود؛ تلاش در لحظه‌ی انقضا خودش ریسک است."""
    now = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)
    gate = _gate()
    gate.note_flood_wait(30, now=now)
    assert gate.flood_wait_until is not None
    assert (gate.flood_wait_until - now).total_seconds() > 30


def test_kill_switch_outranks_everything() -> None:
    now = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)
    gate = _gate(send_paused=True)
    assert gate.blocked_reason(now) == "send_paused"


def test_human_delay_grows_with_length_but_is_capped() -> None:
    assert human_delay_seconds(10) < human_delay_seconds(200)
    assert human_delay_seconds(100_000) == 12.0
