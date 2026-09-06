from __future__ import annotations

from datetime import UTC, datetime

import pytest

from mentorai.telegram.safety import AccountGate, TokenBucket, human_delay_seconds, in_quiet_hours


def _gate(**kw: object) -> AccountGate:
    defaults = {
        "slug": "mentor-a",
        "bucket": TokenBucket(rate_per_minute=6, burst=2),
        "quiet_start": 23,
        "quiet_end": 8,
    }
    return AccountGate(**{**defaults, **kw})  # type: ignore[arg-type]


@pytest.mark.parametrize(
    ("hour", "expected"),
    [(23, True), (2, True), (7, True), (8, False), (12, False), (22, False)],
)
def test_quiet_hours_wrap_across_midnight(hour: int, expected: bool) -> None:
    now = datetime(2026, 9, 2, hour, 0, tzinfo=UTC)
    assert in_quiet_hours(now, start_hour=23, end_hour=8) is expected


def test_quiet_hours_disabled_when_start_equals_end() -> None:
    now = datetime(2026, 9, 2, 3, 0, tzinfo=UTC)
    assert in_quiet_hours(now, start_hour=0, end_hour=0) is False


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
