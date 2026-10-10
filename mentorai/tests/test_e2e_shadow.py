"""سایه‌ی سرتاسری پاسخ‌دهی: انتخاب نمونه، اتصال مرحله‌ها، نوشتن، سقف هزینه و نبودِ اثر جانبی.

هیچ‌کدام به API واقعی نیاز ندارند. مدل `_Pipeline` است (کلاینت آزمایشی با پاسخ از پیش تعیین‌شده برای
هر مرحله)، پس این آزمون‌ها **کیفیت نوشتن یا داوری Claude را نمی‌سنجند**؛ لوله‌کشی، قراردادها،
محافظ‌های کد و ایمنی خروجی را می‌سنجند.
"""

from __future__ import annotations

import ast
import csv
import dataclasses
import io
import json
import re
import stat
from argparse import Namespace
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession
from tests.test_retrieval_shadow import _fake_hit, _FakeSearch, _install, _message
from tests.test_ro5b_evidence_shadow import (
    ACADEMY_YES,
    NOPE,
    USEFUL,
    WEAK,
    Verdict,
    _hit,
    _ro3_doc,
    _ro3_part,
    _seed_chunks,
)
from tests.test_understanding import SRC, _imports, _part, _payload
from tests.test_understanding_replay import _snapshot

from mentorai import cli
from mentorai.ai import decision_shadow as ds
from mentorai.ai import e2e_shadow as e2e
from mentorai.ai import prompt as production_prompt
from mentorai.ai import retrieval_shadow as rs
from mentorai.ai import ro5b_evidence_shadow as r5
from mentorai.ai import understanding
from mentorai.ai import understanding as und
from mentorai.ai.client import RawCall, ScriptedClient
from mentorai.db.models import MentorAccount
from mentorai.db.session import get_engine
from mentorai.model_compare import MASK
from mentorai.model_compare import mask_personal as mask_text

PHONE = "09121234567"
EMAIL = "student@example.com"


# ---------------------------------------------------------------------------
# مدل آزمایشی برای هر چهار مرحله
# ---------------------------------------------------------------------------


class _Pipeline(ScriptedClient):
    """فهم، ارزیاب شواهد و نویسنده را از روی دستور سیستمی تشخیص می‌دهد؛ پاسخ از پیش تعیین‌شده است."""

    def __init__(
        self,
        understanding_routes: dict[str, str],
        verdicts: dict[int, Verdict] | None = None,
        *,
        writer: dict[str, Any] | str | None = None,
        tokens: dict[str, int] | None = None,
    ) -> None:
        super().__init__(raw_text="")
        self.routes = understanding_routes
        self.verdicts = verdicts or {}
        self.writer = writer
        self.tokens = tokens or {}
        self.stage_calls: dict[str, list[str]] = {"understanding": [], "evidence": [], "writer": []}

    def _writer_text(self, user: str) -> str:
        mode = next((k for k, v in e2e.MODE_BRIEF.items() if f"حالت: {v}" in user), "?")
        if isinstance(self.writer, str):
            return self.writer
        if isinstance(self.writer, dict) and mode in self.writer:
            return json.dumps(self.writer[mode], ensure_ascii=False)
        return json.dumps({"answer": f"پاسخ آزمایشی {mode}", "enough_information": True})

    async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> RawCall:
        self.calls.append((system, user))
        if system == understanding.SYSTEM_PROMPT:
            stage = "understanding"
            current = user.rsplit("پیام فعلی دانشجو که باید بفهمی:", 1)[-1]
            text = next((p for m, p in self.routes.items() if m in current), None)
        elif system == r5.SYSTEM_PROMPT:
            stage = "evidence"
            ids = [int(i) for i in re.findall(r"=== chunk_id=(\d+) ===", user)]
            text = json.dumps(
                {
                    "evaluations": [
                        {
                            "chunk_id": i,
                            "relevance": (self.verdicts.get(i, NOPE))[0],
                            "supports_question": (self.verdicts.get(i, NOPE))[1],
                            "academy_fact_supported": (self.verdicts.get(i, NOPE))[2],
                            "reason": (self.verdicts.get(i, NOPE))[3],
                        }
                        for i in ids
                    ]
                }
            )
        elif system == e2e.WRITER_SYSTEM_PROMPT:
            stage = "writer"
            text = self._writer_text(user)
        else:  # pragma: no cover - مرحله‌ی ناشناخته نباید فراخوانی شود
            raise AssertionError("دستور سیستمی ناشناخته")
        self.stage_calls[stage].append(user)
        used = self.tokens.get(stage, 10)
        return RawCall(
            text=text,
            model=self.model,
            latency_ms=1,
            input_tokens=used,
            output_tokens=used,
            error=None if text is not None else "no-route",
        )


def _args(tmp_path: Path, **overrides: object) -> Namespace:
    values: dict[str, object] = {
        "select_from": None,
        "limit": 20,
        "seed": 7,
        "max_cost_usd": 5.0,
        "out": str(tmp_path / "out"),
        "dry_run": False,
    }
    values.update(overrides)
    return Namespace(**values)


def _patch_client(monkeypatch: pytest.MonkeyPatch, client: ScriptedClient) -> None:
    monkeypatch.setattr("mentorai.ai.providers.build_client", lambda: client)


# ---------------------------------------------------------------------------
# ۱) بخش اجتماعی
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("scope", "topic", "fact", "expected"),
    [
        ("in_domain", "other", "none", True),
        ("borderline", "other", "none", False),
        ("out_of_domain", "other", "none", False),
        ("in_domain", "risk_management", "none", False),
        ("in_domain", "other", "general_knowledge", False),
        ("in_domain", "other", "academy_fact", False),
        ("in_domain", "other", "realtime", False),
    ],
)
def test_only_in_domain_other_none_parts_count_as_social(
    scope: str, topic: str, fact: str, expected: bool
) -> None:
    assert e2e.is_social(scope, topic, fact) is expected


def test_the_social_skip_works_on_a_real_understanding_part() -> None:
    social = understanding.Part.model_validate(_part(1, "سلام", topic="other", fact_class="none"))
    real = understanding.Part.model_validate(_part(1, "ریسک چیست؟"))

    assert e2e.social_skip(social) == e2e.SKIP_SOCIAL
    assert e2e.social_skip(real) is None


# ---------------------------------------------------------------------------
# ۲) انتخاب نمونه با پوشش دسته‌ها
# ---------------------------------------------------------------------------


def _record(
    message_id: str,
    *,
    scope: str = "in_domain",
    topic: str = "risk_management",
    fact: str = "general_knowledge",
    strategy: str = "mixed",
    effective: str | None = None,
    status: str = "model_run",
) -> dict[str, Any]:
    return {
        "message_id": message_id,
        "evaluation_status": status,
        "understanding": {
            "parts": [{"part_id": 1, "scope": scope, "topic": topic, "fact_class": fact}]
        },
        "decision": {
            "parts": [
                {
                    "part_id": 1,
                    "effective_fact_class": effective or fact,
                    "decision": {"strategy": strategy},
                }
            ]
        },
    }


def _pool() -> dict[str, Any]:
    records = []
    n = 0

    def add(count: int, **kwargs: Any) -> None:
        nonlocal n
        for _ in range(count):
            n += 1
            records.append(_record(f"m{n}", **kwargs))

    add(6, topic="academy_process", fact="academy_fact", strategy="silence")
    add(4, topic="other", fact="none", strategy="clarify", scope="borderline")
    add(6, topic="other", fact="none", strategy="general_knowledge")
    add(8, topic="trading_psychology", fact="general_knowledge", strategy="mixed")
    add(5, topic="market_concepts", fact="none", strategy="general_knowledge")
    return {"messages": records}


def test_message_categories_come_only_from_the_recorded_model_fields() -> None:
    assert e2e.message_categories(
        _record("m1", topic="academy_process", fact="academy_fact", strategy="silence")
    ) == {"academy_fact", "silence"}
    assert e2e.message_categories(
        _record("m2", scope="borderline", topic="other", fact="none", strategy="clarify")
    ) == {"borderline", "clarification"}
    assert e2e.message_categories(
        _record("m3", topic="other", fact="none", strategy="general_knowledge")
    ) == {"social"}
    assert e2e.message_categories(
        _record("m4", topic="metatrader_tools", fact="general_knowledge")
    ) == {"trading", "general_knowledge"}
    assert e2e.message_categories(
        _record(
            "m5", topic="broker_wallet", fact="none", effective="academy_fact", strategy="mixed"
        )
    ) == {"academy_fact"}


def test_categorize_keeps_only_executed_messages_and_rejects_a_broken_file() -> None:
    doc = {
        "messages": [
            _record("m1"),
            _record("m2", status="model_unavailable"),
            _record("x3"),
        ]
    }

    assert list(e2e.categorize_ro5a(doc)) == ["m1"]
    for broken in ([], {"messages": "x"}, {"messages": ["x"]}):
        with pytest.raises(e2e.E2EError):
            e2e.categorize_ro5a(broken)


def test_selection_covers_every_required_category_and_respects_the_limit() -> None:
    categories = e2e.categorize_ro5a(_pool())

    selection = e2e.select_messages(categories, limit=20, seed=7)

    assert len(selection.ids) == 20 and len(set(selection.ids)) == 20
    for name, minimum in e2e.COVERAGE:
        assert selection.coverage[name] >= minimum, name
    assert selection.shortfall == {}
    assert list(selection.ids) == sorted(selection.ids, key=lambda i: int(i[1:]))
    assert selection.available["academy_fact"] == 6


def test_selection_is_deterministic_and_seed_dependent() -> None:
    categories = e2e.categorize_ro5a(_pool())

    a = e2e.select_messages(categories, limit=20, seed=7)
    b = e2e.select_messages(categories, limit=20, seed=7)
    c = e2e.select_messages(categories, limit=20, seed=8)

    assert a == b
    assert a.ids != c.ids


