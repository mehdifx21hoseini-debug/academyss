"""لایه تصمیم، مرحله‌ی اول: قواعد قطعی.

این قواعد پیش از هر فراخوانی مدل اجرا می‌شوند. ارزان‌اند، سریع‌اند، قابل تست‌اند، و
مهم‌تر از همه قابل پیش‌بینی: برای موضوعی مثل شکایت یا پرداخت، نباید به قضاوت مدل تکیه
کنیم.

فهرست‌ها عمداً داده هستند نه منطق، تا بدون تغییر کد قابل ویرایش باشند.
"""

from __future__ import annotations

import enum
import re

from mentorai.text import normalize_for_search

_SPACES = re.compile(r"\s+")


class EscalationTrigger(enum.StrEnum):
    explicit_human_request = "explicit_human_request"
    money = "money"
    complaint = "complaint"
    account = "account"


# عبارت‌ها به شکل نرمال‌شده نوشته شده‌اند: بدون نیم‌فاصله، با «ی» و «ک» فارسی.
# مقایسه هم روی متن نرمال‌شده انجام می‌شود، پس نگارش‌های مختلف همگی می‌گیرند.
RULES: dict[EscalationTrigger, tuple[str, ...]] = {
    EscalationTrigger.explicit_human_request: (
        "منتور",
        "پشتیبانی",
        "اپراتور",
        "با یه آدم",
        "با آدم",
        "انسان",
        "همکارتون",
        "مسئول",
    ),
    EscalationTrigger.money: (
        "پرداخت",
        "واریز",
        "کارت به کارت",
        "رسید",
        "فاکتور",
        "بازگشت وجه",
        "عودت",
        "پولم",
        "پول من",
        "قیمت",
        "هزینه",
        "شهریه",
        "تخفیف",
        "اقساط",
        "قسط",
    ),
    EscalationTrigger.complaint: (
        "شکایت",
        "ناراضی",
        "اعتراض",
        "کلاهبردار",
        "سر کاری",
        "جواب نمیدید",
        "جواب نمیدن",
    ),
    EscalationTrigger.account: (
        "اکانت",
        "حساب کاربری",
        "لایسنس",
        "دسترسی ندارم",
        "رمز",
        "پسورد",
        "لاگین",
        "وارد نمیشم",
    ),
}


def _joined(value: str) -> str:
    """شکل کاملاً چسبیده، بدون هیچ فاصله‌ای.

    نرمال‌سازی جستجو نیم‌فاصله را حذف می‌کند ولی فاصله‌ی کامل را نگه می‌دارد. پس
    «حساب‌کاربری» به «حسابکاربری» تبدیل می‌شود در حالی که عبارت قاعده «حساب کاربری»
    است و دیگر نمی‌خواند. مقایسه روی شکل چسبیده هر دو را یکی می‌بیند.
    """
    return _SPACES.sub("", value)


def deterministic_trigger(message_text: str) -> EscalationTrigger | None:
    """اگر پیام یکی از موضوعات همیشه-انسانی را لمس کند، همان را برگردان.

    ترتیب بررسی ثابت است تا نتیجه قطعی بماند: یک پیام همیشه همان دلیل را می‌دهد.
    """
    normalized = normalize_for_search(message_text)
    if not normalized:
        return None
    joined = _joined(normalized)
    for trigger in EscalationTrigger:
        for phrase in RULES[trigger]:
            if phrase in normalized or _joined(phrase) in joined:
                return trigger
    return None
