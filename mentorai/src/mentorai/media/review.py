"""پاسخ منتور به استیتمنت.

قاعده: **عدد از کد، لحن و ساختار از پایگاه دانش.** هیچ جمله‌ای اینجا سلیقه‌ی سیستم
نیست؛ ساختار پاسخ، واژگان، و هر توصیه‌ای که گفته می‌شود رکورد تأییدشده‌ی خودش را
دارد و کنار همان قاعده نوشته شده.

ساختار از رکورد «ساختار ثابت هر پاسخ منتور» می‌آید و چهار بخش دارد:
۱) سلام و دعای خیر  ۲) تأیید آنچه درست بوده — حتی وقتی نتیجه بد بوده
۳) اصلاح مشخص، یک یا دو نکته و نه فهرست بلند ایراد  ۴) بستن با انرژی.

معیارها از رکورد «منتور استیتمنت را با چه معیارهایی بررسی می‌کند؟» می‌آیند.
⚠️ با اعداد طرح جذب سرمایه (`ACA-SUP-0012`) اشتباه نشوند؛ آن‌ها شرط پذیرش در آن
طرح‌اند، نه معیار بررسی عمومی استیتمنت.
"""

from __future__ import annotations

from datetime import UTC, datetime

from mentorai.config import get_settings
from mentorai.media.statement import StatementMetrics

TARGET_PROFIT_FACTOR = 1.5
MAX_DRAWDOWN_PCT = 10.0
IDEAL_DRAWDOWN_RANGE = (5.0, 6.0)
# آستانه‌ای که رکورد «وقتی دراوداون حساب به حدود ۳۰٪ رسید» برایش مسیر دارد.
STOP_TRADING_DRAWDOWN_PCT = 30.0

# ایموجی‌ها از همان مجموعه‌ی کم و ثابتی‌اند که در پاسخ‌های واقعی منتورها دیده شده.
# سلام و بدرقه **ثابت نیستند**، و این عمدی است.
#
# پیش از این هر استیتمنتی دقیقاً همان یک جمله را می‌گرفت. دانشجویی که دو بار
# استیتمنت می‌فرستد، یا دو دانشجویی که با هم حرف می‌زنند، همان یک جمله‌ی تکراری را
# می‌بینند — و تکرار عینِ یک جمله، امضای یک قالب است نه یک آدم.
#
# همه‌ی عبارت‌ها از پاسخ‌های واقعی منتورها در `raw_sources/mentor_qa/` درآمده‌اند،
# نه از سلیقه‌ی سیستم. «سلام به شما عزیز، روزتون بخیر» پرتکرارترین بود (۱۰ بار) و
# اول فهرست مانده.
_GREETINGS_DAY: tuple[str, ...] = (
    "سلام به شما عزیز، روزتون بخیر 🌱",
    "سلام به شما عزیز، روز بخیر",
    "سلام، روزتون بخیر 🌹",
    "سلام، روزتون بخیر و شادی 🌱",
)
# داده‌ی منتورها روزمحور است، چون در ساعات کاری جواب می‌دهند. شکل شبانه همان ساختار
# را می‌گیرد؛ «روزتون بخیر» ساعت نه شب، خودش یک نشانه است. این سلیقه‌ی نگارشی است
# نه ادعای واقعی، پس بیرون از قاعده‌ی «هیچ چیز اختراع نشود» می‌ماند.
_GREETINGS_EVENING: tuple[str, ...] = (
    "سلام به شما عزیز، شبتون بخیر 🌱",
    "سلام، شبتون بخیر 🌹",
)
# مرز روز و شب. پیش از ۸ و پس از ۲۳ ساعات سکوت است، پس بازه‌ی واقعی ۸ تا ۲۳ است.
EVENING_FROM_HOUR = 17