def test_a_missing_category_is_reported_as_a_shortfall_not_invented() -> None:
    only_trading = {"messages": [_record(f"m{n}", topic="risk_management") for n in range(1, 9)]}
    categories = e2e.categorize_ro5a(only_trading)

    selection = e2e.select_messages(categories, limit=5, seed=1)

    assert len(selection.ids) == 5
    assert selection.coverage["academy_fact"] == 0
    assert selection.shortfall["academy_fact"] == 3 and selection.shortfall["social"] == 3
    assert "trading" not in selection.shortfall


def test_a_small_pool_selects_everything_and_a_tiny_limit_still_works() -> None:
    categories = e2e.categorize_ro5a({"messages": [_record("m1"), _record("m2")]})

    assert len(e2e.select_messages(categories, limit=20, seed=1).ids) == 2
    assert len(e2e.select_messages(categories, limit=1, seed=1).ids) == 1


def test_cases_for_uses_only_currently_eligible_messages() -> None:
    selection = e2e.Selection(("m1", "m2", "m3"), {}, {}, {})
    eligible = [e2e.Case("m3", "c"), e2e.Case("m1", "a")]

    cases, missing = e2e.cases_for(selection, eligible)

    assert [c.id for c in cases] == ["m1", "m3"] and missing == 1


# ---------------------------------------------------------------------------
# ۳) ارزیاب شواهدِ تصمیم ← RO-5B
# ---------------------------------------------------------------------------


async def _judged(
    verdicts: dict[int, Verdict],
    hits: list[dict[str, Any]],
    **part: Any,
) -> tuple[list[r5.PartResult], dict[str, Any]]:
    doc = _ro3_doc([_ro3_part("m1", 1, hits=hits, **part)])
    judge = _Pipeline({}, verdicts)
    ev = await r5.run_ro5b(
        r5.parse_input(doc),
        {h["chunk_id"]: f"متن {h['chunk_id']}" for h in hits},
        judge,
        input_name="x",
        seed=1,
        max_parts=None,
        max_cost_usd=5.0,
    )
    return ev.results, doc


async def _decide(
    verdicts: dict[int, Verdict], hits: list[dict[str, Any]], **part: Any
) -> ds.PartDecision:
    results, doc = await _judged(verdicts, hits, **part)
    decision = ds.decide_document(doc, e2e.Ro5bAssessor(results))
    return decision.messages[0].parts[0]


async def test_strong_evidence_makes_an_academy_fact_kb_grounded_with_the_direct_chunks() -> None:
    decided = await _decide({1: ACADEMY_YES, 2: USEFUL}, [_hit(1, score=0.03), _hit(2, score=0.02)])

    assert decided.evidence.level is ds.EvidenceLevel.strong
    assert decided.evidence.supporting_chunk_ids == (1,)
    assert decided.decision.strategy is ds.Strategy.kb_grounded


async def test_moderate_evidence_is_weak_with_partial_support_so_an_academy_fact_is_mixed() -> None:
    decided = await _decide({1: USEFUL, 2: NOPE}, [_hit(1, score=0.03), _hit(2, score=0.02)])

    assert decided.evidence.level is ds.EvidenceLevel.weak
    assert decided.evidence.supports_part_of_question is True
    assert decided.evidence.supporting_chunk_ids == (1,)
    assert decided.decision.strategy is ds.Strategy.mixed


async def test_weak_evidence_keeps_an_academy_fact_silent_and_human() -> None:
    decided = await _decide({1: WEAK}, [_hit(1)])

    assert decided.evidence.level is ds.EvidenceLevel.weak
    assert decided.decision.strategy is ds.Strategy.silence and decided.decision.needs_human


async def test_all_irrelevant_chunks_are_no_evidence() -> None:
    academy = await _decide({1: NOPE}, [_hit(1)])
    general = await _decide(
        {1: NOPE}, [_hit(1)], topic="market_concepts", fact_class="general_knowledge"
    )

    assert academy.evidence.level is ds.EvidenceLevel.none
    assert academy.decision.reason == "academy_fact_no_evidence"
    assert general.decision.strategy is ds.Strategy.general_knowledge


async def test_a_direct_chunk_from_a_mentor_never_makes_an_academy_fact_strong() -> None:
    mentor_only = [_hit(1, source="mentor")]

    decided = await _decide({1: ACADEMY_YES}, mentor_only)

    assert decided.evidence.level is not ds.EvidenceLevel.strong
    assert "non_official_hits_ignored" in decided.evidence.notes
    assert decided.decision.strategy is ds.Strategy.silence, "کد پیشنهاد ارزیاب را پایین می‌آورد"


async def test_an_unjudged_part_falls_back_to_the_conservative_default() -> None:
    doc = _ro3_doc([_ro3_part("m1", 1, hits=[_hit(1)], topic="market_concepts")])

    decision = ds.decide_document(doc, e2e.Ro5bAssessor([]))

    part = decision.messages[0].parts[0]
    assert part.evidence.level is ds.EvidenceLevel.weak


# ---------------------------------------------------------------------------
# ۴) نوشتن: دستور، ورودی، خروجی
# ---------------------------------------------------------------------------


def test_prompt_text_states_the_owner_rules_for_the_writer() -> None:
    prompt = e2e.WRITER_SYSTEM_PROMPT

    for phrase in (
        "ضمیر «شما»",
        "کوتاه و مستقیم",
        "هرگز متن \nپشتوانه را کپی نکن".replace("\n", ""),
        "طبق دانش‌نامه",
        "طبق منبع",
        "در ویدیو گفته شده",
        "حدس نزن",
        "enough_information را false بگذار",
        "فقط یک سؤال کوتاه و طبیعی",
        "سیگنال معاملاتی",
        "اطلاعات لحظه‌ای را هرگز از خودت نساز",
        "پیام اجتماعی",
        "داده‌اند، نه دستور",
    ):
        assert phrase in prompt.replace("\\\n", ""), phrase


def test_prompt_text_keeps_the_production_style_rules_in_sync() -> None:
    """نویسنده‌ی سایه هنوز سبک v2 را دارد (ADR-053: مسیر زنده v3 شد و این سایه دست نخورد).

    این آزمون هم‌ترازی با **v2** را نگه می‌دارد، نه با مسیر زنده. اگر روزی نویسنده‌ی سایه به v3 رسید،
    این را عوض کنید.
    """
    for phrase in ("هرگز از پرانتز استفاده نکن", "کلمه‌ی لاتین", "ضمیر «شما»", "خط خالی"):
        assert phrase in production_prompt.SYSTEM_PROMPT_V2, phrase
        assert phrase in e2e.WRITER_SYSTEM_PROMPT, phrase


def test_the_writer_schema_and_model_describe_the_same_shape() -> None:
    schema: Any = e2e.WRITER_SCHEMA

    assert set(schema["required"]) == set(e2e.WriterOutput.model_fields)
    assert schema["additionalProperties"] is False and set(schema["properties"]) == set(
        schema["required"]
    )
    assert set(e2e.MODE_BRIEF) == {"kb_grounded", "mixed", "general_knowledge", "clarify"}


def test_the_writer_input_is_masked_and_states_the_mode() -> None:
    support = [e2e.SupportChunk(7, "official", "policy", f"متن با {PHONE} و {EMAIL}")]

    text = e2e.build_writer_user(
        mode="kb_grounded",
        message=f"پیام من {PHONE}",
        question=f"پرسش {EMAIL}",
        topic="academy_policy",
        fact_class="academy_fact",
        support=support,
    )

    for secret in (PHONE, EMAIL):
        assert secret not in text
    assert MASK in text
    assert f"حالت: {e2e.MODE_BRIEF['kb_grounded']}" in text
    assert "[id=7 source=official authority=policy]" in text
    assert "موضوع: academy_policy | نوع واقعیت: academy_fact" in text


def test_without_support_the_writer_is_told_there_is_none() -> None:
    text = e2e.build_writer_user(
        mode="general_knowledge",
        message="سلام",
        question="سلام",
        topic="other",
        fact_class="none",
        support=[],
    )

    assert "هیچ پشتوانه‌ای از پایگاه دانش برای این بخش نیست" in text
    assert "[id=" not in text


async def test_a_written_answer_is_returned_and_masked() -> None:
    client = _Pipeline(
        {},
        writer={"general_knowledge": {"answer": f"زنگ بزنید {PHONE}", "enough_information": True}},
    )

    result = await e2e.write_part(client, f"حالت: {e2e.MODE_BRIEF['general_knowledge']}")

    assert result.status == e2e.WRITER_WRITTEN
    assert PHONE not in result.answer and MASK in result.answer
    assert result.cost_usd > 0


@pytest.mark.parametrize(
    "payload",
    [
        {"answer": "", "enough_information": True},
        {"answer": "   ", "enough_information": True},
        {"answer": "یک پاسخ حدسی", "enough_information": False},
        {"answer": "", "enough_information": False},
    ],
)
async def test_an_answer_without_enough_information_is_dropped_never_kept(
    payload: dict[str, Any],
) -> None:
    client = _Pipeline({}, writer=json.dumps(payload))

    result = await e2e.write_part(client, "x")

    assert result.status == e2e.WRITER_DECLINED and result.answer == ""


@pytest.mark.parametrize(
    "raw_text",
    [
        "این JSON نیست",
        json.dumps({"answer": "x"}),
        json.dumps({"answer": "x", "enough_information": "true"}),
        json.dumps({"answer": "x", "enough_information": True, "extra": 1}),
        json.dumps({"answer": 5, "enough_information": True}),
    ],
)
async def test_a_malformed_writer_output_is_invalid_and_leaves_no_answer(raw_text: str) -> None:
    result = await e2e.write_part(_Pipeline({}, writer=raw_text), "x")

    assert result.status == e2e.WRITER_INVALID and result.answer == ""


