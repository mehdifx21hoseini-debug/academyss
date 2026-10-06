"""سقف هزینه‌ی مدل.

هر تست اینجا یک شکست واقعی را می‌بندد، نه یک خط کد را پوشش می‌دهد. شکست‌هایی که
پشت این تست‌ها هستند: خرج بی‌سقف، سقفی که با عوض شدن مدل بی‌صدا از کار می‌افتد،
خرجی که اصلاً شمرده نمی‌شود، و مرز روزی که سر ساعت اشتباه صفر می‌شود.
"""

from __future__ import annotations

import csv
from datetime import UTC, datetime
from pathlib import Path

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai import budget
from mentorai.ai.client import DEFAULT_MODEL, ScriptedClient
from mentorai.ai.runtime import SilenceReason, handle_message
from mentorai.ai.schema import ModelAnswer
from mentorai.config import Settings, get_settings
from mentorai.db.models import MentorAccount, Message, ModelUsage, Outcome, Sender
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.ingest import ingest_csv
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound

COLUMNS = [
    "source_class",
    "category",
    "question",
    "answer",
    "authority",
    "valid_until",
    "owner",
    "notes",
]


@pytest.fixture
def embedder() -> HashingEmbedder:
    return HashingEmbedder()


@pytest.fixture
async def knowledge(session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder) -> None:
    path = tmp_path / "kb.csv"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(COLUMNS)
        writer.writerow(
            [
                "official",
                "دوره‌ها",
                "دوره مقدماتی شامل چه چیزهایی است؟",
                "دوره مقدماتی رایگان شامل شانزده جلسه است.",
                "fact",
                "",
                "",
                "",
            ]
        )
    await ingest_csv(session, path, embedder=embedder)
    await session.commit()


async def _incoming(session: AsyncSession, account: MentorAccount, body: str) -> Message:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=500,
        message_id=1,
        sender_user_id=500,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text=body,
        media_type=None,
        reply_to_message_id=None,
        sent_at=datetime(2026, 9, 2, 12, 0, tzinfo=UTC),
        is_private=True,
        is_outgoing=False,
    )
    result = await record_inbound(session, account, inbound, sender=Sender.student)
    await session.commit()
    assert result.message_id is not None
    return await session.get_one(Message, result.message_id)


def _confident() -> ModelAnswer:
    return ModelAnswer(
        answer="دوره مقدماتی شانزده جلسه دارد.",
        confidence=0.95,
        needs_human=False,
        reason="از منبع رسمی",
        used_chunk_ids=[1],
    )


async def _burn(session: AsyncSession, usd: float, *, when: datetime | None = None) -> None:
    """خرجی که انگار قبلاً انجام شده."""
    usage = ModelUsage(
        purpose=budget.Purpose.answer.value,
        model=DEFAULT_MODEL,
        input_tokens=0,
        output_tokens=0,
        cache_read_tokens=0,
        cost_micros=int(usd * budget.MICROS_PER_USD),
    )
    if when is not None:
        usage.occurred_at = when
    session.add(usage)
    await session.commit()


# ---------------------------------------------------------------------------
# قیمت‌گذاری
# ---------------------------------------------------------------------------


def test_the_model_the_code_actually_uses_has_a_price() -> None:
    """اگر مدل پیش‌فرض در جدول قیمت نباشد، هر فراخوانی با نرخ جایگزین حساب می‌شود.

    آن‌وقت سقف هنوز کار می‌کند ولی عددش دیگر واقعی نیست، و هیچ‌کس متوجه نمی‌شود.
    این تست همان لحظه‌ی عوض شدن مدل را می‌گیرد.
    """
    assert DEFAULT_MODEL in budget.PRICES


def test_an_unknown_model_is_priced_at_the_most_expensive_rate() -> None:
    """جهت خطا باید «زودتر ببند» باشد، نه «بی‌صدا از کار بیفت».

    اگر مدلی ناشناخته با قیمت صفر حساب شود، سقف هرگز پر نمی‌شود و کل این ماژول
    بی‌اثر است.
    """
    micros, priced = budget.cost_micros(
        "some-model-released-next-year", input_tokens=1_000_000, output_tokens=0
    )
    assert priced is False
    most_expensive = max(p.input_usd for p in budget.PRICES.values())
    assert micros == round(most_expensive * budget.MICROS_PER_USD)


def test_opus_5_is_priced_from_the_published_rate() -> None:
    """یک میلیون توکن ورودی و یک میلیون توکن خروجی = ۵ + ۲۵ دلار."""
    micros, priced = budget.cost_micros(
        "claude-opus-5", input_tokens=1_000_000, output_tokens=1_000_000
    )
    assert priced is True
    assert micros == 30 * budget.MICROS_PER_USD


def test_cached_tokens_are_billed_not_ignored() -> None:
    """توکن نهان ارزان‌تر است ولی رایگان نیست.

    اگر شمرده نشود، یک پرامپت بزرگ و نهان‌شده می‌تواند پول واقعی خرج کند و در سقف
    اصلاً دیده نشود.
    """
    with_cache, _ = budget.cost_micros(
        "claude-opus-5", input_tokens=0, output_tokens=0, cache_read_tokens=1_000_000
    )
    assert with_cache > 0


# ---------------------------------------------------------------------------
# مرزها
# ---------------------------------------------------------------------------