# عبارت امضایی آکادمی؛ تمرکز بر فرایند به‌جای نتیجه.
_CLOSINGS_HARD: tuple[str, ...] = (
    "تمرکزتون رو روی اجرای درست پلن بذارید، نه سود و ضرر. پرقدرت پیش برید 🌹",
    "تمرکزتون روی اجرای درست پلن باشه، نه نتیجه‌ی یک معامله. پرقدرت ادامه بدید 🌹",
    "نتیجه‌ی یک یا دو معامله مهم نیست، اجرای درست پلن مهمه. پرقدرت در کنارتون هستیم 🌹",
)
_CLOSINGS_GOOD: tuple[str, ...] = (
    "مسیرتون درسته، همینو ادامه بدید. پرقدرت پیش برید 🌹",
    "مسیرتون درسته، همین روند رو حفظ کنید. پرقدرت ادامه بدید 🌹",
    "عالیه، همینو ادامه بدید. پرقدرت مثل همیشه در کنارتون هستیم 🌹",
)

# پرتکرارترین شکل‌ها، برای جایی که یک نمونه‌ی ثابت لازم است.
GREETING = _GREETINGS_DAY[0]
CLOSING_HARD = _CLOSINGS_HARD[0]
CLOSING_GOOD = _CLOSINGS_GOOD[0]


def _pick(pool: tuple[str, ...], seed: int) -> str:
    """انتخاب از فهرست، قطعی برای یک ورودی مشخص.

    عمداً تصادفی نیست. دو دلیل: پاسخ باید تکرارپذیر باشد چون ممکن است یک
    پیش‌نویس دوباره ساخته شود و منتور نباید متن عوض‌شده ببیند؛ و تست تصادفی،
    تست نیست. `seed` شناسه‌ی پیام است، پس دو دانشجو دو عبارت می‌گیرند و یک
    استیتمنت همیشه همان عبارت را.
    """
    return pool[seed % len(pool)]
# منتور پیش از نسخه دادن می‌پرسد.
QUESTION = "یه سؤال هم دارم: استاپ‌هاتون طبق پلن بوده؟ جواب همین، از خود اعداد بیشتر کمک می‌کنه."
HANDOVER = "هر کجا سؤالی بود در خدمتم."