async def test_writer_model_errors_never_raise_and_never_leak_the_exception_text() -> None:
    class Boom(ScriptedClient):
        async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> RawCall:
            raise RuntimeError(f"secret {EMAIL}")

    no_text = await e2e.write_part(ScriptedClient(error=f"fail {EMAIL}", raw_text=None), "x")
    raised = await e2e.write_part(Boom(), "x")

    assert no_text.status == raised.status == e2e.WRITER_MODEL_ERROR
    assert EMAIL not in (no_text.detail or "") and raised.detail == "RuntimeError"


# ---------------------------------------------------------------------------
# ۵) پشتوانه‌ی نویسنده فقط از شواهدِ پذیرفته‌شده می‌آید
# ---------------------------------------------------------------------------


async def test_the_writer_gets_at_most_four_validated_support_chunks() -> None:
    hits = [_hit(i, score=0.04 - i / 1000) for i in range(1, 8)]
    verdicts: dict[int, Verdict] = {i: ACADEMY_YES for i in range(1, 7)}
    results, doc = await _judged(verdicts, hits)
    decided = ds.decide_document(doc, e2e.Ro5bAssessor(results)).messages[0].parts[0]
    contents = {i: f"متن {i}" for i in range(1, 8)}
    evidence = {(r.message_id, r.part_id): r for r in results}

    support = e2e._support_for(decided, evidence, contents)

    assert len(decided.evidence.supporting_chunk_ids) == 6
    assert [c.chunk_id for c in support] == [1, 2, 3, 4]
    assert all(c.source_class == "official" for c in support)


async def test_only_grounded_strategies_receive_support() -> None:
    hits = [_hit(1)]
    results, doc = await _judged({1: ACADEMY_YES}, hits)
    decided = ds.decide_document(doc, e2e.Ro5bAssessor(results)).messages[0].parts[0]
    evidence = {(r.message_id, r.part_id): r for r in results}
    general = dataclasses.replace(
        decided, decision=ds.Decision(ds.Strategy.general_knowledge, False, "x")
    )

    assert len(e2e._support_for(decided, evidence, {1: "متن"})) == 1
    assert e2e._support_for(general, evidence, {1: "متن"}) == []
    assert e2e._support_for(decided, evidence, {}) == [], "متنِ ناموجود هرگز حدس زده نمی‌شود"


# ---------------------------------------------------------------------------
# ۶) پارامتر اختیاریِ بی‌اثر در سایه‌ی بازیابی
# ---------------------------------------------------------------------------