async def test_the_daily_window_starts_at_midnight_in_tehran(session: AsyncSession) -> None:
    """مرز روز باید به وقت آکادمی باشد، نه UTC.

    اگر مرز UTC می‌بود، سقف روزانه ساعت ۳:۳۰ بامداد به وقت تهران صفر می‌شد — رفتاری
    که نه قابل توضیح است نه قابل پیش‌بینی، و خرج دیشب را روی امروز می‌آورد.
    """
    settings = get_settings()
    # تهران +۳:۳۰ است، پس ۲۰:۳۰ UTC دقیقاً نیمه‌شب تهران است.
    #
    # دو خرج، یکی هر طرف آن مرز:
    #   ۲۰:۰۰ UTC = ۲۳:۳۰ تهران، یعنی هنوز روز ۱۱ شهریور
    #   ۲۰:۴۵ UTC = ۰۰:۱۵ تهران، یعنی از روز ۱۲ شهریور
    await _burn(session, 7.0, when=datetime(2026, 9, 2, 20, 0, tzinfo=UTC))
    await _burn(session, 1.0, when=datetime(2026, 9, 2, 20, 45, tzinfo=UTC))

    # پرسیده‌شده در ۰۰:۳۰ تهران: فقط خرج بعد از نیمه‌شب باید شمرده شود.
    spend = await budget.current_spend(
        session, now=datetime(2026, 9, 2, 21, 0, tzinfo=UTC), settings=settings
    )
    assert spend.day_micros == budget.MICROS_PER_USD, (
        "خرج پیش از نیمه‌شب تهران در سقف امروز شمرده شد؛ یعنی مرز روز UTC است نه تهران"
    )
    # هر دو خرج در همان ماه‌اند.
    assert spend.month_micros == 8 * budget.MICROS_PER_USD


async def test_alerting_warns_but_does_not_block(session: AsyncSession) -> None:
    """آستانه‌ی هشدار نباید سیستم را بخواباند.

    اگر هشدار جلوی فراخوانی را بگیرد، سقف عملاً ۸۰٪ می‌شود و کسی نمی‌فهمد چرا.
    """
    settings = Settings(ai_daily_budget_usd=1.0, ai_monthly_budget_usd=1000.0)  # type: ignore[call-arg]
    await _burn(session, 0.85)

    decision = await budget.evaluate(session, settings=settings)
    assert decision.state is budget.BudgetState.alert
    assert decision.may_call is True


async def test_the_monthly_cap_blocks_even_when_the_day_is_clear(session: AsyncSession) -> None:
    settings = Settings(ai_daily_budget_usd=1000.0, ai_monthly_budget_usd=1.0)  # type: ignore[call-arg]
    await _burn(session, 1.5)

    decision = await budget.evaluate(session, settings=settings)
    assert decision.state is budget.BudgetState.exhausted
    assert decision.limit == "monthly"
    assert decision.may_call is False


# ---------------------------------------------------------------------------
# اعمال روی مسیر واقعی پاسخ
# ---------------------------------------------------------------------------


async def test_an_exhausted_budget_stops_the_model_call_entirely(
    session: AsyncSession,
    account: MentorAccount,
    knowledge: None,
    embedder: HashingEmbedder,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """مهم‌ترین تست این فایل.

    شکستی که می‌بندد: خرج بی‌سقف. اگر سقف پر باشد، مدل **اصلاً صدا زده نمی‌شود** —
    نه اینکه صدا زده شود و پاسخش دور ریخته شود، که همان پول را خرج می‌کرد.
    """
    monkeypatch.setattr(
        budget, "evaluate", _fixed_decision(budget.BudgetState.exhausted, "daily")
    )
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(_confident())

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.silence
    assert result.reason == SilenceReason.budget_exhausted.value
    assert client.calls == [], "سقف پر بود ولی مدل باز هم صدا زده شد"


async def test_a_normal_answer_records_what_it_spent(
    session: AsyncSession,
    account: MentorAccount,
    knowledge: None,
    embedder: HashingEmbedder,
) -> None:
    """بدون این سطر، سقف هیچ‌وقت پر نمی‌شود و خرج نامرئی است."""
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(_confident())

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.answer
    rows = list((await session.execute(select(ModelUsage))).scalars())
    assert len(rows) == 1
    assert rows[0].purpose == budget.Purpose.answer.value
    # مدل آزمایشی در جدول قیمت نیست، پس باید محافظه‌کارانه علامت بخورد.
    assert rows[0].priced is False


async def test_deterministic_escalation_spends_nothing(
    session: AsyncSession,
    account: MentorAccount,
    knowledge: None,
    embedder: HashingEmbedder,
) -> None:
    """قاعده‌ی قطعی پیش از مدل اجرا می‌شود، پس نباید هیچ سطر مصرفی بسازد."""
    message = await _incoming(session, account, "رسید واریزم رو فرستادم چی شد؟")
    client = ScriptedClient(_confident())

    await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    total = (
        await session.execute(select(func.count(ModelUsage.id)))
    ).scalar_one()
    assert total == 0


def _fixed_decision(state: budget.BudgetState, limit: str | None):  # type: ignore[no-untyped-def]
    async def _evaluate(session, *, now=None, settings=None):  # type: ignore[no-untyped-def]
        return budget.Decision(state, budget.Spend(0, 0), limit)

    return _evaluate
