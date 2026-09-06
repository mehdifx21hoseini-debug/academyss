from __future__ import annotations

import pytest

from mentorai.ai.decision import EscalationTrigger, deterministic_trigger


@pytest.mark.parametrize(
    ("message", "expected"),
    [
        ("میشه با منتور صحبت کنم؟", EscalationTrigger.explicit_human_request),
        ("لطفا وصل کنید به پشتیبانی", EscalationTrigger.explicit_human_request),
        ("پرداختم انجام شد ولی ثبت نشد", EscalationTrigger.money),
        ("رسید واریز رو فرستادم", EscalationTrigger.money),
        ("هزینه دوره چقدره؟", EscalationTrigger.money),
        ("من شکایت دارم از این وضع", EscalationTrigger.complaint),
        ("پولم رو پس بدید", EscalationTrigger.money),
        ("لایسنس من کار نمیکنه", EscalationTrigger.account),
        ("رمزم رو فراموش کردم", EscalationTrigger.account),
    ],
)
def test_sensitive_topics_escalate_without_a_model_call(
    message: str, expected: EscalationTrigger
) -> None:
    assert deterministic_trigger(message) is expected


@pytest.mark.parametrize(
    "message",
    [
        "دوره مقدماتی چند جلسه است؟",
        "پرایس اکشن یعنی چی؟",
        "سلام وقتتون بخیر",
        "کلاس‌ها آنلاینه؟",
    ],
)
def test_ordinary_questions_are_not_escalated_by_rule(message: str) -> None:
    assert deterministic_trigger(message) is None


@pytest.mark.parametrize(
    "message",
    [
        "درباره رمزارز هم آموزش دارید؟",
        "به هدفم رسیدم",
        "این تحلیل به نتیجه رسیده",
    ],
)
def test_words_that_merely_contain_a_rule_phrase_do_not_escalate(message: str) -> None:
    """«رمز» زیررشته‌ی «رمزارز» است و «رسید» زیررشته‌ی «رسیده».

    در یک آکادمی معامله‌گری هر دو واژه‌ی پرکاربردی‌اند؛ تطبیق زیررشته‌ای هر سؤال
    درباره‌ی رمزارز را به مشکل حساب کاربری تبدیل می‌کرد.
    """
    assert deterministic_trigger(message) is None


@pytest.mark.parametrize(
    "message",
    [
        "پرداختم انجام شد",
        "رمزم رو فراموش کردم",
        "پرداختش رو کجا ببینم",
        "حساب کاربری‌ام مشکل داره",
    ],
)
def test_attached_persian_possessive_suffixes_still_match(message: str) -> None:
    """فارسی ضمیر ملکی را می‌چسباند؛ مرز واژه‌ی سخت این‌ها را از دست می‌داد."""
    assert deterministic_trigger(message) is not None


def test_rules_match_across_persian_spelling_variants() -> None:
    """قواعد روی متن نرمال‌شده اجرا می‌شوند، پس نگارش عربی هم می‌گیرد."""
    assert deterministic_trigger("مي خواهم با منتور حرف بزنم") is (
        EscalationTrigger.explicit_human_request
    )


@pytest.mark.parametrize(
    "message",
    [
        "حساب کاربری من مشکل داره",
        "حساب‌کاربری من مشکل داره",
        "حسابکاربری من مشکل داره",
    ],
)
def test_rules_match_whether_the_phrase_is_spaced_joined_or_half_spaced(message: str) -> None:
    """نرمال‌سازی جستجو نیم‌فاصله را حذف می‌کند ولی فاصله‌ی کامل را نگه می‌دارد.

    بدون مقایسه روی شکل چسبیده، عبارت قاعده که با فاصله نوشته شده، شکل نیم‌فاصله‌دار
    را از دست می‌دهد.
    """
    assert deterministic_trigger(message) is EscalationTrigger.account


def test_empty_message_triggers_nothing() -> None:
    assert deterministic_trigger("") is None
    assert deterministic_trigger("   ") is None


def test_result_is_stable_for_the_same_input() -> None:
    """یک پیام همیشه همان دلیل را می‌دهد؛ ترتیب بررسی ثابت است."""
    message = "هزینه دوره چقدره و میشه با منتور حرف بزنم؟"
    assert deterministic_trigger(message) is deterministic_trigger(message)


