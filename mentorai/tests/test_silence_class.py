"""کلاس سکوت در `ai_runs` (RO-1، ADR-042).

RO-1 **رفتار را عوض نمی‌کند**؛ فقط هر اجرای ساکت را برچسب می‌زند و شاخص‌ها را بر اساس
آن برچسب می‌شمارد. چهار چیز را قفل می‌کند:

۱. نگاشت دلیل ← کلاس، که مالک تعیین کرده (جدول در `test_the_mapping_is_the_one_the_owner_set`).
   دلیل ناشناخته `needs_human` است (جهت امن).
۲. سکوت عمدی (`out_of_domain`) ردیف ارجاع نمی‌سازد؛ بقیه‌ی سکوت‌ها می‌سازند.
۳. اجراهای قدیمی (کلاس تهی) **دقیقاً** مثل پیش از این شمرده می‌شوند.
۴. migration فقط می‌افزاید: بدون backfill، قابل برگشت، و داده‌ی قبلی دست‌نخورده.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from tests import test_runtime as _rt
from tests.test_legacy_kpis import ANSWERS, LEGACY_SILENCES, _message, _seed_legacy_runs
from tests.test_runtime import _confident, _incoming, _with_media

from mentorai import escalation, health
from mentorai.access import Principal, Role
from mentorai.ai.client import ScriptedClient
from mentorai.ai.runtime import (
    _SILENCE_CLASS,
    SilenceReason,
    _record,
    handle_message,
    silence_class_of,
)
from mentorai.ai.schema import ModelAnswer
from mentorai.db.models import AiRun, Escalation, MentorAccount, Outcome, SilenceClass
from mentorai.db.session import get_engine
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.web import queries

# فیکسچرهای test_runtime.py (یک KB کوچک و بردارساز آزمایشی). با نسبت دادن، pytest آن‌ها را
# در این ماژول هم می‌بیند؛ import مستقیم نام پارامتر را «تعریف دوباره» حساب می‌کرد.
embedder = _rt.embedder
knowledge = _rt.knowledge

ADMIN = Principal(role=Role.admin, label="test")
ROOT = Path(__file__).resolve().parent.parent

# نگاشتی که مالک قطعی کرد (۱۴۰۵/۰۷/۱۵). `rule_*` از روی رفتار فعلی کد است: همگی
# `HANDOFF_REASONS`‌اند، یعنی گفتگو برای منتور ارجاع می‌شود.
OWNER_MAPPING: dict[str, SilenceClass] = {
    "no_sources": SilenceClass.needs_human,
    "unsupported_media": SilenceClass.needs_human,
    "empty_answer": SilenceClass.system_fault,
    "ungrounded_money": SilenceClass.needs_human,
    "model_flagged": SilenceClass.needs_human,
    "low_confidence": SilenceClass.needs_human,
    "model_error": SilenceClass.system_fault,
    "budget_exhausted": SilenceClass.system_fault,
    "out_of_domain": SilenceClass.intentional,
    "rule_identity_question": SilenceClass.needs_human,
    "rule_explicit_human_request": SilenceClass.needs_human,
    "rule_money": SilenceClass.needs_human,
    "rule_complaint": SilenceClass.needs_human,
    "rule_account": SilenceClass.needs_human,
}


# ---------------------------------------------------------------------------
# ۱. نگاشت
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(("reason", "expected"), sorted(OWNER_MAPPING.items()))
def test_the_mapping_is_the_one_the_owner_set(reason: str, expected: SilenceClass) -> None:
    assert silence_class_of(reason) is expected


def test_every_known_reason_is_mapped_explicitly() -> None:
    """دلیل تازه‌ای که به `SilenceReason` اضافه شود، نباید بی‌صدا به پیش‌فرض بیفتد.

    هم جدول مالک و هم جدول خود کد (`_SILENCE_CLASS`) باید دقیقاً همه‌ی دلیل‌ها را بپوشانند؛
    وگرنه دلیلی که کلاسش همان پیش‌فرض (`needs_human`) است، در نبودش دیده نمی‌شد.
    """
    known = {r.value for r in SilenceReason}
    assert known == set(OWNER_MAPPING)
    assert known == set(_SILENCE_CLASS)


@pytest.mark.parametrize("reason", ["", "something_new", "rule_money_v2", "OUT_OF_DOMAIN"])
def test_an_unknown_reason_is_needs_human(reason: str) -> None:
    """سکوتی که نمی‌شناسیم نباید «عمدی» حساب شود و از ارجاع‌ها بیرون برود."""
    assert silence_class_of(reason) is SilenceClass.needs_human


def test_every_handoff_reason_is_needs_human() -> None:
    """رفتار فعلی کد: ارجاع به منتور یعنی `needs_human`."""
    for reason in escalation.HANDOFF_REASONS:
        assert silence_class_of(reason) is SilenceClass.needs_human, reason


def test_only_out_of_domain_is_intentional() -> None:
    intentional = {
        r for r in SilenceReason if silence_class_of(r.value) is SilenceClass.intentional
    }
    assert intentional == {SilenceReason.out_of_domain}


def test_the_class_has_exactly_three_values_and_no_partial() -> None:
    """پاسخ جزئی یک پاسخ است، نه سکوت."""
    assert {c.value for c in SilenceClass} == {"intentional", "needs_human", "system_fault"}


# ---------------------------------------------------------------------------
# ۲. ثبت: کلاس روی اجراهای تازه، بدون تغییر رفتار
# ---------------------------------------------------------------------------


def _answer(**kw: Any) -> ModelAnswer:
    base: dict[str, Any] = {
        "answer": "دوره مقدماتی شانزده جلسه دارد.",
        "confidence": 0.95,
        "needs_human": False,
        "reason": "از منبع رسمی",
        "used_chunk_ids": [1],
    }
    return ModelAnswer(**{**base, **kw})


QUESTION = "دوره مقدماتی چند جلسه است؟"

# (دلیل، متن پیام، کلاینت مدل). هر کدام همان مسیر زنده‌ی قدیمی است.
LEGACY_SCENARIOS: list[tuple[str, str, ScriptedClient]] = [
    ("rule_money", "رسید واریزم", ScriptedClient(_answer())),
    ("rule_complaint", "شکایت دارم", ScriptedClient(_answer())),
    ("model_error", QUESTION, ScriptedClient(None, error="timeout")),
    ("model_flagged", QUESTION, ScriptedClient(_answer(needs_human=True))),
    ("low_confidence", QUESTION, ScriptedClient(_answer(confidence=0.4))),
    ("empty_answer", QUESTION, ScriptedClient(_answer(answer="   "))),
    (
        "ungrounded_money",
        QUESTION,
        ScriptedClient(_answer(answer="شهریه‌اش ۴۵۰ هزار تومان است.", confidence=0.99)),
    ),
]


@pytest.mark.parametrize(
    ("reason", "body", "client"), LEGACY_SCENARIOS, ids=[s[0] for s in LEGACY_SCENARIOS]
)
async def test_a_live_silence_is_recorded_with_its_class(
    session: AsyncSession,
    account: MentorAccount,
    knowledge: None,
    embedder: HashingEmbedder,
    reason: str,
    body: str,
    client: ScriptedClient,
) -> None:
    message = await _incoming(session, account, body)
    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.silence
    assert result.reason == reason, "رفتار legacy نباید عوض شده باشد"
    run = (await session.execute(select(AiRun))).scalar_one()
    assert run.silence_class == OWNER_MAPPING[reason].value
    # هر سکوت غیرعمدی همچنان یک ردیف ارجاع دارد (رفتار موجود).
    assert len((await session.execute(select(Escalation))).scalars().all()) == 1


async def test_no_sources_is_recorded_as_needs_human(
    session: AsyncSession, account: MentorAccount, embedder: HashingEmbedder
) -> None:
    message = await _incoming(session, account, "سؤالی که هیچ سندی ندارد")
    result = await handle_message(
        session, message, model_client=ScriptedClient(_answer()), embedder=embedder
    )
    await session.commit()

    assert result.reason == "no_sources"
    run = (await session.execute(select(AiRun))).scalar_one()
    assert run.silence_class == "needs_human"


async def test_a_media_silence_is_recorded_as_needs_human(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    message = await _incoming(session, account, None, media_type="voice")
    await _with_media(session, message, kind="voice", text="")

    result = await handle_message(
        session, message, model_client=ScriptedClient(_answer()), embedder=embedder
    )
    await session.commit()

    assert result.reason == "unsupported_media"
    run = (await session.execute(select(AiRun))).scalar_one()
    assert run.silence_class == "needs_human"
    assert len((await session.execute(select(Escalation))).scalars().all()) == 1


async def test_an_answer_has_no_class(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    """پاسخ سکوت نیست و کلاس ندارد."""
    message = await _incoming(session, account, QUESTION)
    result = await handle_message(
        session, message, model_client=ScriptedClient(_confident()), embedder=embedder
    )
    await session.commit()

    assert result.outcome is Outcome.answer
    run = (await session.execute(select(AiRun))).scalar_one()
    assert run.silence_class is None


# ---------------------------------------------------------------------------
# ۳. سکوت عمدی: ردیف ارجاع نمی‌سازد
# ---------------------------------------------------------------------------


async def test_an_intentional_silence_makes_no_escalation_and_the_rest_do(
    session: AsyncSession, account: MentorAccount
) -> None:
    """هر دلیل سکوت جز `out_of_domain` یک ردیف ارجاع می‌سازد؛ آن یکی هرگز."""
    reasons = [r.value for r in SilenceReason]
    messages = {}
    for i, reason in enumerate(reasons, start=1):
        message = await _incoming(session, account, f"پیام {i}", message_id=i)
        messages[reason] = message.id
        await _record(session, message=message, outcome=Outcome.silence, reason=reason, hits=[])
        await session.commit()

    escalated = {e.message_id for e in (await session.execute(select(Escalation))).scalars()}
    assert messages["out_of_domain"] not in escalated
    assert escalated == {mid for reason, mid in messages.items() if reason != "out_of_domain"}


async def test_an_intentional_silence_is_recorded_but_never_pending(
    session: AsyncSession, account: MentorAccount
) -> None:
    message = await _incoming(session, account, "قیمه شیرازی")
    await _record(
        session, message=message, outcome=Outcome.silence, reason="out_of_domain", hits=[]
    )
    await session.commit()

    run = (await session.execute(select(AiRun))).scalar_one()
    assert run.reason == "out_of_domain"
    assert run.silence_class == "intentional"
    assert await escalation.open_escalations(session) == []
    kpis = await queries.kpis(session, ADMIN)
    assert kpis.open_escalations == 0
    assert (await health.escalations(session)).level is health.Level.ok


# ---------------------------------------------------------------------------
# ۴. قید پایگاه داده
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("outcome", "silence_class", "ok"),
    [
        ("silence", "intentional", True),
        ("silence", "needs_human", True),
        ("silence", "system_fault", True),
        ("silence", None, True),  # اجرای قدیمی
        ("answer", None, True),
        ("answer", "needs_human", False),  # پاسخ کلاس ندارد
        ("answer", "intentional", False),
        ("silence", "partial", False),  # `partial` کلاس نیست
        ("silence", "bogus", False),
    ],
)
async def test_the_database_only_allows_a_class_on_a_silence(
    session: AsyncSession,
    account: MentorAccount,
    outcome: str,
    silence_class: str | None,
    ok: bool,
) -> None:
    message = await _incoming(session, account, "پیام")
    session.add(
        AiRun(
            conversation_id=message.conversation_id,
            message_id=message.id,
            outcome=outcome,
            reason="x",
            silence_class=silence_class,
            prompt_version="v2",
        )
    )
    if ok:
        await session.commit()
        return
    with pytest.raises(IntegrityError):
        await session.commit()
    await session.rollback()


# ---------------------------------------------------------------------------
# ۵. شاخص‌ها
# ---------------------------------------------------------------------------


async def test_legacy_rows_and_class_stamped_rows_are_counted_identically(
    session: AsyncSession, account: MentorAccount
) -> None:
    """همان ۱۵ اجرا، یک‌بار با کلاس تهی (قدیمی) و یک‌بار با کلاس: اعداد برابرند."""
    await _seed_legacy_runs(session, account)
    legacy_kpis = await queries.kpis(session, ADMIN)
    legacy_facts = (await health.snapshot(session)).facts

    # همان داده با کلاس. سطرها را به‌روز می‌کنیم، نه دوباره می‌سازیم.
    await session.execute(
        text(
            "update ai_runs set silence_class = case reason "
            "when 'model_error' then 'system_fault' else 'needs_human' end "
            "where outcome = 'silence'"
        )
    )
    await session.commit()

    stamped_kpis = await queries.kpis(session, ADMIN)
    stamped_facts = (await health.snapshot(session)).facts

    assert (
        (stamped_kpis.runs_7d, stamped_kpis.answered_7d, stamped_kpis.silent_7d)
        == (
            legacy_kpis.runs_7d,
            legacy_kpis.answered_7d,
            legacy_kpis.silent_7d,
        )
        == (ANSWERS + sum(n for _, n in LEGACY_SILENCES), ANSWERS, 10)
    )
    assert stamped_kpis.answer_rate == legacy_kpis.answer_rate
    assert stamped_facts == legacy_facts


async def test_intentional_runs_are_counted_apart_from_every_rate(
    session: AsyncSession, account: MentorAccount
) -> None:
    """سکوت عمدی در نرخ پاسخ، نرخ سکوت و شمار اجراها نمی‌آید و جدا دیده می‌شود."""
    await _seed_legacy_runs(session, account)
    before_kpis = await queries.kpis(session, ADMIN)
    before_facts = (await health.snapshot(session)).facts

    for i in range(100, 104):
        message = await _message(session, account, i)
        session.add(
            AiRun(
                conversation_id=message.conversation_id,
                message_id=message.id,
                outcome="silence",
                reason="out_of_domain",
                silence_class="intentional",
                prompt_version="v2",
            )
        )
    await session.commit()

    kpis = await queries.kpis(session, ADMIN)
    assert (kpis.runs_7d, kpis.answered_7d, kpis.silent_7d) == (15, 5, 10)
    assert kpis.answer_rate == before_kpis.answer_rate
    assert kpis.intentional_7d == 4

    facts = (await health.snapshot(session)).facts
    assert facts["answer_rate"] == before_facts["answer_rate"] == 0.333
    assert facts["silence_rate"] == before_facts["silence_rate"] == 0.667
    assert facts["ai_runs"] == 19, "همه‌ی اجراها، شامل عمدی"
    assert facts["intentional_runs"] == 4


async def test_without_any_intentional_run_the_new_counters_are_zero(
    session: AsyncSession, account: MentorAccount
) -> None:
    await _seed_legacy_runs(session, account)

    assert (await queries.kpis(session, ADMIN)).intentional_7d == 0
    assert (await health.snapshot(session)).facts["intentional_runs"] == 0


# ---------------------------------------------------------------------------
# ۶. migration: فقط افزودن، بدون backfill، برگشت‌پذیر
# ---------------------------------------------------------------------------


def _alembic(*args: str) -> None:
    result = subprocess.run(
        [sys.executable, "-m", "alembic", *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"alembic {' '.join(args)}:\n{result.stdout}\n{result.stderr}"


async def _snapshot(session: AsyncSession, tag: str) -> list[dict[str, Any]]:
    """همه‌ی ستون‌های `ai_runs`.

    `tag` متن SQL را هر بار متفاوت می‌کند: asyncpg پلن `select *` را کش می‌کند و بعد از
    تغییر ستون‌ها با `InvalidCachedStatementError` رد می‌شود.
    """
    rows = await session.execute(text(f"select * from ai_runs /* {tag} */ order by id"))
    return [dict(r._mapping) for r in rows]


async def test_the_migration_adds_without_touching_existing_runs(
    session: AsyncSession, account: MentorAccount
) -> None:
    """up/down/up با داده: ردیف‌های قدیمی بایت‌به‌بایت یکی می‌مانند و کلاسشان تهی است."""
    await _seed_legacy_runs(session, account)
    await session.commit()
    session.expire_all()

    try:
        # ۱. به وضعیت پیش از RO-1 برگرد (ستون حذف می‌شود).
        _alembic("downgrade", "0016")
        before = await _snapshot(session, "pre-ro1")
        await session.commit()
        assert before, "پیش‌شرط: داده‌ی قدیمی هست"
        assert "silence_class" not in before[0], "پیش‌شرط: پایگاه داده‌ی پیش از RO-1"

        # ۲. ارتقا: ستون می‌آید، هیچ ردیفی عوض نمی‌شود، backfill ای نیست.
        _alembic("upgrade", "head")
        after_up = await _snapshot(session, "after-up")
        await session.commit()
        assert [r.pop("silence_class") for r in after_up] == [None] * len(before)
        assert after_up == before, "ارتقا هیچ ستون قدیمی‌ای را تغییر نداد"

        # ۳. برگشت دوباره: باز هم همان داده.
        _alembic("downgrade", "0016")
        after_down = await _snapshot(session, "after-down")
        await session.commit()
        assert after_down == before
    finally:
        _alembic("upgrade", "head")
        # اتصال‌های استخر پلن‌های کش‌شده‌ی پیش از تغییر ستون‌ها را نگه می‌دارند؛ بدون بستنشان
        # اولین تستِ بعدی که به `ai_runs` می‌نویسد با `InvalidCachedStatementError` می‌افتد.
        await get_engine().dispose()

    # ۴. پایان: طرح دوباره کامل است و ستون هست.
    columns = (
        (
            await session.execute(
                text(
                    "select column_name from information_schema.columns "
                    "where table_name = 'ai_runs' and column_name = 'silence_class'"
                )
            )
        )
        .scalars()
        .all()
    )
    await session.commit()
    assert columns == ["silence_class"]
