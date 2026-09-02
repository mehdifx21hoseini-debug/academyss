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