# ---------------------------------------------------------------------------
# پرسش آموزشی در برابر پرسش مالی (ADR-028)
#
# «قیمت» و «هزینه» تنها در فهرست مالی بودند و ۱۵ پرسش کاملاً آموزشی پایگاه دانش
# را برای همیشه به منتور می‌سپردند. هر مورد زیر یک پرسش واقعی از پایگاه دانش است،
# نه نمونه‌ی ساختگی.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "message",
    [
        "فشردگی قیمت چیه؟",
        "چرا قیمت حرکت می‌کنه؟",
        "قیمت واقعی طلا چقدره؟",
        "چرا قیمت تکون نمی‌خوره؟",
        "چرا قیمت‌ها آپدیت نمی‌شه؟",
        "چرا قیمت از یه سطح می‌ریزه؟",
        "چرا قیمت‌ها بی‌دلیل می‌ریزن؟",
        "قیمت چطور تعیین می‌شه؟",
        "چطور برای یه قیمت هشدار بذارم؟",
        "چرا حد ضررم با قیمت بدتری خورد؟",
        "چرا معامله‌م با قیمت دیگه‌ای باز شد؟",
        "چرا قیمت بروکرها فرق داره؟",
        "هزینه‌ی هر معامله چقدره؟",
    ],
)
def test_trading_questions_that_mention_price_are_not_financial(message: str) -> None:
    """این‌ها کار دستیار است، نه کار منتور.

    شکستی که می‌بندد: پرسشی که سیستم پاسخ درستش را دارد — و در آزمون بازیابی
    «چرا حد ضررم با قیمت بدتری خورد؟» سند درست را در رتبه‌ی اول پیدا می‌کند —
    پیش از آنکه بازیابی اصلاً اجرا شود دور ریخته می‌شد، و کل مکالمه تا پاسخ
    شخصی منتور و گذشتن ۱۲ ساعت سپرده می‌ماند.
    """
    assert deterministic_trigger(message) is None


@pytest.mark.parametrize(
    "message",
    [
        "قیمت دوره چنده؟",
        "قیمت دوره‌ها چنده؟",
        "قیمت کلاس چقدره؟",
        "هزینه دوره چقدره؟",
        # شکل نیم‌فاصله‌دار و شکل جمع. نرمال‌سازی نیم‌فاصله را برمی‌دارد
        # («هزینه‌ی» → «هزینهی») و تطبیق پسوند فارسی این را می‌پذیرد. اینجا آزموده
        # می‌شود چون اگر آن رفتار روزی عوض شود، پرسش کاملاً مالی بی‌صدا از دست
        # می‌رود — و جهت این خطا خطرناک است.
        "هزینه‌ی دوره چقدره؟",
        "هزینه‌ی منتورینگ چقدره؟",
        "مبلغ ثبت نام چقدره؟",
        "قیمت اشتراک چنده؟",
        "هزینه عضویت چقدره؟",
    ],
)
def test_questions_about_what_the_academy_charges_still_escalate(message: str) -> None:
    """جهت خطای خطرناک این است، نه آن یکی.

    پرسش مالی که به منتور نرسد یعنی دانشجویی درباره‌ی پول جواب خودکار می‌گیرد.
    """
    assert deterministic_trigger(message) is EscalationTrigger.money


def test_a_price_word_alone_is_not_enough() -> None:
    assert deterministic_trigger("قیمت چیه؟") is None


def test_an_academy_word_alone_is_not_enough() -> None:
    assert deterministic_trigger("دوره چند جلسه است؟") is None


def test_the_reason_for_a_message_is_stable() -> None:
    """یک پیام همیشه باید همان دلیل را بدهد.

    اگر ترتیب بررسی عوض شود، همان پیام گاهی «مالی» و گاهی چیز دیگری می‌شود و
    آمار ارجاع بی‌معنی می‌شود.
    """
    message = "قیمت دوره چنده؟ میشه با منتور صحبت کنم؟"
    assert {deterministic_trigger(message) for _ in range(20)} == {
        EscalationTrigger.explicit_human_request
    }
