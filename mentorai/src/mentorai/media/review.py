"""تبدیل اعداد استیتمنت به پاسخی که یک منتور می‌نویسد.

قاعده‌ی این ماژول: **عدد از کد، حرف از پایگاه دانش.** هیچ جمله‌ای اینجا از خودِ
سیستم در نمی‌آید؛ هر معیار و هر توصیه‌ای که گفته می‌شود، رکورد تأییدشده‌ی خودش را
در پایگاه دانش دارد و شناسه‌اش کنار همان قاعده نوشته شده.

⚠️ این پاسخ، تصمیم نیست. اعداد را می‌خواند و معنی‌شان را توضیح می‌دهد و مسیر
تأییدشده‌ی آکادمی را یادآوری می‌کند؛ قضاوت درباره‌ی مسیر دانشجو کار منتور است.
"""

from __future__ import annotations

from mentorai.media.statement import StatementMetrics

# معیارهایی که منتور روی استیتمنت نگاه می‌کند — رکورد «منتور استیتمنت را با چه
# معیارهایی بررسی می‌کند؟». این‌ها معیار بررسی عمومی‌اند.
#
# ⚠️ با اعداد طرح سرمایه‌گذاری (`ACA-SUP-0012`: پروفیت فکتور ۱٫۳۵) اشتباه نشوند.
# آن‌ها شرط پذیرش در طرح جذب سرمایه‌اند و فقط وقتی گفته می‌شوند که دانشجو درباره‌ی
# همان طرح پرسیده باشد.
TARGET_PROFIT_FACTOR = 1.5
MAX_DRAWDOWN_PCT = 10.0
IDEAL_DRAWDOWN_RANGE = (5.0, 6.0)

# آستانه‌ای که رکورد «وقتی دراوداون حساب به حدود ۳۰٪ رسید چه باید کرد؟» برایش
# مسیر مشخص دارد. زیر این عدد، آن مسیر گفته نمی‌شود.
STOP_TRADING_DRAWDOWN_PCT = 30.0

GREETING = "سلام عزیز، وقتتون بخیر 🌱"
CLOSING = (
    "این اعداد را خودِ گزارش متاتریدر نوشته و من فقط خواندمشان. برای بررسی دقیق‌تر "
    "مسیر و پلنتان، حتماً با منتورتان در میان بگذارید."
)


