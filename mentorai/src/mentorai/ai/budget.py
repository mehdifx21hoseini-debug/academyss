"""سقف هزینه‌ی مدل.

بدون این، یک حلقه یا یک سیل پیام می‌تواند صورتحساب بی‌سقف بسازد. سیستم عمداً طوری
نوشته شده که وقتی سقف پر شد **ساکت بماند**، نه اینکه پاسخ ارزان‌تر یا بی‌کیفیت‌تر
بدهد: پیام خوانده‌نشده می‌ماند و منتور در تلگرام خودش می‌بیندش، دقیقاً مثل هر سکوت
دیگری (`ADR-009`).

سه انتخاب اینجا عمدی‌اند و هر سه در جهت «کمتر خرج کن» خطا می‌کنند:

۱. مدل ناشناخته با **گران‌ترین** قیمت جدول حساب می‌شود. اگر روزی مدل عوض شود و
   کسی این جدول را به‌روز نکند، سقف زودتر می‌بندد — نه اینکه بی‌صدا از کار بیفتد.
۲. توکن خوانده‌شده از حافظه‌ی نهان با قیمت **کامل ورودی** حساب می‌شود، نه با قیمت
   تخفیف‌خورده‌اش. این هزینه را بیشتر از واقعیت نشان می‌دهد؛ برای یک سقف، همین جهت
   درست است.
۳. بررسی **پیش از** فراخوانی انجام می‌شود، نه بعدش. یعنی آخرین فراخوانی می‌تواند
   کمی از سقف بگذرد، ولی فراخوانی بعدی انجام نمی‌شود.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.config import Settings, get_settings
from mentorai.db.models import ModelUsage

log = structlog.get_logger(__name__)

MICROS_PER_USD = 1_000_000
_TOKENS_PER_UNIT = 1_000_000


@dataclass(frozen=True)
class Price:
    """دلار به‌ازای یک میلیون توکن."""

    input_usd: float
    output_usd: float


# قیمت‌های رسمی Anthropic. هر تغییری در این جدول باید با مستندات رسمی بررسی شود،
# نه از حافظه. `tests/test_budget.py` می‌سنجد که مدل پیش‌فرض کد اینجا قیمت دارد.
PRICES: dict[str, Price] = {
    "claude-opus-5": Price(5.00, 25.00),
    "claude-opus-4-8": Price(5.00, 25.00),
    "claude-opus-4-7": Price(5.00, 25.00),
    "claude-opus-4-6": Price(5.00, 25.00),
    "claude-sonnet-5": Price(2.00, 10.00),
    "claude-sonnet-4-6": Price(3.00, 15.00),
    "claude-haiku-4-5": Price(1.00, 5.00),
    "claude-fable-5": Price(10.00, 50.00),
    "claude-fable-5-1": Price(10.00, 50.00),
}

# گران‌ترین قیمت شناخته‌شده، برای مدلی که در جدول نیست.
_FALLBACK = Price(
    max(p.input_usd for p in PRICES.values()),
    max(p.output_usd for p in PRICES.values()),
)


class Purpose(enum.StrEnum):
    """چرا مدل صدا زده شد. با قید `ck_model_usage_purpose` هم‌خوان است."""

    answer = "answer"
    image_description = "image_description"
    memory_extraction = "memory_extraction"


class BudgetState(enum.StrEnum):
    ok = "ok"
    alert = "alert"
    exhausted = "exhausted"


@dataclass(frozen=True)
class Spend:
    day_micros: int
    month_micros: int

    @property
    def day_usd(self) -> float:
        return self.day_micros / MICROS_PER_USD

    @property
    def month_usd(self) -> float:
        return self.month_micros / MICROS_PER_USD


@dataclass(frozen=True)
class Decision:
    state: BudgetState
    spend: Spend
    # کدام سقف باعث این وضعیت شد. برای پیام لاگ و برای تست.
    limit: str | None = None

    @property
    def may_call(self) -> bool:
        return self.state is not BudgetState.exhausted


def price_for(model: str) -> tuple[Price, bool]:
    """قیمت مدل، و اینکه آیا واقعاً شناخته‌شده بود."""
    price = PRICES.get(model)
    if price is None:
        return _FALLBACK, False
    return price, True


def cost_micros(
    model: str, *, input_tokens: int, output_tokens: int, cache_read_tokens: int = 0
) -> tuple[int, bool]:
    """هزینه به میکرودلار، و اینکه قیمت مدل شناخته‌شده بود یا نه.

    توکن نهان با قیمت ورودی حساب می‌شود؛ دلیلش در توضیح بالای فایل.
    """
    price, priced = price_for(model)
    billed_input = max(0, input_tokens) + max(0, cache_read_tokens)
    total_usd = (
        billed_input * price.input_usd + max(0, output_tokens) * price.output_usd
    ) / _TOKENS_PER_UNIT
    return round(total_usd * MICROS_PER_USD), priced


async def record(
    session: AsyncSession,
    *,
    purpose: Purpose,
    model: str,
    input_tokens: int | None,
    output_tokens: int | None,
    cache_read_tokens: int | None = None,
) -> ModelUsage:
    """یک فراخوانی مدل را ثبت کن.

    `None` در شمارش توکن یعنی ارائه‌دهنده عددی برنگرداند — که خودش با خطا رخ می‌دهد.
    صفر گرفته می‌شود تا ثبت انجام شود؛ نبودن سطر بدتر از سطر با عدد صفر است، چون
    آن‌وقت اصلاً معلوم نیست فراخوانی انجام شده.
    """
    micros, priced = cost_micros(
        model,
        input_tokens=input_tokens or 0,
        output_tokens=output_tokens or 0,
        cache_read_tokens=cache_read_tokens or 0,
    )
    usage = ModelUsage(
        purpose=purpose.value,
        model=model,
        input_tokens=input_tokens or 0,
        output_tokens=output_tokens or 0,
        cache_read_tokens=cache_read_tokens or 0,
        cost_micros=micros,
        priced=priced,
    )
    session.add(usage)
    if not priced:
        log.warning("model_price_unknown", model=model, purpose=purpose.value)
    return usage


def _day_start(now: datetime, settings: Settings) -> datetime:
    """آغاز امروز به وقت آکادمی، برگردانده‌شده به UTC.

    مرز روز عمداً تهران است نه UTC: مالک روزش را به وقت تهران می‌شمارد، و سقفی که
    ساعت سه‌ونیم بامداد صفر شود قابل توضیح نیست.
    """
    local = now.astimezone(settings.tz)
    return local.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(UTC)


def _month_start(now: datetime, settings: Settings) -> datetime:
    local = now.astimezone(settings.tz)
    return local.replace(day=1, hour=0, minute=0, second=0, microsecond=0).astimezone(UTC)


async def spend_since(session: AsyncSession, since: datetime) -> int:
    total = (
        await session.execute(
            select(func.coalesce(func.sum(ModelUsage.cost_micros), 0)).where(
                ModelUsage.occurred_at >= since
            )
        )
    ).scalar_one()
    return int(total)


async def current_spend(
    session: AsyncSession, *, now: datetime | None = None, settings: Settings | None = None
) -> Spend:
    settings = settings or get_settings()
    moment = now or datetime.now(UTC)
    return Spend(
        day_micros=await spend_since(session, _day_start(moment, settings)),
        month_micros=await spend_since(session, _month_start(moment, settings)),
    )


async def evaluate(
    session: AsyncSession, *, now: datetime | None = None, settings: Settings | None = None
) -> Decision:
    """آیا اجازه‌ی فراخوانی مدل هست.

    سقف ماهانه پیش از روزانه بررسی می‌شود: اگر ماه تمام شده، روز هم بی‌معنی است.
    """
    settings = settings or get_settings()
    spend = await current_spend(session, now=now, settings=settings)

    month_cap = settings.ai_monthly_budget_usd * MICROS_PER_USD
    day_cap = settings.ai_daily_budget_usd * MICROS_PER_USD

    if spend.month_micros >= month_cap:
        return Decision(BudgetState.exhausted, spend, "monthly")
    if spend.day_micros >= day_cap:
        return Decision(BudgetState.exhausted, spend, "daily")

    fraction = settings.ai_budget_alert_fraction
    if spend.month_micros >= month_cap * fraction:
        return Decision(BudgetState.alert, spend, "monthly")
    if spend.day_micros >= day_cap * fraction:
        return Decision(BudgetState.alert, spend, "daily")

    return Decision(BudgetState.ok, spend)


async def check(
    session: AsyncSession, *, purpose: Purpose, now: datetime | None = None
) -> Decision:
    """بررسی پیش از فراخوانی، به‌همراه لاگ.

    وضعیت هشدار جلوی فراخوانی را نمی‌گیرد؛ فقط بلند اعلام می‌کند. جلوگیری فقط در
    وضعیت «تمام‌شده» است.
    """
    decision = await evaluate(session, now=now)
    if decision.state is BudgetState.exhausted:
        log.error(
            "ai_budget_exhausted",
            purpose=purpose.value,
            limit=decision.limit,
            day_usd=round(decision.spend.day_usd, 4),
            month_usd=round(decision.spend.month_usd, 4),
        )
    elif decision.state is BudgetState.alert:
        log.warning(
            "ai_budget_alert",
            purpose=purpose.value,
            limit=decision.limit,
            day_usd=round(decision.spend.day_usd, 4),
            month_usd=round(decision.spend.month_usd, 4),
        )
    return decision


def retry_after(now: datetime, settings: Settings | None = None) -> timedelta:
    """چقدر تا باز شدن سقف روزانه مانده. برای زمان‌بندی دوباره‌ی کار."""
    settings = settings or get_settings()
    tomorrow = _day_start(now, settings) + timedelta(days=1)
    return max(timedelta(minutes=1), tomorrow - now)
