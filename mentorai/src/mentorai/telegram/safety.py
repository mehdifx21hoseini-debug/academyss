"""محدودیت‌هایی که حساب‌ها را سالم نگه می‌دارند.

پیاده‌سازی docs/TELEGRAM_SAFETY.md. هر چیزی که اینجاست یک الزام است، نه تنظیم اختیاری.
"""

from __future__ import annotations

import asyncio
import time as _time
from dataclasses import dataclass, field
from datetime import UTC, datetime, time, timedelta


@dataclass
class TokenBucket:
    """سقف ارسال هر حساب.

    سقف را خودمان و بسیار پایین‌تر از حد تلگرام می‌گذاریم. اگر صف طولانی شد، صبر
    می‌کنیم؛ سرعت گرفتن گزینه نیست.
    """

    rate_per_minute: float
    burst: int
    _tokens: float = field(init=False)
    _updated: float = field(init=False)

    def __post_init__(self) -> None:
        self._tokens = float(self.burst)
        self._updated = _time.monotonic()

    def _refill(self) -> None:
        now = _time.monotonic()
        elapsed = now - self._updated
        self._updated = now
        self._tokens = min(float(self.burst), self._tokens + elapsed * self.rate_per_minute / 60.0)

    def seconds_until_allowed(self) -> float:
        self._refill()
        if self._tokens >= 1.0:
            return 0.0
        return (1.0 - self._tokens) * 60.0 / self.rate_per_minute

    def consume(self) -> None:
        self._refill()
        self._tokens -= 1.0

    async def wait(self) -> None:
        while (delay := self.seconds_until_allowed()) > 0:
            await asyncio.sleep(delay)
        self.consume()


def in_quiet_hours(now: datetime, *, start_hour: int, end_hour: int) -> bool:
    """آیا الان در بازه‌ی سکوت است.

    بازه‌ای که از نیمه‌شب رد می‌شود، مثل ۲۳ تا ۸، درست اداره می‌شود.
    """
    current = now.timetz().replace(tzinfo=None)
    start = time(hour=start_hour)
    end = time(hour=end_hour)
    if start == end:
        return False
    if start < end:
        return start <= current < end
    return current >= start or current < end


@dataclass
class AccountGate:
    """آیا این حساب همین حالا اجازه‌ی ارسال دارد."""

    slug: str
    bucket: TokenBucket
    quiet_start: int
    quiet_end: int
    send_paused: bool = False
    flood_wait_until: datetime | None = None

    def blocked_reason(self, now: datetime) -> str | None:
        if self.send_paused:
            return "send_paused"
        if self.flood_wait_until is not None and now < self.flood_wait_until:
            return "flood_wait"
        if in_quiet_hours(now, start_hour=self.quiet_start, end_hour=self.quiet_end):
            return "quiet_hours"
        return None

    def note_flood_wait(self, seconds: int, *, now: datetime | None = None) -> None:
        """عقب‌نشینی برای کل حساب، نه فقط همان گفتگو.

        تلاش مجدد در بازه‌ی انتظار، مدت را تمدید می‌کند و خودش رفتار خودکار ثبت می‌شود.
        یک حاشیه‌ی اضافه گرفته می‌شود تا لبه‌ی دقیق را لمس نکنیم.
        """
        base = now or datetime.now(UTC)
        self.flood_wait_until = base + timedelta(seconds=seconds + 5)


def human_delay_seconds(answer_length: int, *, cap: float = 12.0) -> float:
    """تأخیر متناسب با طول پاسخ، با سقف.

    آدم پاسخ بلندتر را دیرتر می‌فرستد. ولی سقف لازم است، وگرنه پاسخ بلند آن‌قدر دیر
    می‌رسد که تجربه بد می‌شود؛ طبق اولویت‌های محصول، قابلیت اطمینان بر طبیعی بودن مقدم است.
    """
    return min(cap, 1.5 + answer_length / 25.0)