def _fa(value: float, digits: int = 2) -> str:
    text = f"{value:,.{digits}f}".replace(",", "٬").replace(".", "٫")
    return text.translate(str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹"))


def _int(value: float) -> str:
    return _fa(value, 0)


def _activity(m: StatementMetrics) -> str | None:
    """چه کاری انجام شده. عدد خام، بدون قضاوت."""
    if not m.trades:
        return None
    line = f"در این بازه {_int(m.trades)} معامله انجام دادید"
    if m.wins or m.losses:
        line += f": {_int(m.wins)} تا سود و {_int(m.losses)} تا زیان"
        if m.win_rate is not None:
            line += f" — یعنی نرخ برد حدود {_int((m.win_rate) * 100)} درصد"
    if m.net_profit:
        outcome = "زیان" if m.net_profit < 0 else "سود"
        line += f". برایند خالص حساب {_fa(abs(m.net_profit))} {outcome} بوده"
    return line + "."


def _profit_factor(m: StatementMetrics) -> str | None:
    """پروفیت فکتور، با توضیح اینکه اصلاً یعنی چه."""
    factor = m.profit_factor
    if factor is None:
        return (
            "پروفیت فکتور در این بازه قابل محاسبه نیست — این عدد نسبت مجموع سود به "
            "مجموع زیان است و وقتی معامله‌ی زیان‌ده وجود نداشته باشد تعریف ندارد. "
            "بازه‌ی طولانی‌تر تصویر روشن‌تری می‌دهد."
        )
    line = (
        f"پروفیت فکتور شما {_fa(factor)} است. این عدد یعنی به‌ازای هر ۱ واحد زیان، "
        f"{_fa(factor)} واحد سود گرفته‌اید"
    )
    if factor < 1:
        line += " — یعنی مجموع زیان‌ها از مجموع سودها بیشتر شده و حساب در این بازه رو به کاهش بوده"
    elif factor < TARGET_PROFIT_FACTOR:
        line += " — یعنی حساب رو به رشد بوده، ولی حاشیه‌اش هنوز باریک است"
    else:
        line += " — یعنی سودها با فاصله‌ی خوبی از زیان‌ها جلو زده‌اند"
    return line + (
        f". عددی که منتور روی استیتمنت دنبالش می‌گردد، بالای {_fa(TARGET_PROFIT_FACTOR, 1)} است."
    )


def _drawdown(m: StatementMetrics) -> str | None:
    """دراوداون، با تعریفش و جایگاهش."""
    percent = m.max_drawdown_pct
    if percent is None:
        if m.max_drawdown_abs is None:
            return None
        return (
            f"بیشترین افت حساب از سقفش {_fa(m.max_drawdown_abs)} بوده، ولی چون سرمایه‌ی "
            "اولیه در گزارش نیامده، درصدش قابل محاسبه نیست."
        )

    line = (
        f"دراوداون حساب {_fa(percent)} درصد است. دراوداون یعنی بیشترین افت سرمایه از "
        "بالاترین نقطه‌ای که حساب رسیده تا پایین‌ترین نقطه‌ی بعدش، و مهم‌ترین معیار "
        "سنجش ریسک یک روش معاملاتی است"
    )
    if IDEAL_DRAWDOWN_RANGE[0] <= percent <= IDEAL_DRAWDOWN_RANGE[1]:
        return line + ". این عدد دقیقاً در همان بازه‌ی مطلوب ۵ تا ۶ درصد است."
    if percent < MAX_DRAWDOWN_PCT:
        return line + (
            f". سقفی که منتور می‌پذیرد {_int(MAX_DRAWDOWN_PCT)} درصد است و شما زیر آن هستید؛ "
            "بازه‌ی مطلوب ۵ تا ۶ درصد است."
        )
    return line + (
        f". چیزی که منتور دنبالش است زیر {_int(MAX_DRAWDOWN_PCT)} درصد و مطلوبش ۵ تا ۶ درصد است."
    )


def _recovery_path(m: StatementMetrics) -> str | None:
    """مسیر تأییدشده‌ی آکادمی برای دراوداون سنگین.

    فقط بالای همان آستانه‌ای گفته می‌شود که رکورد آکادمی برایش نوشته شده.
    """
    percent = m.max_drawdown_pct
    if percent is None or percent < STOP_TRADING_DRAWDOWN_PCT:
        return None
    return (
        f"این عدد از {_int(STOP_TRADING_DRAWDOWN_PCT)} درصد رد شده، و آکادمی برای این "
        "حالت مسیر مشخصی دارد:\n"
        "۱. فعلاً معامله را متوقف کنید.\n"
        "۲. همه‌ی معامله‌ها را مرور کنید و جاهایی را که خارج از پلن عمل شده پیدا کنید.\n"
        "۳. برگردید به بک‌تست، تا تسلط و اعتمادبه‌نفس برگردد.\n"
        "۴. بعد دوباره فوروارد تست را شروع کنید."
    )


def _what_lowers_drawdown(m: StatementMetrics) -> str | None:
    """دو عاملی که رکورد آکادمی برای پایین نگه داشتن دراوداون نام می‌برد."""
    percent = m.max_drawdown_pct
    if percent is None or percent < MAX_DRAWDOWN_PCT:
        return None
    return (
        "دو چیز با هم دراوداون را پایین نگه می‌دارند: ریسک کمتر از ۱٪ در هر معامله، و "
        "وین‌ریتی که واقعاً بالا باشد. دراوداون تک‌رقمی حاصل ترکیب این دو است، نه فقط "
        "کم کردن ریسک."
    )


def render(metrics: StatementMetrics) -> str:
    """پاسخ کامل، همان‌طور که به دانشجو می‌رسد."""
    body = [
        GREETING,
        "استیتمنتتون رو دیدم. بذارید با هم عددها رو مرور کنیم و ببینیم چی می‌گن.",
        _activity(metrics),
        _profit_factor(metrics),
        _drawdown(metrics),
        _recovery_path(metrics),
        _what_lowers_drawdown(metrics),
        CLOSING,
    ]
    return "\n\n".join(part for part in body if part)
