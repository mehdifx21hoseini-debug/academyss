"""قالب‌بندی برای نمایش.

اینجا سه چیز حل می‌شود که هرکدام بدون دیدن صفحه‌ی واقعی پیدا نمی‌شدند:

۱. زمان‌ها در پایگاه داده UTC هستند. منتور در تهران است و «۰۳:۲۸» برایش یعنی
   ساعت اشتباه. تبدیل اینجا انجام می‌شود، نه در پرس‌وجو، تا داده همان UTC بماند.
۲. تاریخ‌ها شمسی نمایش داده می‌شوند و رقم‌ها فارسی. ذخیره‌سازی همچنان میلادی و UTC
   است؛ تقویم یک موضوع نمایشی است و هرگز نباید به پایگاه داده نشت کند، وگرنه هر
   مقایسه و مرتب‌سازی باید از تبدیل بگذرد.
۳. عرض نوار نسبت با کلاس داده می‌شود و نه با ویژگی style، چون سیاست محتوا سبک درون‌خطی
   را مسدود می‌کند و نوار بی‌صدا خالی می‌ماند.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

from mentorai import jalali
from mentorai.config import get_settings

_DIGITS = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")

# عرض نوار در پله‌های پنج درصدی. دقت بیشتر از این روی نوار هشت‌پیکسلی دیده نمی‌شود،
# و پله‌ای بودن یعنی تعداد کلاس‌ها ثابت و محدود می‌ماند.
BAR_STEP = 5


def digits(value: object) -> str:
    """رقم‌های لاتین را فارسی کن."""
    return str(value).translate(_DIGITS)


def local(moment: datetime) -> datetime:
    """به منطقه‌ی زمانی پیکربندی‌شده ببر.

    زمان بدون منطقه UTC فرض می‌شود: هرچه این برنامه می‌نویسد آگاه از منطقه است، و
    فرض دیگری فقط خطا را پنهان می‌کند.
    """
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=UTC)
    return moment.astimezone(get_settings().tz)


def datetime_label(moment: datetime) -> str:
    """تاریخ شمسی و ساعت محلی، مثل ۱۴۰۵/۰۶/۱۱ ۱۰:۳۴."""
    at = local(moment)
    return digits(f"{jalali.format_date(at.date())} {at:%H:%M}")


def date_label(value: date) -> str:
    """تاریخ شمسی با نام ماه.

    برای تاریخ تنها — مثل انقضای سند — نام ماه خواناتر از عدد است و ابهام «ماه یا
    روز؟» را هم ندارد.
    """
    return digits(jalali.format_date_long(value))


def duration_label(delta: timedelta) -> str:
    """مدت انتظار به زبان آدمیزاد.

    «۰ ساعت» چیزی نمی‌گوید؛ آنچه اهمیت دارد این است که چیزی تازه است یا روزهاست مانده.
    """
    hours = int(delta.total_seconds() // 3600)
    if hours < 1:
        return "کمتر از یک ساعت"
    if hours < 24:
        return f"{digits(hours)} ساعت"
    days = hours // 24
    return f"{digits(days)} روز"


def bar_class(ratio: float) -> str:
    """کلاس عرض نوار، گرد شده به نزدیک‌ترین پله."""
    bounded = min(max(ratio, 0.0), 1.0)
    return f"p{round(bounded * 100 / BAR_STEP) * BAR_STEP}"


def percent_label(ratio: float) -> str:
    return f"{digits(round(min(max(ratio, 0.0), 1.0) * 100))}٪"
