"""لایه تصمیم، مرحله‌ی اول: قواعد قطعی.

این قواعد پیش از هر فراخوانی مدل اجرا می‌شوند. ارزان‌اند، سریع‌اند، قابل تست‌اند، و
مهم‌تر از همه قابل پیش‌بینی: برای موضوعی مثل شکایت یا پرداخت، نباید به قضاوت مدل تکیه
کنیم.

فهرست‌ها عمداً داده هستند نه منطق، تا بدون تغییر کد قابل ویرایش باشند.
"""

from __future__ import annotations

import enum

from mentorai.text import normalize_for_search
from mentorai.text.matching import contains_phrase


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
        # «رسید» تنها نمی‌آید: هم رسید پرداخت است هم صرف فعل رسیدن، و «به هدفم رسیدم»
        # نباید ارجاع مالی شود. شکل چندواژه‌ای این ابهام را ندارد.
        "رسید واریز",
        "رسید پرداخت",
        "رسید بانکی",
        "فیش واریز",
        "فیش پرداخت",
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


def deterministic_trigger(message_text: str) -> EscalationTrigger | None:
    """اگر پیام یکی از موضوعات همیشه-انسانی را لمس کند، همان را برگردان.

    تطبیق روی مرز واژه انجام می‌شود، نه زیررشته. «رمز» زیررشته‌ی «رمزارز» است و
    دانشجویی که درباره‌ی رمزارز می‌پرسد نباید به‌عنوان مشکل حساب کاربری ارجاع شود.

    ترتیب بررسی ثابت است تا نتیجه قطعی بماند: یک پیام همیشه همان دلیل را می‌دهد.
    """
    normalized = normalize_for_search(message_text)
    if not normalized:
        return None
    for trigger in EscalationTrigger:
        if any(contains_phrase(normalized, phrase) for phrase in RULES[trigger]):
            return trigger
    return None