def _fa(value: float, digits: int = 2) -> str:
    text = f"{value:,.{digits}f}".replace(",", "٬").replace(".", "٫")
    return text.translate(str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹"))


def _int(value: float) -> str:
    return _fa(value, 0)


def _healthy(m: StatementMetrics) -> bool:
    factor = m.profit_factor
    drawdown = m.max_drawdown_pct
    return (factor is None or factor >= TARGET_PROFIT_FACTOR) and (
        drawdown is None or drawdown < MAX_DRAWDOWN_PCT
    )


def _opening(m: StatementMetrics) -> str:
    """بخش دوم پاسخ: تأیید آنچه درست بوده.

    رکورد «اول تحسین، بعد اصلاح» می‌گوید این بخش حتی در بدترین نتیجه هم می‌آید. پس
    چیزی که تأیید می‌شود باید واقعی باشد و نه تعارف: فرستادن استیتمنت برای بررسی،
    و کافی بودن داده برای دیدن الگو.
    """
    if not m.trades:
        return "استیتمنتتون رو دیدم، ممنون که فرستادید."
    return (
        f"استیتمنتتون رو دیدم. اینکه خودتون فرستادید برای بررسی قدم درستیه، و "
        f"{_int(m.trades)} معامله داده‌ی کافی هست که تصویر روشن باشه."
    )


def _numbers(m: StatementMetrics) -> str | None:
    """یک خط، فقط آمار خام."""
    if not m.trades or not (m.wins or m.losses):
        return None
    line = f"از {_int(m.trades)} معامله، {_int(m.wins)} تا سود بوده و {_int(m.losses)} تا ضرر"
    if m.net_profit:
        outcome = "ضرر" if m.net_profit < 0 else "سود"
        line += f"، و در مجموع حساب {_fa(abs(m.net_profit))} {outcome} داده"
    return line + "."


def _profit_factor(m: StatementMetrics) -> str | None:
    factor = m.profit_factor
    if factor is None:
        return None
    line = (
        f"پروفیت فکتور {_fa(factor)} ـه؛ یعنی به‌ازای هر ۱ واحد ضرر، {_fa(factor)} واحد سود گرفتید"
    )
    if factor < 1:
        line += ". هر عددی زیر ۱ یعنی ضررها از سودها جلو زدن"
    if factor < TARGET_PROFIT_FACTOR:
        line += f". چیزی که منتور دنبالشه بالای {_fa(TARGET_PROFIT_FACTOR, 1)} ـه"
    else:
        line += f"، و این بالاتر از {_fa(TARGET_PROFIT_FACTOR, 1)} ـه که معیار منتوره"
    return line + "."


def _drawdown(m: StatementMetrics) -> str | None:
    percent = m.max_drawdown_pct
    if percent is None:
        return None
    # یک رقم اعشار: گرد کردن به عدد صحیح، ۵٫۵ را «۶» نشان می‌داد — یعنی درست روی
    # مرز بازه‌ی مطلوب، عدد نمایش‌داده‌شده با نتیجه‌ی سنجش نمی‌خواند.
    shown = _fa(percent, 1)
    line = f"دراوداون {shown} درصده؛ یعنی حساب از بالاترین نقطه‌اش {shown} درصد افت کرده"
    if IDEAL_DRAWDOWN_RANGE[0] <= percent <= IDEAL_DRAWDOWN_RANGE[1]:
        return line + "، دقیقاً همون بازه‌ی مطلوب ۵ تا ۶ درصد."
    if percent < MAX_DRAWDOWN_PCT:
        return line + f"، که زیر سقف {_int(MAX_DRAWDOWN_PCT)} درصدِ آکادمیه."
    return line + f". معیار آکادمی زیر {_int(MAX_DRAWDOWN_PCT)} درصده."


def _recovery_path(m: StatementMetrics) -> str | None:
    """مسیر تأییدشده‌ی آکادمی، فقط بالای همان آستانه‌ای که رکوردش برایش نوشته شده."""
    percent = m.max_drawdown_pct
    if percent is None or percent < STOP_TRADING_DRAWDOWN_PCT:
        return None
    return (
        f"چون از {_int(STOP_TRADING_DRAWDOWN_PCT)} درصد رد شده، مسیر آکادمی برای این حالت "
        "مشخصه: فعلاً معامله رو متوقف کنید، معامله‌ها رو مرور کنید و ببینید کجاها خارج از "
        "پلن عمل شده، برگردید سراغ بک‌تست تا تسلط برگرده، بعد دوباره فوروارد تست رو "
        "شروع کنید."
    )


def render(
    metrics: StatementMetrics, *, seed: int = 0, now: datetime | None = None
) -> str:
    """پاسخ کامل، همان‌طور که به دانشجو می‌رسد.

    `seed` شناسه‌ی پیام است و تعیین می‌کند کدام شکلِ سلام و بدرقه بیاید. `now`
    به وقت آکادمی است و روز را از شب جدا می‌کند.
    """
    moment = (now or datetime.now(UTC)).astimezone(get_settings().tz)
    greetings = (
        _GREETINGS_EVENING if moment.hour >= EVENING_FROM_HOUR else _GREETINGS_DAY
    )
    healthy = _healthy(metrics)
    parts = [
        _pick(greetings, seed),
        _opening(metrics),
        _numbers(metrics),
        _profit_factor(metrics),
        _drawdown(metrics),
        _recovery_path(metrics),
        None if healthy else QUESTION,
        HANDOVER if healthy else None,
        _pick(_CLOSINGS_GOOD if healthy else _CLOSINGS_HARD, seed),
    ]
    return "\n\n".join(part for part in parts if part)