async def test_skip_part_skips_retrieval_without_changing_the_default_behaviour(
    session: AsyncSession,
    account: MentorAccount,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    message = await _message(session, account, "نمونه-الف: سلام", 1)
    fake = _install(monkeypatch, _FakeSearch({"q-social": [_fake_hit(1)]}))
    reply = _payload(_part(1, "سلام", topic="other", fact_class="none", queries=("q-social",)))
    client = _Pipeline({"نمونه-الف": reply})
    case = [e2e.Case(f"m{message.id}", message.text or "")]

    plain = await rs.run_retrieval_shadow(session, case, client, max_cost_usd=5.0)
    skipped = await rs.run_retrieval_shadow(
        session, case, client, max_cost_usd=5.0, skip_part=e2e.social_skip
    )

    assert plain.messages[0].parts[0].skipped is None
    assert len(fake.calls) == 1, "فقط اجرای بدون skip_part جست‌وجو کرد"
    part = skipped.messages[0].parts[0]
    assert part.skipped == e2e.SKIP_SOCIAL and part.retrieval is None


async def test_the_builtin_skips_win_over_a_custom_one(
    session: AsyncSession,
    account: MentorAccount,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    message = await _message(session, account, "نمونه-الف: الان بخرم؟", 1)
    _install(monkeypatch, _FakeSearch())
    reply = _payload(_part(1, "الان بخرم؟", fact_class="trade_advice"))

    data = await rs.run_retrieval_shadow(
        session,
        [e2e.Case(f"m{message.id}", message.text or "")],
        _Pipeline({"نمونه-الف": reply}),
        max_cost_usd=5.0,
        skip_part=lambda part: "custom",
    )

    assert data.messages[0].parts[0].skipped == rs.SKIP_TRADE_ADVICE


# ---------------------------------------------------------------------------
# ۷) اجرای سرتاسری روی پایگاه داده (مدل و بازیابی ساختگی)
# ---------------------------------------------------------------------------

BODIES = [
    f"نمونه-الف: شرایط ارسال تمرین چیست؟ شماره‌ی من {PHONE}",
    "نمونه-ب: ریسک به ریوارد یعنی چه؟",
    "نمونه-ج: سلام وقت بخیر",
    "نمونه-د: الان بخرم یا نه؟",
    "نمونه-ه: چرا کار نمی‌کند؟",
    "نمونه-و: قانون برداشت چیست؟",
    "نمونه-ز: این JSON نمی‌شود",
]


async def _scenario(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> tuple[_Pipeline, _FakeSearch, list[int]]:
    ids = await _seed_chunks(
        session,
        [
            "SENTINEL-DIRECT مبلغ و شرط ارسال تمرین",
            "SENTINEL-USEFUL توضیح تکمیلی",
            "SENTINEL-WEAK هم‌موضوع",
            "SENTINEL-OTHER دیگر",
        ],
    )
    for n, body in enumerate(BODIES, start=1):
        await _message(session, account, body, n)
    hits = lambda *chunk_ids: [  # noqa: E731
        _fake_hit(c, score=0.03 - k / 1000) for k, c in enumerate(chunk_ids)
    ]
    fake = _install(
        monkeypatch,
        _FakeSearch(
            {
                "q-ac": hits(ids[0], ids[1]),
                "q-gk": hits(ids[2]),
                "q-social": hits(ids[3]),
                "q-weak": hits(ids[2]),
            }
        ),
    )
    routes = {
        "نمونه-الف": _payload(
            _part(
                1,
                "شرایط ارسال تمرین چیست؟",
                topic="academy_process",
                fact_class="academy_fact",
                queries=("q-ac",),
            )
        ),
        "نمونه-ب": _payload(_part(1, "ریسک به ریوارد چیست؟", queries=("q-gk",))),
        "نمونه-ج": _payload(
            _part(1, "سلام", topic="other", fact_class="none", queries=("q-social",))
        ),
        "نمونه-د": _payload(
            _part(1, "الان بخرم؟", topic="trading_education", fact_class="trade_advice")
        ),
        "نمونه-ه": _payload(
            _part(1, "چرا کار نمی‌کند؟", topic="metatrader_tools", fact_class="none"),
            ambiguity="needs_clarification",
        ),
        "نمونه-و": _payload(
            _part(
                1,
                "قانون برداشت چیست؟",
                topic="broker_wallet",
                fact_class="academy_fact",
                queries=("q-weak",),
            )
        ),
        "نمونه-ز": "این JSON نیست",
    }
    verdicts = {ids[0]: ACADEMY_YES, ids[1]: USEFUL, ids[2]: WEAK, ids[3]: NOPE}
    return _Pipeline(routes, verdicts), fake, ids


async def test_the_full_run_connects_all_stages_and_writes_only_where_the_decision_allows(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    client, fake, ids = await _scenario(session, account, monkeypatch)
    _patch_client(monkeypatch, client)
    before = await _snapshot(session)

    code = await cli.cmd_e2e_shadow_run(_args(tmp_path))

    assert code == 0
    out = tmp_path / "out"
    assert sorted(p.name for p in out.iterdir()) == ["e2e_review.csv", "e2e_shadow.json", "prompts"]
    for path in (out / "e2e_review.csv", out / "e2e_shadow.json"):
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert stat.S_IMODE((out / "prompts").stat().st_mode) == 0o700
    doc = json.loads((out / "e2e_shadow.json").read_text(encoding="utf-8"))
    by_text = {m["masked_student_message"].split(":")[0]: m for m in doc["messages"]}

    grounded = by_text["نمونه-الف"]
    assert grounded["decision_strategy"] == "kb_grounded"
    assert grounded["evidence_quality"] == "strong"
    assert grounded["retrieved_chunk_ids"] == ids[:2]
    assert grounded["generated_answer"] == "پاسخ آزمایشی kb_grounded"
    assert grounded["parts"][0]["writer_chunk_ids"] == [ids[0]]
    assert grounded["silence_reason"] is None and grounded["needs_human"] is False
    assert PHONE not in json.dumps(doc, ensure_ascii=False)

    mixed = by_text["نمونه-ب"]
    assert mixed["decision_strategy"] == "mixed" and mixed["evidence_quality"] == "weak"
    assert mixed["parts"][0]["writer_chunk_ids"] == []

    social = by_text["نمونه-ج"]
    assert social["decision_strategy"] == "general_knowledge"
    assert social["parts"][0]["retrieval_skipped"] == e2e.SKIP_SOCIAL
    assert social["retrieved_chunk_ids"] == [] and social["evidence_quality"] == "—"
    assert social["generated_answer"] == "پاسخ آزمایشی general_knowledge"
    assert "q-social" not in [q for q, _ in fake.calls], "برای پیام اجتماعی بازیابی نشد"

    trade = by_text["نمونه-د"]
    assert trade["decision_strategy"] == "silence" and trade["silence_reason"] == "trade_advice"
    assert trade["generated_answer"] == "" and trade["needs_human"] is True

    clarify = by_text["نمونه-ه"]
    assert clarify["decision_strategy"] == "clarify"
    assert clarify["generated_answer"] == "پاسخ آزمایشی clarify"
    assert clarify["parts"][0]["writer_chunk_ids"] == []

    weak_academy = by_text["نمونه-و"]
    assert weak_academy["decision_strategy"] == "silence"
    assert weak_academy["silence_reason"] == "academy_fact_weak_evidence_unverified"
    assert weak_academy["generated_answer"] == "" and weak_academy["needs_human"] is True

    broken = by_text["نمونه-ز"]
    assert broken["understanding_error"] == "invalid_output" and broken["parts"] == []
    assert broken["silence_reason"] == "understanding_invalid_output"
    assert broken["needs_human"] is True

    # نوشتن فقط برای چهار بخشِ مجاز؛ پشتوانه‌ی بخش مستند فقط قطعه‌ی مستقیم است.
    assert len(client.stage_calls["writer"]) == 4
    grounded_prompt = next(
        u for u in client.stage_calls["writer"] if "kb_grounded" in u or "پایه‌ی پاسخ" in u
    )
    assert "SENTINEL-DIRECT" in grounded_prompt
    for other in ("SENTINEL-USEFUL", "SENTINEL-WEAK", "SENTINEL-OTHER"):
        assert other not in grounded_prompt
    for call in client.stage_calls["writer"]:
        assert PHONE not in call
    # دو مرحله‌ی مدل روی بخش‌های بازیابی‌شده: ربط شواهد برای سه بخش دارای قطعه.
    assert len(client.stage_calls["evidence"]) == 3

    assert doc["run"]["spend_by_stage_usd"].keys() == {"understanding", "evidence", "writing"}
    assert doc["run"]["spent_usd"] == pytest.approx(
        sum(doc["run"]["spend_by_stage_usd"].values()), abs=1e-5
    )
    assert any("answers_are_unreviewed" in item for item in doc["limitations"])

    shown = capsys.readouterr().out
    assert "7 پیام انتخاب شد" in shown and "سقف هزینه: 5.00 دلار" in shown
    for text in ("نمونه-", "پاسخ آزمایشی", "SENTINEL", PHONE):
        assert text not in shown
    assert "استراتژی تصمیم" in shown and "نوشتن" in shown
    assert await _snapshot(session) == before, "هیچ نوشتنی در پایگاه داده نبود"


async def test_the_whole_run_is_one_read_only_transaction(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client, _, _ = await _scenario(session, account, monkeypatch)
    _patch_client(monkeypatch, client)
    statements: list[str] = []

    def spy(conn: Any, cursor: Any, statement: str, *args: Any) -> None:
        statements.append(" ".join(statement.lower().split()))

    engine = get_engine().sync_engine
    event.listen(engine, "before_cursor_execute", spy)
    try:
        code = await cli.cmd_e2e_shadow_run(_args(tmp_path))
    finally:
        event.remove(engine, "before_cursor_execute", spy)

    assert code == 0 and statements
    assert statements[0] == "set transaction read only"
    allowed = (
        "select",
        "set transaction read only",
        "savepoint",
        "release savepoint",
        "rollback to",
    )
    for statement in statements:
        assert statement.startswith(allowed), statement


async def test_the_database_rejects_writes_in_the_transaction_the_command_opens(
    session: AsyncSession,
) -> None:
    """همان تراکنشی که فرمان باز می‌کند (`SET TRANSACTION READ ONLY`) نوشتن را رد می‌کند."""
    from sqlalchemy import text
    from sqlalchemy.exc import DBAPIError

    from mentorai.db.session import session_scope

    with pytest.raises(DBAPIError):
        async with session_scope() as guarded:
            await guarded.execute(text("SET TRANSACTION READ ONLY"))
            await guarded.execute(text("DELETE FROM knowledge_documents"))


async def test_the_review_sheet_has_one_row_per_part_with_blank_human_notes(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client, _, _ = await _scenario(session, account, monkeypatch)
    _patch_client(monkeypatch, client)

    await cli.cmd_e2e_shadow_run(_args(tmp_path))

    raw = (tmp_path / "out" / "e2e_review.csv").read_text(encoding="utf-8")
    assert raw.startswith("﻿")
    rows = list(csv.DictReader(io.StringIO(raw.lstrip("﻿"))))
    assert list(rows[0]) == list(e2e.REVIEW_COLUMNS)
    assert len(rows) == 7, "شش بخش + یک پیامِ خطای فهم"
    assert all(r["human_note"] == "" for r in rows)
    by = {r["masked_student_message"].split(":")[0]: r for r in rows}
    assert (
        by["نمونه-ب"]["writer_status"] == "written"
        and by["نمونه-د"]["writer_status"] == "not_needed"
    )
    assert (
        by["نمونه-د"]["needs_human"] == "true" and by["نمونه-د"]["silence_reason"] == "trade_advice"
    )
    assert by["نمونه-ز"]["silence_reason"] == "understanding_invalid_output"
    assert (
        by["نمونه-الف"]["retrieved_chunk_ids"] != "" and by["نمونه-ج"]["retrieved_chunk_ids"] == ""
    )
    assert by["نمونه-الف"]["fact_class"] == "academy_fact"
    assert by["نمونه-و"]["fact_class"] == "academy_fact"
    assert by["نمونه-و"]["understood_fact_class"] == "academy_fact"


async def test_dry_run_shows_the_selection_and_cap_but_calls_no_model_and_writes_nothing(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _scenario(session, account, monkeypatch)

    def must_not_be_built() -> ScriptedClient:
        raise AssertionError("در --dry-run کلاینت ساخته نمی‌شود")

    monkeypatch.setattr("mentorai.ai.providers.build_client", must_not_be_built)

    code = await cli.cmd_e2e_shadow_run(_args(tmp_path, dry_run=True, limit=3))

    assert code == 0
    shown = capsys.readouterr().out
    assert "3 پیام انتخاب شد (درخواستی: 3" in shown
    assert "سقف هزینه: 5.00 دلار" in shown and "فرض نمی‌شود" in shown
    assert "--dry-run بود: مدل صدا زده نشد و فایلی نوشته نشد." in shown
    assert not (tmp_path / "out").exists()


async def _real_numbers(session: AsyncSession) -> list[int]:
    from sqlalchemy import select

    from mentorai.db.models import Message

    rows = await session.execute(select(Message.id).order_by(Message.id))
    return [m for (m,) in rows.all()]


async def test_select_from_picks_messages_by_the_recorded_categories(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _scenario(session, account, monkeypatch)
    numbers = await _real_numbers(session)
    records = [
        _record(f"m{numbers[0]}", topic="academy_process", fact="academy_fact", strategy="silence"),
        _record(f"m{numbers[1]}", topic="other", fact="none", strategy="general_knowledge"),
        _record(f"m{numbers[2]}", topic="risk_management"),
    ]
    source = tmp_path / "ro5a.json"
    source.write_text(json.dumps({"messages": records}), encoding="utf-8")

    code = await cli.cmd_e2e_shadow_run(
        _args(tmp_path, select_from=str(source), limit=3, dry_run=True)
    )

    assert code == 0
    shown = capsys.readouterr().out
    assert "3 پیام انتخاب شد (درخواستی: 3" in shown
    assert "پوشش نمونه (از خروجی مدل)" in shown and "academy_fact: 1" in shown
    assert "social: 1" in shown and "trading: 1" in shown
    assert "کمبود پوشش" in shown
    assert "دیگر در نمونه‌ی قابل‌استفاده نبود" not in shown


async def test_select_from_warns_about_messages_that_are_no_longer_eligible(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _scenario(session, account, monkeypatch)
    numbers = await _real_numbers(session)
    records = [_record(f"m{numbers[0]}"), _record("m999999")]
    source = tmp_path / "ro5a.json"
    source.write_text(json.dumps({"messages": records}), encoding="utf-8")

    code = await cli.cmd_e2e_shadow_run(
        _args(tmp_path, select_from=str(source), limit=2, dry_run=True)
    )

    assert code == 0
    shown = capsys.readouterr().out
    assert "1 پیام انتخاب شد (درخواستی: 2" in shown
    assert "1 پیام انتخاب‌شده دیگر در نمونه‌ی قابل‌استفاده نبود" in shown


async def test_select_from_reports_missing_messages_and_bad_files(
    session: AsyncSession,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    broken = tmp_path / "b.json"
    broken.write_text("نه JSON", encoding="utf-8")
    wrong = tmp_path / "w.json"
    wrong.write_text("[]", encoding="utf-8")

    first = await cli.cmd_e2e_shadow_run(_args(tmp_path, select_from=str(tmp_path / "none.json")))
    second = await cli.cmd_e2e_shadow_run(_args(tmp_path, select_from=str(broken)))
    third = await cli.cmd_e2e_shadow_run(_args(tmp_path, select_from=str(wrong)))

    assert (first, second, third) == (1, 1, 1)
    assert capsys.readouterr().err.count("انجام نشد") == 3
    assert not (tmp_path / "out").exists()


async def test_an_empty_database_is_a_clear_message_and_no_files(
    session: AsyncSession, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    code = await cli.cmd_e2e_shadow_run(_args(tmp_path))

    assert code == 1
    assert "هیچ پیامی" in capsys.readouterr().err
    assert not (tmp_path / "out").exists()


async def test_without_a_model_nothing_runs_and_no_secret_is_printed(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _scenario(session, account, monkeypatch)

    def no_key() -> ScriptedClient:
        raise RuntimeError("no api key sk-ant-secret")

    monkeypatch.setattr("mentorai.ai.providers.build_client", no_key)

    code = await cli.cmd_e2e_shadow_run(_args(tmp_path))

    assert code == 1
    captured = capsys.readouterr()
    assert "مدل در دسترس نیست" in captured.err
    assert "sk-ant-secret" not in captured.out + captured.err
    assert not (tmp_path / "out").exists()


async def test_the_cost_cap_stops_the_run_after_the_first_measured_call_and_writes_nothing(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    client, _, _ = await _scenario(session, account, monkeypatch)
    _patch_client(monkeypatch, client)

    code = await cli.cmd_e2e_shadow_run(_args(tmp_path, max_cost_usd=1e-9))

    assert code == 1
    assert "سقف" in capsys.readouterr().err
    assert len(client.stage_calls["understanding"]) == 1
    assert client.stage_calls["evidence"] == [] and client.stage_calls["writer"] == []
    assert not (tmp_path / "out").exists()


async def test_a_writing_cost_overrun_midway_marks_the_rest_as_not_run(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client, _, _ = await _scenario(session, account, monkeypatch)
    # نوشتنِ نخست ارزان است؛ بعدی‌ها (توکن بسیار) سقف را می‌شکنند.
    calls = {"n": 0}
    original = client.raw

    async def raw(*, system: str, user: str, schema: dict[str, object]) -> RawCall:
        result = await original(system=system, user=user, schema=schema)
        if system == e2e.WRITER_SYSTEM_PROMPT:
            calls["n"] += 1
            if calls["n"] > 1:
                return dataclasses.replace(
                    result, input_tokens=50_000_000, output_tokens=50_000_000
                )
        return result

    client.raw = raw  # type: ignore[method-assign]
    _patch_client(monkeypatch, client)

    code = await cli.cmd_e2e_shadow_run(_args(tmp_path, max_cost_usd=3.0))

    assert code == 0
    doc = json.loads((tmp_path / "out" / "e2e_shadow.json").read_text(encoding="utf-8"))
    statuses = [
        p["writer_status"]
        for m in doc["messages"]
        for p in m["parts"]
        if p["writer_status"] != "not_needed"
    ]
    assert statuses.count("written") == 2 and statuses.count("not_run_cost_cap") == 2


async def test_a_writer_that_declines_leaves_no_answer_and_flags_a_human(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client, _, _ = await _scenario(session, account, monkeypatch)
    client.writer = {"kb_grounded": {"answer": "", "enough_information": False}}
    _patch_client(monkeypatch, client)

    await cli.cmd_e2e_shadow_run(_args(tmp_path))

    doc = json.loads((tmp_path / "out" / "e2e_shadow.json").read_text(encoding="utf-8"))
    declined = next(
        m
        for m in doc["messages"]
        if m["parts"] and m["parts"][0]["writer_status"] == e2e.WRITER_DECLINED
    )
    assert declined["generated_answer"] == ""
    assert declined["needs_human"] is True
    assert declined["silence_reason"] == e2e.WRITER_DECLINED


async def test_personal_data_never_reaches_the_model_or_any_output(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    key = "sk-ant-api03-SECRETVALUE-do-not-leak"
    monkeypatch.setenv("ANTHROPIC_API_KEY", key)
    client, _, _ = await _scenario(session, account, monkeypatch)
    client.writer = {
        "kb_grounded": {"answer": f"زنگ بزنید {PHONE} یا {EMAIL}", "enough_information": True}
    }
    _patch_client(monkeypatch, client)

    await cli.cmd_e2e_shadow_run(_args(tmp_path))

    everything = "\n".join(user for calls in client.stage_calls.values() for user in calls)
    for path in sorted((tmp_path / "out").rglob("*")):
        if path.is_file():
            everything += path.read_text(encoding="utf-8")
    for secret in (PHONE, EMAIL, key):
        assert secret not in everything
    assert MASK in everything


def test_max_cost_is_mandatory_and_the_command_is_registered(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = (SRC / "cli.py").read_text(encoding="utf-8")
    assert '"e2e-shadow-run"' in source and "cmd_e2e_shadow_run" in source
    monkeypatch.setattr("sys.argv", ["mentorai", "e2e-shadow-run", "--limit", "5"])
    with pytest.raises(SystemExit) as raised:
        cli.main()
    assert raised.value.code == 2, "بدون --max-cost-usd (بدون هزینه‌ی پیش‌فرض) اجرا نمی‌شود"


def test_the_default_output_folder_is_ignored_by_git() -> None:
    ignore = (SRC.parent.parent / ".gitignore").read_text(encoding="utf-8")

    assert "\ne2e/\n" in ignore


# ---------------------------------------------------------------------------
# ۸) معماری: بی‌اثر بر مسیر زنده، تلگرام و پایگاه داده
# ---------------------------------------------------------------------------


def test_e2e_cannot_send_write_or_reach_the_live_path() -> None:
    path = SRC / "ai" / "e2e_shadow.py"
    forbidden = (
        "mentorai.telegram",
        "mentorai.delivery",
        "mentorai.drafts",
        "mentorai.escalation",
        "mentorai.worker",
        "mentorai.conversation",
        "mentorai.control",
        "mentorai.jobs",
        "mentorai.ai.runtime",
        "mentorai.ai.prompt",
        "mentorai.knowledge.retrieval",
        "mentorai.db.session",
        "telethon",
    )
    imports = _imports(path)
    assert not {n for n in imports if n.startswith(forbidden)}, sorted(imports)

    tree = ast.parse(path.read_text(encoding="utf-8"))
    banned_calls = {
        "add_all",
        "commit",
        "flush",
        "delete",
        "merge",
        "begin",
        "rollback",
        "execute",
        "send_message",
        "send_file",
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            assert node.func.attr not in banned_calls, node.func.attr
            if node.func.attr == "add":
                # `set.add` برای دسته‌ها مجاز است؛ هرگز روی نشست پایگاه داده.
                receiver = node.func.value
                assert isinstance(receiver, ast.Name) and receiver.id == "found"
    names = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name)}
    assert not names & {"insert", "update", "delete", "session_scope", "sender", "gateway"}


def test_the_live_modules_do_not_know_about_the_e2e_tool_and_the_production_prompt_is_unused() -> (
    None
):
    live = (
        SRC / "ai" / "runtime.py",
        SRC / "worker.py",
        SRC / "telegram" / "gateway.py",
        SRC / "telegram" / "sender.py",
        SRC / "escalation.py",
        SRC / "drafts.py",
        SRC / "delivery.py",
        SRC / "knowledge" / "retrieval.py",
        SRC / "ai" / "understanding.py",
        SRC / "ai" / "decision_shadow.py",
        SRC / "ai" / "ro5a_shadow.py",
        SRC / "ai" / "ro5b_evidence_shadow.py",
        SRC / "understanding_replay.py",
    )
    for module in live:
        assert not any("e2e_shadow" in n for n in _imports(module)), module.name
    prompt_source = (SRC / "ai" / "e2e_shadow.py").read_text(encoding="utf-8")
    assert "production_prompt" not in prompt_source and "build_user_content" not in prompt_source


# ---------------------------------------------------------------------------
# ۹) آزمون‌های تقویت‌شده (جهش‌های زنده‌مانده)
# ---------------------------------------------------------------------------


def test_rare_categories_are_guaranteed_by_the_minimums_not_by_luck() -> None:
    """۶۰ پیام معمولی و فقط سه پیامِ هر دسته‌ی کمیاب: پر کردن تصادفی به‌تنهایی آن‌ها را نمی‌گیرد."""
    records = [_record(f"m{n}", topic="risk_management") for n in range(1, 61)]
    n = 100
    for _name, kwargs in (
        ("academy", dict(topic="academy_process", fact="academy_fact", strategy="silence")),
        ("clarify", dict(topic="metatrader_tools", fact="none", strategy="clarify")),
        ("social", dict(topic="other", fact="none", strategy="general_knowledge")),
        ("borderline", dict(scope="borderline", topic="risk_management")),
    ):
        for _ in range(3):
            n += 1
            records.append(_record(f"m{n}", **kwargs))
    categories = e2e.categorize_ro5a({"messages": records})

    for seed in range(12):
        selection = e2e.select_messages(categories, limit=12, seed=seed)
        for name in ("academy_fact", "clarification", "social", "borderline"):
            assert selection.coverage[name] >= 3, (seed, name)


def _tokens_for(usd: float) -> int:
    """توکنِ برابرِ ورودی و خروجی که با قیمت مدلِ آزمایشی دقیقاً `usd` هزینه دارد."""
    from mentorai.ai import budget

    price, _ = budget.price_for("scripted-test-only")
    return round(usd * 1_000_000 / (price.input_usd + price.output_usd))


async def test_the_writing_stage_projects_its_total_cost_after_its_first_call(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    client, _, _ = await _scenario(session, account, monkeypatch)
    # هر نوشتن ۱ دلار؛ ۴ نوشتن = ۴ دلار از سقف ۳ دلار می‌گذرد، ولی نوشتنِ نخست از سقف نمی‌گذرد.
    client.tokens = {"writer": _tokens_for(1.0)}
    _patch_client(monkeypatch, client)

    code = await cli.cmd_e2e_shadow_run(_args(tmp_path, max_cost_usd=3.0))

    assert code == 1
    assert "سقف" in capsys.readouterr().err
    assert len(client.stage_calls["writer"]) == 1, "پس از نخستین فراخوانیِ اندازه‌گیری‌شده متوقف شد"
    assert not (tmp_path / "out").exists()


async def test_each_stage_only_gets_what_the_earlier_stages_left_of_the_shared_cap(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    # فهم: ۷ فراخوانی × ۱ دلار = ۷ دلار؛ ربط شواهد: ۳ فراخوانی × ۱ دلار.
    # با سقف ۹ دلار فقط ۲ دلار برای ربط شواهد می‌ماند، پس برآورد ۳ دلار رد می‌شود.
    client, _, _ = await _scenario(session, account, monkeypatch)
    client.tokens = {"understanding": _tokens_for(1.0), "evidence": _tokens_for(1.0)}
    _patch_client(monkeypatch, client)

    code = await cli.cmd_e2e_shadow_run(_args(tmp_path, max_cost_usd=9.0))

    assert code == 1
    assert len(client.stage_calls["understanding"]) == 7
    assert len(client.stage_calls["evidence"]) == 1, "سقفِ باقی‌مانده، نه سقف کل"
    assert client.stage_calls["writer"] == []
    assert "سقف" in capsys.readouterr().err


async def test_the_writing_stage_only_gets_what_is_left_after_understanding_and_evidence(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # فهم ۷ دلار؛ نوشتن ۴ × ۱ دلار. با سقف ۹ دلار فقط ۲ دلار برای نوشتن می‌ماند.
    client, _, _ = await _scenario(session, account, monkeypatch)
    client.tokens = {"understanding": _tokens_for(1.0), "writer": _tokens_for(1.0)}
    _patch_client(monkeypatch, client)

    code = await cli.cmd_e2e_shadow_run(_args(tmp_path, max_cost_usd=9.0))

    assert code == 1
    assert len(client.stage_calls["writer"]) == 1
    assert not (tmp_path / "out").exists()


def test_multi_part_answers_are_joined_with_a_blank_line_and_gaps_are_skipped() -> None:
    def part(pid: int, answer: str) -> e2e.PartOutput:
        return e2e.PartOutput(
            part_id=pid,
            standalone_question="q",
            scope="in_domain",
            topic="other",
            understood_fact_class="none",
            fact_class="none",
            strategy="general_knowledge",
            decision_reason="r",
            needs_human=False,
            evidence_level="none",
            evidence_quality=None,
            retrieval_skipped=None,
            retrieved_chunk_ids=[],
            evaluated_chunk_ids=[],
            supporting_chunk_ids=[],
            writer_chunk_ids=[],
            generated_answer=answer,
        )

    message = e2e.MessageOutput(
        "m1", "پیام", None, None, [part(1, "الف"), part(2, ""), part(3, "ب")]
    )

    assert message.generated_answer == "الف\n\nب"


# ---------------------------------------------------------------------------
# ۱۰) قابلیت بازبینی: فیلدهای تازه فقط افزوده می‌شوند و رفتار تغییر نمی‌کند
# ---------------------------------------------------------------------------

GOLDEN = Path(__file__).parent / "data" / "e2e_golden_legacy.json"

NEW_RUN_KEYS = {"retrieval", "prompts", "code"}
NEW_MESSAGE_KEYS = {"understanding"}
NEW_PART_KEYS = {
    "writer_cost_usd",
    "search_queries",
    "retrieval",
    "evidence",
    "evidence_notes",
    "decision_corrections",
}


async def _run_scenario(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    *,
    out: str = "out",
) -> tuple[dict[str, Any], str, _Pipeline, _FakeSearch, list[int]]:
    client, fake, ids = await _scenario(session, account, monkeypatch)
    _patch_client(monkeypatch, client)
    code = await cli.cmd_e2e_shadow_run(_args(tmp_path, out=str(tmp_path / out)))
    assert code == 0
    doc = json.loads((tmp_path / out / "e2e_shadow.json").read_text(encoding="utf-8"))
    csv_text = (tmp_path / out / "e2e_review.csv").read_text(encoding="utf-8")
    return doc, csv_text, client, fake, ids


async def test_the_previous_outputs_and_the_model_inputs_are_unchanged_by_the_review_fields(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """نمونه‌ی طلایی با کدِ پیش از افزودن فیلدهای بازبینی گرفته شده (commit c8d3a66)."""
    golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
    doc, csv_text, client, _, _ = await _run_scenario(session, account, tmp_path, monkeypatch)
    doc.pop("created")

    # ورودیِ هر سه مرحله‌ی مدل کلمه‌به‌کلمه همان است: رفتار تصمیم، شواهد و نوشتن عوض نشده.
    assert client.stage_calls == golden["stage_calls"]
    # CSV بازبینی و همه‌ی کلیدهای قبلی JSON عیناً همان‌اند.
    assert csv_text == golden["csv"]
    old = golden["document"]
    assert doc["version"] == old["version"] and doc["limitations"] == old["limitations"]
    assert set(doc["run"]) == set(old["run"]) | NEW_RUN_KEYS
    assert {k: doc["run"][k] for k in old["run"]} == old["run"]
    assert len(doc["messages"]) == len(old["messages"])
    for new_message, old_message in zip(doc["messages"], old["messages"], strict=True):
        assert set(new_message) == set(old_message) | NEW_MESSAGE_KEYS
        for key in old_message:
            if key != "parts":
                assert new_message[key] == old_message[key], key
        assert len(new_message["parts"]) == len(old_message["parts"])
        for new_part, old_part in zip(new_message["parts"], old_message["parts"], strict=True):
            assert set(new_part) == set(old_part) | NEW_PART_KEYS
            assert {k: new_part[k] for k in old_part} == old_part


async def test_two_identical_runs_give_identical_documents_so_they_can_be_compared(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    first, _, client, _, _ = await _run_scenario(session, account, tmp_path, monkeypatch, out="a")
    _patch_client(monkeypatch, _Pipeline(client.routes, client.verdicts))
    assert await cli.cmd_e2e_shadow_run(_args(tmp_path, out=str(tmp_path / "b"))) == 0
    second = json.loads((tmp_path / "b" / "e2e_shadow.json").read_text(encoding="utf-8"))
    first.pop("created")
    second.pop("created")

    assert first == second


async def test_the_search_queries_and_the_retrieval_run_of_the_same_run_are_recorded(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    doc, _, _, fake, ids = await _run_scenario(session, account, tmp_path, monkeypatch)
    by_text = {m["masked_student_message"].split(":")[0]: m for m in doc["messages"]}

    academy = by_text["نمونه-الف"]["parts"][0]
    assert academy["search_queries"] == ["q-ac"]
    assert academy["retrieval"]["queries"] == [
        {"index": 1, "query": "q-ac", "hit_count": 2, "error": None}
    ]
    assert (
        academy["retrieval"]["hit_count"] == 2 and academy["retrieval"]["duplicates_removed"] == 0
    )
    first = academy["retrieval"]["hits"][0]
    assert first["chunk_id"] == ids[0] and first["source_class"] == "official"
    assert first["score"] > academy["retrieval"]["hits"][1]["score"]
    assert first["found_by"] == [{"query_index": 1, "rank": 1}]

    social = by_text["نمونه-ج"]["parts"][0]
    assert social["retrieval_skipped"] == e2e.SKIP_SOCIAL
    assert social["retrieval"]["queries"] == [] and social["retrieval"]["hits"] == []

    # عبارت‌های ذخیره‌شده دقیقاً همان‌هایی‌اند که به جست‌وجوی واقعی همان اجرا رفتند.
    searched = {
        q
        for m in doc["messages"]
        for p in m["parts"]
        if not p["retrieval_skipped"]
        for q in p["search_queries"]
    }
    assert {q for q, _ in fake.calls} == searched
    assert {
        q["query"] for m in doc["messages"] for p in m["parts"] for q in p["retrieval"]["queries"]
    } == searched


async def test_a_failed_search_query_is_recorded_with_its_error_type_only(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client, fake, _ = await _scenario(session, account, monkeypatch)
    fake.results["q-weak"] = RuntimeError(f"db down {EMAIL}")
    _patch_client(monkeypatch, client)
    assert await cli.cmd_e2e_shadow_run(_args(tmp_path)) == 0
    doc = json.loads((tmp_path / "out" / "e2e_shadow.json").read_text(encoding="utf-8"))

    part = next(
        m["parts"][0] for m in doc["messages"] if m["masked_student_message"].startswith("نمونه-و")
    )
    assert part["retrieval"]["queries"] == [
        {"index": 1, "query": "q-weak", "hit_count": 0, "error": "RuntimeError"}
    ]
    assert part["evidence"]["final"]["retrieval_errors"] == 1
    assert part["evidence"]["status"] is None or part["evidence"]["chunks"] == []
    assert EMAIL not in json.dumps(doc, ensure_ascii=False)


async def test_each_chunk_records_the_raw_model_verdict_the_final_verdict_and_every_change(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client, _, ids = await _scenario(session, account, monkeypatch)
    # ارزیاب ادعای «مستقیم» می‌کند ولی پشتیبانی نمی‌دهد؛ کد آن را به «مفید» پایین می‌آورد.
    client.verdicts[ids[0]] = ("direct", False, True, f"ادعا {PHONE}")
    _patch_client(monkeypatch, client)
    assert await cli.cmd_e2e_shadow_run(_args(tmp_path)) == 0
    doc = json.loads((tmp_path / "out" / "e2e_shadow.json").read_text(encoding="utf-8"))

    part = next(
        m["parts"][0]
        for m in doc["messages"]
        if m["masked_student_message"].startswith("نمونه-الف")
    )
    chunks = {c["chunk_id"]: c for c in part["evidence"]["chunks"]}
    lowered = chunks[ids[0]]
    assert lowered["rank"] == 1 and lowered["source_class"] == "official"
    assert lowered["authority"] == "fact" and lowered["status"] == "evaluated"
    assert lowered["model_relevance"] == "direct" and lowered["relevance"] == "useful"
    assert lowered["supports_question"] is False
    assert lowered["adjustments"] == [r5.ADJ_DIRECT_NO_SUPPORT]
    assert PHONE not in lowered["reason"] and MASK in lowered["reason"]
    other = chunks[ids[1]]
    assert other["model_relevance"] == other["relevance"] == "useful"
    assert other["adjustments"] == [] and other["supports_question"] is True
    assert isinstance(other["original_score"], float) and other["found_by"] == [
        {"query_index": 1, "rank": 2}
    ]
    assert part["evidence"]["aggregate"]["evidence_quality"] == "moderate"
    both = sorted([ids[0], ids[1]])
    assert part["evidence"]["proposal"] == {
        "level": "weak",
        "supporting_chunk_ids": both,
        "supports_part_of_question": True,
    }, "پیشنهاد واقعیِ ارزیاب به تصمیم، نه بازمحاسبه"
    assert part["evidence"]["final"]["level"] == "weak"
    assert part["evidence"]["final"]["supporting_chunk_ids"] == both
    assert part["evidence"]["final"]["supports_part_of_question"] is True
    assert part["decision_strategy"] == "mixed"
    assert part["evidence"]["cost_usd"] > 0 and part["evidence"]["status"] == "evaluated"
    assert part["writer_cost_usd"] > 0


def _unit_ro3(
    *, hits: list[dict[str, Any]], topic: str, fact_class: str, queries: tuple[str, ...]
) -> dict[str, Any]:
    doc = _ro3_doc(
        [_ro3_part("m1", 1, hits=hits, topic=topic, fact_class=fact_class, queries=queries)]
    )
    doc["messages"][0].update(
        {
            "scope_confidence": 0.5,
            "adjustments": ["queries_fallback_to_question:1", f"x {PHONE}"],
            "understanding_detail": f"bad {EMAIL}",
            "ambiguity": "none",
        }
    )
    return doc


async def _assembled(
    doc: dict[str, Any], contents: dict[int, str], verdicts: dict[int, Verdict]
) -> tuple[e2e.MessageOutput, e2e.Ro5bAssessor]:
    loaded = r5.parse_input(doc)
    judged = await r5.run_ro5b(
        loaded,
        contents,
        _Pipeline({}, verdicts),
        input_name="x",
        seed=1,
        max_parts=None,
        max_cost_usd=5.0,
    )
    assessor = e2e.Ro5bAssessor(judged.results)
    decision = ds.decide_document(doc, assessor)
    evidence = {(r.message_id, r.part_id): r for r in judged.results}
    messages, _ = e2e._assemble(doc, decision, evidence, contents, assessor)
    return messages[0], assessor


async def test_evidence_notes_and_the_proposal_show_where_the_code_lowered_the_claim() -> None:
    doc = _unit_ro3(
        hits=[_hit(1, source="mentor"), _hit(2, score=0.015)],
        topic="academy_process",
        fact_class="academy_fact",
        queries=("q1",),
    )

    message, assessor = await _assembled(doc, {1: "a", 2: "b"}, {1: ACADEMY_YES, 2: NOPE})

    part = message.parts[0]
    proposal = part.evidence_detail["proposal"]
    final = part.evidence_detail["final"]
    assert proposal == {
        "level": "strong",
        "supporting_chunk_ids": [1],
        "supports_part_of_question": False,
    }, "ارزیاب قطعه‌ی منتور را مستقیم دانسته بود"
    assert final["level"] == "weak" and final["supporting_chunk_ids"] == []
    assert final["candidate_chunk_ids"] == [2], "قطعه‌ی منتور برای واقعیت آکادمی نامزد نیست"
    assert part.evidence_notes == [
        "non_official_hits_ignored",
        "unretrieved_supporting_ids_dropped",
        "strong_without_valid_support_lowered",
    ]
    assert (
        part.strategy == "silence"
        and part.decision_reason == "academy_fact_weak_evidence_unverified"
    )
    assert assessor.proposals[("m1", 1)].level is ds.EvidenceLevel.strong


async def test_understanding_and_decision_corrections_are_recorded_and_masked() -> None:
    doc = _unit_ro3(
        hits=[_hit(1)], topic="broker_wallet", fact_class="none", queries=(f"q {EMAIL}", "q2")
    )
    doc["parts"][0]["retrieval"]["queries"][0]["query"] = f"q {EMAIL}"  # بدون ماسک در منبع

    message, _ = await _assembled(doc, {1: "a"}, {1: ACADEMY_YES})

    assert message.understanding["scope_confidence"] == 0.5
    assert message.understanding["adjustments"] == ["queries_fallback_to_question:1", f"x {MASK}"]
    assert message.understanding["detail"] == f"bad {MASK}"
    part = message.parts[0]
    assert part.decision_corrections == ["fact_class_upgraded:none->academy_fact"]
    assert part.search_queries == [f"q {MASK}", "q2"], "عبارت‌ها دوباره پوشانده می‌شوند"
    assert part.retrieval["queries"][0]["query"] == f"q {MASK}"
    assert EMAIL not in json.dumps(e2e._part_document(part), ensure_ascii=False)


async def test_a_failed_understanding_records_its_detail(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    doc, _, _, _, _ = await _run_scenario(session, account, tmp_path, monkeypatch)

    broken = next(m for m in doc["messages"] if m["understanding_error"])
    assert broken["understanding"] == {
        "scope_confidence": None,
        "adjustments": [],
        "detail": "json",
    }


def test_recording_the_assessors_proposal_does_not_change_what_it_returns() -> None:
    results: list[r5.PartResult] = []
    assessor = e2e.Ro5bAssessor(results)
    part = ds.PartInput(
        message_id="m1",
        part_id=1,
        standalone_question="q",
        scope=understanding.Scope.in_domain,
        topic=understanding.Topic.risk_management,
        fact_class=understanding.FactClass.general_knowledge,
        method_intent=understanding.MethodIntent.none,
        method_names=(),
        skipped=None,
        queries_total=1,
        query_errors=0,
        hits=(ds.HitRef(1, "official"),),
    )

    returned = assessor.assess(part, part.hits)

    assert returned == ds.EvidenceProposal(ds.EvidenceLevel.weak)
    assert assessor.proposals == {("m1", 1): returned}
    assert assessor.assess(part, ()) == ds.EvidenceProposal(ds.EvidenceLevel.none)


def test_the_prompt_manifest_gives_a_stable_version_hash_and_text_for_every_model_stage() -> None:
    import hashlib

    manifest = e2e.prompt_manifest()

    assert set(manifest) == {"understanding", "evidence", "writer"}
    assert manifest["understanding"]["version"] == understanding.UNDERSTANDING_PROMPT_VERSION
    assert manifest["evidence"]["version"] == r5.PROMPT_VERSION
    assert manifest["writer"]["version"] == e2e.WRITER_PROMPT_VERSION
    for name, text in (
        ("understanding", understanding.SYSTEM_PROMPT),
        ("evidence", r5.SYSTEM_PROMPT),
        ("writer", e2e.WRITER_SYSTEM_PROMPT),
    ):
        entry = manifest[name]
        assert entry["text"] == text
        assert entry["sha256"] == hashlib.sha256(text.encode("utf-8")).hexdigest()
        assert len(entry["schema_sha256"]) == 64
    assert manifest["writer"]["mode_brief"] == dict(e2e.MODE_BRIEF)
    assert manifest == e2e.prompt_manifest(), "پایدار: دو بار یک نتیجه"
    assert len({manifest[n]["sha256"] for n in manifest}) == 3


def test_a_changed_prompt_or_schema_changes_its_hash(monkeypatch: pytest.MonkeyPatch) -> None:
    before = e2e.prompt_manifest()

    monkeypatch.setattr(e2e, "WRITER_SYSTEM_PROMPT", e2e.WRITER_SYSTEM_PROMPT + "\nقانون تازه")
    monkeypatch.setattr(r5, "JSON_SCHEMA", {**r5.JSON_SCHEMA, "title": "x"})
    monkeypatch.setitem(e2e.MODE_BRIEF, "clarify", "دستور دیگر")
    after = e2e.prompt_manifest()

    assert after["writer"]["sha256"] != before["writer"]["sha256"]
    assert after["evidence"]["schema_sha256"] != before["evidence"]["schema_sha256"]
    assert after["writer"]["mode_brief_sha256"] != before["writer"]["mode_brief_sha256"]
    assert after["understanding"] == before["understanding"]


def test_the_stored_prompts_contain_no_personal_data() -> None:
    """دستورها ثابت‌اند و چیزی برای ماسک ندارند؛ اگر روزی داشتند، این آزمون می‌شکند."""
    for entry in e2e.prompt_manifest().values():
        assert mask_text(entry["text"]) == entry["text"]
        for value in entry.get("mode_brief", {}).values():
            assert mask_text(value) == value


async def test_the_run_records_the_prompts_and_the_retrieval_settings(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    doc, _, _, _, _ = await _run_scenario(session, account, tmp_path, monkeypatch)

    assert doc["run"]["prompts"] == e2e.prompt_metadata()
    assert doc["run"]["retrieval"]["embedder"] == "none (text only)"
    assert doc["run"]["retrieval"]["source_classes"] == ["official", "mentor"]
    assert doc["run"]["retrieval"]["limit_per_query"] == 8


async def test_no_knowledge_base_text_or_title_enters_the_new_fields(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    doc, _, _, _, _ = await _run_scenario(session, account, tmp_path, monkeypatch)

    text = json.dumps(doc, ensure_ascii=False)
    assert "SENTINEL" not in text, "متن قطعه‌های پایگاه دانش ذخیره نمی‌شود"
    assert "سند " not in text, "عنوان قطعه‌ها ذخیره نمی‌شود"
    for message in doc["messages"]:
        for part in message["parts"]:
            for hit in part["retrieval"]["hits"]:
                assert "title" not in hit and "content_preview" not in hit
            for chunk in part["evidence"]["chunks"]:
                assert "title" not in chunk and "content_preview" not in chunk
    assert PHONE not in text


def test_the_review_sheet_columns_and_the_terminal_summary_are_untouched() -> None:
    assert e2e.REVIEW_COLUMNS == (
        "message_id",
        "part_id",
        "masked_student_message",
        "standalone_question",
        "decision_strategy",
        "decision_reason",
        "fact_class",
        "understood_fact_class",
        "topic",
        "scope",
        "retrieved_chunk_ids",
        "evidence_quality",
        "evidence_level",
        "writer_chunk_ids",
        "generated_answer",
        "writer_status",
        "needs_human",
        "silence_reason",
        "human_note",
    )


def test_a_chunk_detail_masks_the_reason_even_if_the_source_did_not() -> None:
    chunk = r5.ChunkResult(
        chunk_id=5,
        rank=2,
        original_score=0.0161,
        source_class="mentor",
        authority="guidance",
        title="عنوان محرمانه",
        found_by=((1, 2),),
        content_preview="متن محرمانه",
        status=r5.CHUNK_EVALUATED,
        model_relevance=r5.Relevance.direct,
        relevance=r5.Relevance.useful,
        supports_question=False,
        academy_fact_supported=False,
        reason=f"تماس {PHONE}",
        adjustments=(r5.ADJ_DIRECT_NO_SUPPORT,),
    )

    detail = e2e._chunk_detail(chunk)

    assert detail["reason"] == f"تماس {MASK}"
    assert detail == {
        "rank": 2,
        "chunk_id": 5,
        "source_class": "mentor",
        "authority": "guidance",
        "original_score": 0.0161,
        "found_by": [{"query_index": 1, "rank": 2}],
        "status": "evaluated",
        "model_relevance": "direct",
        "relevance": "useful",
        "supports_question": False,
        "academy_fact_supported": False,
        "reason": f"تماس {MASK}",
        "adjustments": [r5.ADJ_DIRECT_NO_SUPPORT],
    }, "عنوان و متن قطعه هرگز وارد خروجی نمی‌شود"


# ---------------------------------------------------------------------------
# ۱۱) دستورها بیرون از JSON، اثر انگشت کد، و قفل نسخه‌ی دستورها
# ---------------------------------------------------------------------------

PINS = Path(__file__).parent / "data" / "e2e_prompt_pins.json"
_PIN_KEYS = ("version", "sha256", "schema_sha256", "mode_brief_sha256")


def prompt_pin_problems(current: dict[str, Any], pins: dict[str, Any]) -> list[str]:
    """تغییرِ دستور (متن، شِما یا دستور حالت‌ها) بدون تغییر نسخه، یا بدون به‌روز کردن قفل."""
    problems: list[str] = []
    for stage, pin in pins.items():
        now = {k: current[stage][k] for k in _PIN_KEYS if k in current[stage]}
        if now == pin:
            continue
        changed = [k for k in pin if k != "version" and now.get(k) != pin[k]]
        if changed and now["version"] == pin["version"]:
            problems.append(f"{stage}: {', '.join(changed)} عوض شد ولی نسخه بالا نرفت")
        else:
            problems.append(f"{stage}: قفل tests/data/e2e_prompt_pins.json به‌روز نشده")
    problems += [f"{stage}: مرحله‌ی تازه بدون قفل" for stage in current if stage not in pins]
    return problems


def test_a_prompt_change_without_a_version_bump_is_detected() -> None:
    pins = json.loads(PINS.read_text(encoding="utf-8"))

    assert prompt_pin_problems(e2e.prompt_metadata(), pins) == [], (
        "اگر عمداً دستوری را عوض کردی: نسخه‌اش را بالا ببر و قفل را به‌روز کن"
    )


def test_the_pin_check_catches_every_kind_of_silent_change(monkeypatch: pytest.MonkeyPatch) -> None:
    pins = json.loads(PINS.read_text(encoding="utf-8"))

    monkeypatch.setattr(e2e, "WRITER_SYSTEM_PROMPT", e2e.WRITER_SYSTEM_PROMPT + " قانون تازه")
    text = prompt_pin_problems(e2e.prompt_metadata(), pins)
    monkeypatch.undo()
    monkeypatch.setattr(r5, "JSON_SCHEMA", {**r5.JSON_SCHEMA, "title": "x"})
    schema = prompt_pin_problems(e2e.prompt_metadata(), pins)
    monkeypatch.undo()
    monkeypatch.setitem(e2e.MODE_BRIEF, "clarify", "دستور دیگر")
    modes = prompt_pin_problems(e2e.prompt_metadata(), pins)
    monkeypatch.undo()
    monkeypatch.setattr(und, "SYSTEM_PROMPT", und.SYSTEM_PROMPT + " ")
    understanding_text = prompt_pin_problems(e2e.prompt_metadata(), pins)
    monkeypatch.undo()
    # نسخه بالا رفته ولی قفل به‌روز نشده
    monkeypatch.setattr(e2e, "WRITER_PROMPT_VERSION", "writer-v2")
    stale = prompt_pin_problems(e2e.prompt_metadata(), pins)

    assert text == ["writer: sha256 عوض شد ولی نسخه بالا نرفت"]
    assert schema == ["evidence: schema_sha256 عوض شد ولی نسخه بالا نرفت"]
    assert modes == ["writer: mode_brief_sha256 عوض شد ولی نسخه بالا نرفت"]
    assert understanding_text == ["understanding: sha256 عوض شد ولی نسخه بالا نرفت"]
    assert stale == ["writer: قفل tests/data/e2e_prompt_pins.json به‌روز نشده"]


async def test_the_json_has_no_prompt_text_only_versions_hashes_and_file_names(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    doc, _, _, _, _ = await _run_scenario(session, account, tmp_path, monkeypatch)

    raw = (tmp_path / "out" / "e2e_shadow.json").read_text(encoding="utf-8")
    for text in (und.SYSTEM_PROMPT, r5.SYSTEM_PROMPT, e2e.WRITER_SYSTEM_PROMPT):
        assert text[:60] not in raw and text[-60:] not in raw
    for brief in e2e.MODE_BRIEF.values():
        assert brief not in raw
    for stage, entry in doc["run"]["prompts"].items():
        assert "text" not in entry and "mode_brief" not in entry, stage
        assert set(entry) >= {"version", "sha256", "schema_sha256", "file", "schema_file"}
        assert entry["file"] == f"prompts/{entry['sha256']}.txt"
        assert entry["schema_file"] == f"prompts/{entry['schema_sha256']}.json"
    writer = doc["run"]["prompts"]["writer"]
    assert writer["mode_brief_file"] == f"prompts/{writer['mode_brief_sha256']}.json"


async def test_each_prompt_is_written_once_as_a_private_file_named_by_its_hash(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import hashlib

    doc, _, _, _, _ = await _run_scenario(session, account, tmp_path, monkeypatch)

    folder = tmp_path / "out" / "prompts"
    files = sorted(folder.iterdir())
    # سه دستور، سه شِما و یک دستور حالت‌ها؛ فارغ از اینکه چند پیام اجرا شده (۷ پیام).
    assert len(doc["messages"]) == 7 and len(files) == 7
    assert stat.S_IMODE(folder.stat().st_mode) == 0o700
    for path in files:
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
        content = path.read_bytes()
        assert hashlib.sha256(content).hexdigest() == path.stem, "نام فایل همان هش محتواست"
    # هر ارجاعِ JSON به فایلی موجود می‌رسد و محتوایش همان دستور واقعی است.
    prompts = doc["run"]["prompts"]
    assert (tmp_path / "out" / prompts["writer"]["file"]).read_text(encoding="utf-8") == (
        e2e.WRITER_SYSTEM_PROMPT
    )
    assert (tmp_path / "out" / prompts["understanding"]["file"]).read_text(encoding="utf-8") == (
        und.SYSTEM_PROMPT
    )
    assert (tmp_path / "out" / prompts["evidence"]["file"]).read_text(encoding="utf-8") == (
        r5.SYSTEM_PROMPT
    )
    modes = json.loads((tmp_path / "out" / prompts["writer"]["mode_brief_file"]).read_text("utf-8"))
    assert modes == dict(e2e.MODE_BRIEF)
    schema = json.loads((tmp_path / "out" / prompts["writer"]["schema_file"]).read_text("utf-8"))
    assert schema == e2e.WRITER_SCHEMA


def test_prompt_files_never_contain_personal_data_and_match_the_metadata() -> None:
    files = e2e.prompt_files()
    meta = e2e.prompt_metadata()

    referenced = {
        value
        for entry in meta.values()
        for key, value in entry.items()
        if key in {"file", "schema_file", "mode_brief_file"}
    }
    assert referenced == set(files)
    assert all(mask_text(content) == content for content in files.values())


def test_the_code_fingerprint_names_each_file_and_hashes_its_real_bytes() -> None:
    import hashlib

    fingerprint = e2e.code_fingerprint()

    assert [f["file"] for f in fingerprint] == [
        "mentorai/ai/e2e_shadow.py",
        "mentorai/ai/ro5b_evidence_shadow.py",
        "mentorai/ai/decision_shadow.py",
        "mentorai/ai/retrieval_shadow.py",
        "mentorai/ai/understanding.py",
    ]
    for entry in fingerprint:
        real = SRC / entry["file"].removeprefix("mentorai/")
        assert entry["sha256"] == hashlib.sha256(real.read_bytes()).hexdigest()
        assert entry["module"] == entry["file"].removesuffix(".py").replace("/", ".")
    assert len({f["sha256"] for f in fingerprint}) == 5


def test_the_file_hash_changes_with_the_content_and_is_none_for_a_missing_file(
    tmp_path: Path,
) -> None:
    target = tmp_path / "x.py"
    target.write_text("a = 1\n", encoding="utf-8")
    first = e2e._file_sha(target)
    target.write_text("a = 2\n", encoding="utf-8")

    assert first != e2e._file_sha(target)
    assert e2e._file_sha(tmp_path / "missing.py") is None


async def test_the_run_records_the_code_fingerprint(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    doc, _, _, _, _ = await _run_scenario(session, account, tmp_path, monkeypatch)

    assert doc["run"]["code"] == e2e.code_fingerprint()
    assert all(len(entry["sha256"]) == 64 for entry in doc["run"]["code"])
