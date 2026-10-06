"""محافظ قطعی خروجی.

بدترین خطای ممکن این دستیار، گفتن یک قیمت اشتباه به دانشجوست. برخلاف توضیح آموزشی
ناقص — که دانشجو دوباره می‌پرسد — قیمت غلط مستقیم به پول آدم‌ها می‌خورد و قابل جبران
نیست.

قاعده‌ی این فایل: محافظ در **کد** است، نه در دستور مدل. دستور یک درخواست است و
مدل معمولاً رعایتش می‌کند؛ «معمولاً» برای این یکی کافی نیست.
"""

from __future__ import annotations

import pytest

from mentorai.ai.guard import money_amounts, ungrounded_money
from mentorai.knowledge.retrieval import Hit


def _hit(content: str, *, source_class: str = "official", chunk_id: int = 1) -> Hit:
    return Hit(
        chunk_id=chunk_id,
        document_id=chunk_id,
        content=content,
        source_class=source_class,
        authority="fact",
        category="دوره مقدماتی",
        title="سؤال نمونه",
        score=0.9,
        text_rank=1,
    )


# ---------------------------------------------------------------------------
# تشخیص مبلغ
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("قیمت دوره ۵۰۰ هزار تومان است", ["500"]),
        # ارقام لاتین و فارسی یکی حساب می‌شوند، وگرنه محافظ را می‌شد با عوض کردن
        # شکل ارقام دور زد.
        ("قیمت دوره 500 هزار تومان است", ["500"]),
        ("با ۱۰۰ دلار شروع کنید", ["100"]),
        ("۲ میلیون تومان", ["2"]),
        ("۱,۵۰۰,۰۰۰ ریال", ["1500000"]),
        ("هم ۵۰ دلار و هم ۳۰۰ تومان", ["50", "300"]),
        # «درصد» واحد پول نیست: «قانون ۲ درصد» آموزش است، و بیشتر پایگاه دانش از
        # همین جنس است. اگر درصد هم مبلغ حساب می‌شد، محافظ کل لایه‌ی آموزشی را
        # خفه می‌کرد.
        ("قانون ۲ درصد را رعایت کنید", []),
        ("حد ضرر را روی ۲۰ پیپ بگذارید", []),
        ("دوره پانزده جلسه دارد", []),
        ("", []),
    ],
)
def test_money_is_told_apart_from_measurement(text: str, expected: list[str]) -> None:
    assert money_amounts(text) == expected


# ---------------------------------------------------------------------------
# قاعده‌ی اصلی
# ---------------------------------------------------------------------------


def test_an_invented_price_is_blocked() -> None:
    """شکستی که می‌بندد: مدل قیمتی بگوید که در هیچ منبعی نیست."""
    hits = [_hit("دوره مقدماتی پانزده جلسه دارد و شامل متاتریدر است.")]

    assert ungrounded_money("قیمت دوره ۵۰۰ هزار تومان است", hits=hits) == "500"


def test_a_price_repeated_from_an_official_source_passes() -> None:
    hits = [_hit("شهریه دوره مقدماتی ۵۰۰ هزار تومان است.")]

    assert ungrounded_money("قیمت دوره ۵۰۰ هزار تومان است", hits=hits) is None


def test_a_price_from_a_mentor_source_is_not_enough() -> None:
    """منبع `mentor` تجربه‌ی شخصی است، نه اعلام رسمی آکادمی.

    همین تفکیک در بند ۳ دستور مدل هم هست؛ اینجا اجرا می‌شود نه درخواست.
    """
    hits = [_hit("فکر کنم دوره ۵۰۰ هزار تومان بود.", source_class="mentor")]

    assert ungrounded_money("قیمت دوره ۵۰۰ هزار تومان است", hits=hits) == "500"


def test_echoing_the_student_own_number_is_not_inventing_a_price() -> None:
    """اگر دانشجو پرسیده «با ۱۰۰ دلار می‌شه؟»، تکرار همان ۱۰۰ اختراع نیست."""
    hits = [_hit("سرمایه‌ی شروع باید پولی باشد که از دست رفتنش به زندگی آسیب نزند.")]

    assert (
        ungrounded_money(
            "با ۱۰۰ دلار هم می‌توانید شروع کنید",
            hits=hits,
            question="با ۱۰۰ دلار می‌شه شروع کرد؟",
        )
        is None
    )


def test_one_bad_amount_among_good_ones_still_blocks() -> None:
    """کافی است یک عدد ساختگی باشد. پاسخ نیمه‌درست، درست نیست."""
    hits = [_hit("شهریه دوره ۵۰۰ هزار تومان است.")]

    assert ungrounded_money("دوره ۵۰۰ هزار تومان و منتورینگ ۹۹۹ هزار تومان است", hits=hits) == "999"


def test_an_answer_with_no_money_is_untouched() -> None:
    """محافظ نباید لایه‌ی آموزشی را خفه کند."""
    hits = [_hit("پین بار کندلی است با سایه‌ی بلند و بدنه‌ی کوچک.")]

    assert ungrounded_money("پین بار سایه‌ی بلند دارد و بدنه‌اش کوچک است", hits=hits) is None


def test_no_sources_means_any_amount_is_ungrounded() -> None:
    assert ungrounded_money("قیمت ۵۰۰ هزار تومان است", hits=[]) == "500"


def test_a_digit_shape_swap_does_not_slip_past() -> None:
    """منبع با ارقام فارسی، پاسخ با ارقام لاتین: باید بگذرد، چون عدد یکی است.

    و برعکسش هم باید بگیرد. اگر مقایسه روی متن خام بود، هر دو اشتباه می‌شدند.
    """
    hits = [_hit("شهریه ۵۰۰ هزار تومان است.")]
    assert ungrounded_money("قیمت 500 هزار تومان است", hits=hits) is None
    assert ungrounded_money("قیمت 700 هزار تومان است", hits=hits) == "700"
