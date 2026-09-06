"""سنجش اعداد یک استیتمنت در برابر معیارهای خود آکادمی.

اعداد از رکورد `ACA-SUP-0012` می‌آیند، که تصمیم مالک آکادمی است (`D-0017`) و بر
عدد ۱٫۳ سند اولیه و عدد ۱٫۵ پاسخ منتورها اولویت دارد. اینجا هیچ آستانه‌ی تازه‌ای
ساخته نمی‌شود؛ هر عددی که در این فایل است باید در پایگاه دانش منبع داشته باشد.

⚠️ این سنجش، نظر نیست. همان رکورد صریح می‌گوید پروفیت فکتور و دراوداون **شرط
بررسی‌اند، نه تضمین پذیرش**، و مربی مبلغ سرمایه یا نتیجه‌ی درخواست را تضمین نمی‌کند.
پس خروجی این ماژول هم به‌عنوان اندازه‌گیری ارائه می‌شود، نه به‌عنوان تصمیم.
"""

from __future__ import annotations

from dataclasses import dataclass

from mentorai.media.statement import StatementMetrics

# آستانه‌های رسمی آکادمی — `ACA-SUP-0012`.
MIN_PROFIT_FACTOR = 1.35
MAX_DRAWDOWN_PCT = 10.0
IDEAL_DRAWDOWN_RANGE = (5.0, 6.0)

SOURCE_NOTE = (
    "معیارها از سند رسمی طرح سرمایه‌گذاری آکادمی است (`ACA-SUP-0012`): "
    "پروفیت فکتور حداقل ۱٫۳۵ و دراوداون زیر ۱۰ درصد، با مقدار مطلوب ۵ تا ۶ درصد."
)
DECISION_NOTE = "این اعداد شرط بررسی‌اند، نه تضمین پذیرش. تصمیم نهایی با تیم آکادمی است."

# از کجا آمدن اعداد صریح گفته می‌شود، و هیچ‌کدام «خطا» نیست: متاتریدر خودش این
# اعداد را حساب و چاپ می‌کند و دانشجو هم همان‌ها را در ترمینالش می‌بیند، پس وقتی
# خلاصه هست همان ملاک است؛ محاسبه‌ی مستقیم برای گزارشی می‌ماند که خلاصه ندارد.
ORIGIN_NOTES = {
    "report_summary": "این اعداد را خودِ گزارش متاتریدر نوشته است.",
    "computed": "این اعداد از روی سطرهای معامله‌ی همین فایل محاسبه شده‌اند.",
}


@dataclass(frozen=True)
class Finding:
    level: str  # "ok" | "warn" | "fail" | "unknown"
    text: str


def _fa(value: float, digits: int = 2) -> str:
    """عدد لاتین را به رقم فارسی با جداکننده‌ی اعشار فارسی برگردان."""
    text = f"{value:,.{digits}f}".replace(",", "٬").replace(".", "٫")
    return text.translate(str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹"))


def review(metrics: StatementMetrics) -> list[Finding]:
    findings: list[Finding] = []

    factor = metrics.profit_factor
    if factor is None:
        findings.append(
            Finding(
                "unknown",
                "پروفیت فکتور محاسبه نشد. اگر هیچ معامله‌ی زیان‌ده در بازه نبوده، این "
                "عدد تعریف ندارد و بازه‌ی طولانی‌تری لازم است.",
            )
        )
    elif factor >= MIN_PROFIT_FACTOR:
        findings.append(
            Finding("ok", f"پروفیت فکتور {_fa(factor)} است و از حداقل ۱٫۳۵ آکادمی بالاتر است.")
        )
    else:
        findings.append(
            Finding(
                "fail",
                f"پروفیت فکتور {_fa(factor)} است و به حداقل ۱٫۳۵ آکادمی نمی‌رسد.",
            )
        )

    drawdown = metrics.max_drawdown_pct
    if drawdown is None:
        detail = (
            f"بیشترین افت از سقف {_fa(metrics.max_drawdown_abs)} واحد بوده، ولی چون سرمایه‌ی "
            "اولیه در گزارش نبود، درصدش قابل محاسبه نیست."
            if metrics.max_drawdown_abs is not None
            else "دراوداون محاسبه نشد."
        )
        findings.append(Finding("unknown", detail))
    elif drawdown >= MAX_DRAWDOWN_PCT:
        findings.append(
            Finding("fail", f"دراوداون {_fa(drawdown)} درصد است و از سقف ۱۰ درصد آکادمی بالاتر.")
        )
    elif IDEAL_DRAWDOWN_RANGE[0] <= drawdown <= IDEAL_DRAWDOWN_RANGE[1]:
        findings.append(
            Finding("ok", f"دراوداون {_fa(drawdown)} درصد است، در همان بازه‌ی مطلوب ۵ تا ۶ درصد.")
        )
    else:
        findings.append(
            Finding("ok", f"دراوداون {_fa(drawdown)} درصد است و زیر سقف ۱۰ درصد آکادمی.")
        )

    if metrics.trades:
        rate = metrics.win_rate
        findings.append(
            Finding(
                "ok" if metrics.net_profit >= 0 else "warn",
                f"{_fa(metrics.trades, 0)} معامله بررسی شد؛ "
                f"{_fa(metrics.wins, 0)} سود و {_fa(metrics.losses, 0)} زیان"
                + (f"، نرخ برد {_fa((rate or 0) * 100, 1)} درصد" if rate is not None else "")
                + f"، برایند خالص {_fa(metrics.net_profit)}.",
            )
        )

    return findings


def render(metrics: StatementMetrics) -> str:
    """گزارش متنی آماده، برای دادن به منتور یا به مدل به‌عنوان زمینه.

    کار مدل نوشتن توضیح با لحن آکادمی است؛ خود اعداد اینجا قطعی شده‌اند و مدل
    نباید دوباره حسابشان کند.
    """
    marks = {"ok": "✅", "warn": "⚠️", "fail": "❌", "unknown": "❔"}
    lines = [f"{marks.get(f.level, '•')} {f.text}" for f in review(metrics)]

    lines.append(ORIGIN_NOTES.get(metrics.source, ""))
    lines.append(DECISION_NOTE)
    return "\n".join(line for line in lines if line)
