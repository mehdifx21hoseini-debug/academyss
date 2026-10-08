"""ارزیابی سایه‌ی واقعی RO-5A: اجرا، آمار، نمونه‌های مشکوک، خروجی‌ها و نبودِ اثر جانبی.

هیچ‌کدام به API واقعی نیاز ندارند. مدل فهم `ScriptedClient`/`_Router` است، پس این تست‌ها
**کیفیت Claude را نمی‌سنجند**؛ لوله‌کشی، آمار، قاعده‌های نمونه‌ی مشکوک و ایمنی خروجی را می‌سنجند.
"""

from __future__ import annotations

import ast
import csv
import io
import json
import stat
from argparse import Namespace
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession
from tests import test_retrieval_shadow as _rs_tests
from tests.test_retrieval_shadow import _fake_hit, _FakeSearch, _install, _message, _Router
from tests.test_understanding import SRC, _imports, _part, _payload
from tests.test_understanding_replay import _snapshot

from mentorai import cli
from mentorai.ai import ro5a_shadow as r5
from mentorai.ai.client import ScriptedClient
from mentorai.db.models import MentorAccount

kb = _rs_tests.kb
embedder = _rs_tests.embedder

PHONE = "09121234567"
EMAIL = "student@example.com"


# ---------------------------------------------------------------------------
# رکورد ساختگی برای آزمون‌های خالص
# ---------------------------------------------------------------------------


def _rec(
    mid: str,
    parts: list[dict[str, Any]] | None = None,
    *,
    text: str = "پیام نمونه",
    ambiguity: str = "none",
    adjustments: tuple[str, ...] = (),
    status: str = r5.STATUS_MODEL_RUN,
    error: str | None = None,
) -> dict[str, Any]:
    specs = parts if parts is not None else [{}]
    u_parts, r_parts, d_parts = [], [], []
    for i, spec in enumerate(specs, start=1):
        scope = spec.get("scope", "in_domain")
        fact = spec.get("fact", "general_knowledge")
        eff = spec.get("eff", fact)
        scores = spec.get("scores", [])
        skipped = spec.get("skipped")
        u_parts.append(
            {
                "part_id": i,
                "standalone_question": "پرسش",
                "scope": scope,
                "topic": spec.get("topic", "risk_management"),
                "fact_class": fact,
                "external_method": {
                    "named": list(spec.get("named", [])),
                    "intent": spec.get("intent", "none"),
                },
                "search_queries": ["q"],
            }
        )
        r_parts.append(
            {
                "part_id": i,
                "retrieval_skipped": skipped,
                "has_hits": bool(scores),
                "retrieval": None
                if skipped
                else {
                    "hit_count": len(scores),
                    "duplicates_removed": spec.get("dups", 0),
                    "queries": [
                        {
                            "index": 1,
                            "query": "q",
                            "hit_count": len(scores),
                            "error": spec.get("err"),
                        }
                    ],
                    "hits": [
                        {"chunk_id": 100 + j, "score": s, "source_class": "official"}
                        for j, s in enumerate(scores)
                    ],
                },
            }
        )
        d_parts.append(
            {
                "part_id": i,
                "effective_fact_class": eff,
                "evidence": {"level": spec.get("level", "weak")},
                "decision": {
                    "strategy": spec.get("strategy", "mixed"),
                    "needs_human": spec.get("human", False),
                    "reason": spec.get("reason", "r"),
                },
            }
        )
    return {
        "message_id": mid,
        "student_message_masked": text,
        "understanding": {
            "error": error,
            "ambiguity": ambiguity,
            "scope_confidence": 0.9,
            "adjustments": list(adjustments),
            "parts": u_parts,
        },
        "retrieval": {"parts": r_parts},
        "decision": {"overall": {}, "parts": d_parts},
        "evaluation_status": status,
    }


def _evaluation(records: list[dict[str, Any]], **overrides: Any) -> r5.Evaluation:
    values: dict[str, Any] = {
        "created": "2026-10-08T00:00:00+00:00",
        "model": "scripted-test-only",
        "prompt_version": "understand-v2",
        "embedder": "none (text only)",
        "seed": 7,
        "selected": len(records),
        "requested": len(records),
        "max_cost_usd": 1.0,
        "spent_usd": 0.0,
        "stopped_early": False,
        "excluded": {},
        "records": records,
    }
    values.update(overrides)
    return r5.Evaluation(**values)


# ---------------------------------------------------------------------------
# آمار
# ---------------------------------------------------------------------------


def test_score_statistics_report_percentiles_only_with_enough_data() -> None:
    assert r5.describe([]) == {"n": 0}
    small = r5.describe([0.3, 0.1, 0.2])
    assert (small["n"], small["min"], small["max"], small["median"]) == (3, 0.1, 0.3, 0.2)
    assert small["mean"] == pytest.approx(0.2)
    assert small["p90"] is None and small["p95"] is None, "داده‌ی کم ← صدک حدس زده نمی‌شود"

    values = [float(i) for i in range(1, 101)]
    big = r5.describe(values)
    assert (big["min"], big["max"], big["median"]) == (1.0, 100.0, 50.5)
    assert (big["p90"], big["p95"]) == (90.0, 95.0), "nearest-rank"


def test_the_statistics_are_exact_on_a_known_set_of_records() -> None:
    records = [
        _rec(
            "m1",
            [
                {
                    "topic": "academy_policy",
                    "fact": "academy_fact",
                    "scores": [0.0328, 0.0161],
                    "strategy": "silence",
                    "human": True,
                    "dups": 1,
                    "level": "weak",
                },
                {"scores": [0.0164], "strategy": "mixed"},
            ],
        ),
        _rec(
            "m2",
            [
                {
                    "fact": "trade_advice",
                    "skipped": "trade_advice",
                    "strategy": "silence",
                    "human": True,
                    "level": "none",
                }
            ],
        ),
        _rec(
            "m3",
            [
                {
                    "scope": "out_of_domain",
                    "topic": "other",
                    "fact": "none",
                    "skipped": "out_of_domain",
                    "strategy": "silence",
                    "level": "none",
                }
            ],
        ),
        _rec("m4", [], error="invalid_output", status=r5.STATUS_ERROR),
        _rec(
            "m5",
            [
                {
                    "scores": [],
                    "strategy": "general_knowledge",
                    "level": "none",
                    "err": "RuntimeError",
                }
            ],
            ambiguity="resolved_by_context",
        ),
    ]

    s = r5.compute_stats(records)

    assert s["statuses"] == {"model_run": 4, "error": 1}
    assert s["understanding_errors"] == {"invalid_output": 1}
    u, r, d = s["understanding"], s["retrieval"], s["decision"]
    assert (u["total_messages"], u["total_parts"]) == (4, 5)
    assert u["average_parts_per_message"] == pytest.approx(1.25)
    assert u["scope"] == {"in_domain": 4, "out_of_domain": 1}
    assert u["ambiguity"] == {"none": 3, "resolved_by_context": 1}
    assert (r["parts_retrieved"], r["parts_skipped"]) == (
        3,
        {"trade_advice": 1, "out_of_domain": 1},
    )
    assert (r["parts_with_hits"], r["parts_without_hits"]) == (2, 1)
    assert r["average_hits_per_retrieved_part"] == pytest.approx(1.0)
    assert (r["duplicates_removed"], r["query_errors"]) == (1, 1)
    assert r["all_hit_scores"]["n"] == 3 and r["all_hit_scores"]["max"] == 0.0328
    assert r["top_score_per_part"]["n"] == 2
    assert r["distinct_score_values"] == 3 and r["hits_at_the_highest_score_seen"] == 1
    assert d["strategy"] == {"silence": 3, "mixed": 1, "general_knowledge": 1}
    assert (d["needs_human"], d["silence"], d["clarify"]) == (2, 3, 0)
    assert d["academy_fact"] == {
        "kb_grounded": 0,
        "mixed": 0,
        "silence": 1,
        "general_knowledge": 0,
        "clarify": 0,
    }
    assert d["general_knowledge"]["general_knowledge"] == 1 and d["general_knowledge"]["mixed"] == 1
    assert (d["trade_advice"], d["realtime"], d["out_of_domain"]) == (1, 0, 1)


def test_model_unavailable_records_produce_no_quality_statistics() -> None:
    records = r5.unavailable_records([("m1", f"پیام از {PHONE}"), ("m2", "دیگر")])

    stats = r5.compute_stats(records)
    summary = r5.render_summary(_evaluation(records, model="—"))

    assert stats["statuses"] == {"model_unavailable": 2}
    assert stats["understanding"]["total_parts"] == 0
    assert "model_unavailable" in summary and "ارزیابی مدل انجام نشد" in summary
    assert "total parts" not in summary, "هیچ آماری از فهم/بازیابی/تصمیم ساخته نمی‌شود"
    assert PHONE not in json.dumps(records, ensure_ascii=False)


# ---------------------------------------------------------------------------
# نمونه‌های مشکوک
# ---------------------------------------------------------------------------

_CASES: list[tuple[str, list[dict[str, Any]], dict[str, Any], str]] = [
    (
        "academy_fact_to_general_knowledge",
        [{"fact": "academy_fact", "strategy": "general_knowledge"}],
        {},
        "m",
    ),
    (
        "model_said_general_on_academy_topic",
        [{"fact": "general_knowledge", "eff": "academy_fact", "strategy": "silence"}],
        {},
        "m",
    ),
    ("academy_fact_to_silence", [{"fact": "academy_fact", "strategy": "silence"}], {}, "m"),
    ("general_knowledge_to_silence", [{"strategy": "silence"}], {}, "m"),
    ("trade_advice_answerable", [{"fact": "trade_advice", "strategy": "mixed"}], {}, "m"),
    ("realtime_answerable", [{"fact": "realtime", "strategy": "general_knowledge"}], {}, "m"),
    (
        "ood_raised_by_code",
        [{"scope": "borderline"}],
        {"adjustments": ("incoherent_out_of_domain_raised:1",)},
        "m",
    ),
    (
        "ood_inside_a_message_with_domain_parts",
        [{"scope": "out_of_domain", "topic": "other", "fact": "none"}, {}],
        {},
        "m",
    ),
    ("multi_question_marks_but_one_part", [{}], {"text": "اول؟ دوم؟"}, "m"),
    ("many_parts", [{}] * 5, {}, "m"),
    (
        "ambiguity_but_answerable_part",
        [{"strategy": "mixed"}],
        {"ambiguity": "needs_clarification"},
        "m",
    ),
    (
        "external_method_teach_or_compare",
        [{"intent": "teach_request", "named": ["SMC"], "strategy": "silence"}],
        {},
        "m",
    ),
    (
        "external_method_intent_without_name",
        [{"intent": "concept_question", "strategy": "general_knowledge"}],
        {},
        "m",
    ),
    ("many_hits_but_weak_evidence", [{"scores": [0.01] * 8, "level": "weak"}], {}, "m"),
    (
        "no_hits_for_a_clear_in_domain_question",
        [{"scores": [], "strategy": "general_knowledge", "level": "none"}],
        {},
        "m",
    ),
    (
        "borderline_unclear_silence",
        [{"scope": "borderline", "reason": "borderline_scope_unclear", "strategy": "silence"}],
        {},
        "m",
    ),
]


@pytest.mark.parametrize(("code", "parts", "extra", "mid"), _CASES, ids=[c[0] for c in _CASES])
def test_each_suspicious_rule_flags_its_case_with_the_reason(
    code: str, parts: list[dict[str, Any]], extra: dict[str, Any], mid: str
) -> None:
    result = r5.select_suspicious([_rec(mid, parts, **extra)])

    flagged = {reason for s in result["samples"] for reason in s["reasons"]}
    assert code in flagged
    assert {r["code"] for r in result["rules"]} >= {c[0] for c in _CASES}


def test_a_perfectly_ordinary_part_is_not_flagged() -> None:
    plain = _rec("m1", [{"scores": [0.0164], "strategy": "mixed", "level": "weak"}])

    assert r5.select_suspicious([plain])["samples"] == []


def test_the_rules_are_ordered_by_the_owners_priority_list() -> None:
    codes = [rule.code for rule in r5.RULES]

    assert codes.index("academy_fact_to_general_knowledge") < codes.index("academy_fact_to_silence")
    assert codes.index("academy_fact_to_silence") < codes.index("general_knowledge_to_silence")
    assert codes.index("general_knowledge_to_silence") < codes.index("trade_advice_answerable")
    assert codes.index("realtime_answerable") < codes.index("ood_raised_by_code")
    assert codes.index("no_hits_for_a_clear_in_domain_question") > codes.index(
        "many_hits_but_weak_evidence"
    )


def test_no_rule_is_capped_below_the_target_and_each_rule_is_capped_when_there_is_plenty() -> None:
    # چهار قاعده، هرکدام ۱۵ مورد: دور اول ۴×۱۰ = ۴۰ ≥ ۳۰ و دور دوم لازم نیست.
    records = []
    for i in range(15):
        records.append(_rec(f"a{i:02}", [{"fact": "academy_fact", "strategy": "silence"}]))
        records.append(_rec(f"g{i:02}", [{"strategy": "silence"}]))
        records.append(_rec(f"t{i:02}", [{"fact": "trade_advice", "strategy": "mixed"}]))
        records.append(_rec(f"r{i:02}", [{"fact": "realtime", "strategy": "mixed"}]))

    result = r5.select_suspicious(records)

    per_rule = {r["code"]: r["matches"] for r in result["rules"]}
    assert per_rule["academy_fact_to_silence"] == 15
    assert len(result["samples"]) == 40
    for code in (
        "academy_fact_to_silence",
        "general_knowledge_to_silence",
        "trade_advice_answerable",
        "realtime_answerable",
    ):
        assert sum(code in s["reasons"] for s in result["samples"]) == r5.SUSPICIOUS_PER_RULE


def test_too_few_flags_are_topped_up_only_with_flagged_cases() -> None:
    flagged = [
        _rec(f"a{i:02}", [{"fact": "academy_fact", "strategy": "silence"}]) for i in range(14)
    ]
    ordinary = [_rec(f"o{i}", [{"scores": [0.0164], "level": "weak"}]) for i in range(40)]

    result = r5.select_suspicious(flagged + ordinary)

    assert len(result["samples"]) == 14, "همه‌ی ۱۴ مورد دارای قاعده، و هیچ نمونه‌ی بدون قاعده"
    assert all(s["message_id"].startswith("a") for s in result["samples"])


def test_a_part_matching_several_rules_is_listed_once_with_every_reason() -> None:
    both = _rec(
        "m1",
        [{"fact": "academy_fact", "strategy": "silence", "reason": "borderline_scope_unclear"}],
    )

    samples = r5.select_suspicious([both])["samples"]

    assert len(samples) == 1
    assert {"academy_fact_to_silence", "borderline_unclear_silence"} <= set(samples[0]["reasons"])


def test_the_top_up_never_goes_beyond_twice_the_target() -> None:
    many = [_rec(f"a{i:03}", [{"fact": "academy_fact", "strategy": "silence"}]) for i in range(90)]

    result = r5.select_suspicious(many)

    assert len(result["samples"]) == 2 * r5.SUSPICIOUS_MIN_TARGET
    assert (
        next(r for r in result["rules"] if r["code"] == "academy_fact_to_silence")["matches"] == 90
    )


def test_the_no_hit_rule_ignores_a_part_of_an_ambiguous_message() -> None:
    quiet = _rec(
        "m1",
        [{"scores": [], "strategy": "clarify", "level": "none"}],
        ambiguity="needs_clarification",
    )

    codes = {r for s in r5.select_suspicious([quiet])["samples"] for r in s["reasons"]}

    assert "no_hits_for_a_clear_in_domain_question" not in codes


def test_the_highest_score_count_counts_ties_at_the_top() -> None:
    records = [_rec("m1", [{"scores": [0.0328, 0.0328, 0.0161]}])]

    retrieval = r5.compute_stats(records)["retrieval"]

    assert retrieval["hits_at_the_highest_score_seen"] == 2
    assert retrieval["distinct_score_values"] == 2


def test_assembling_records_masks_even_if_an_earlier_stage_did_not() -> None:
    ro3 = {
        "messages": [
            {
                "message_id": "m1",
                "question": f"تماس {PHONE} {EMAIL}",
                "understanding_error": None,
                "ambiguity": "none",
                "scope_confidence": 0.9,
                "adjustments": [],
            }
        ],
        "parts": [
            {
                "message_id": "m1",
                "part_id": 1,
                "standalone_question": f"شماره {PHONE}",
                "scope": "in_domain",
                "topic": "other",
                "fact_class": "none",
                "external_method": {"named": [EMAIL], "intent": "none"},
                "search_queries": [f"q {EMAIL}"],
                "retrieval_skipped": None,
                "has_hits": False,
                "retrieval": None,
            }
        ],
    }
    decision = {"messages": [{"message_id": "m1", "overall": {}, "parts": []}]}

    dumped = json.dumps(r5.assemble_records(ro3, decision), ensure_ascii=False)

    assert PHONE not in dumped and EMAIL not in dumped and "[حذف‌شده]" in dumped


def test_flagged_messages_come_first_in_the_review_csv_even_when_their_id_sorts_last() -> None:
    records = [
        _rec("a-ordinary", [{"scores": [0.0164]}]),
        _rec("z-flagged", [{"fact": "academy_fact", "strategy": "silence"}]),
    ]

    text = r5.render_review_csv(_evaluation(records)).lstrip("﻿")

    assert [r["message_id"] for r in csv.DictReader(io.StringIO(text))] == [
        "z-flagged",
        "a-ordinary",
    ]


# ---------------------------------------------------------------------------
# خلاصه و CSV
# ---------------------------------------------------------------------------


def test_the_summary_has_the_agreed_numbers_and_never_a_message_text() -> None:
    secret = "راز-پیام-۷۷۱"
    records = [
        _rec(
            "m1",
            [
                {
                    "topic": "academy_policy",
                    "fact": "academy_fact",
                    "scores": [0.0328, 0.0161],
                    "strategy": "silence",
                    "human": True,
                }
            ],
            text=f"{secret} {PHONE}",
        ),
        _rec("m2", [{"scores": [0.0164], "strategy": "mixed"}]),
    ]
    summary = r5.render_summary(_evaluation(records, excluded={"rule_money": 2}, spent_usd=0.0123))

    for expected in (
        "total messages: 2",
        "total parts: 2",
        "average parts/message: 1.00",
        "scope:",
        "ambiguity:",
        "fact_class",
        "external_method intents:",
        "parts retrieved: 2 از 2",
        "with hits:",
        "without hits:",
        "average hits",
        "duplicate removal count:",
        "retrieval errors",
        "score distribution",
        "strategy:",
        "needs_human: 1",
        "academy_fact → kb_grounded: 0",
        "academy_fact → mixed: 0",
        "academy_fact → silence: 1",
        "general_knowledge → general_knowledge: 0",
        "realtime:",
        "trade_advice:",
        "OOD:",
        "rule_money: 2",
        "0.0123",
        "نمونه‌های مشکوک",
    ):
        assert expected in summary, expected
    assert secret not in summary and PHONE not in summary and "پیام نمونه" not in summary
    assert "m1#1" in summary, "فقط شناسه و کد قاعده"


def test_the_review_csv_has_the_exact_columns_and_never_invents_ground_truth() -> None:
    records = [
        _rec("m1", [{"fact": "academy_fact", "strategy": "silence"}, {}], text="=HYPERLINK(1)"),
        _rec("m2", [{"scores": [0.0164]}], text="عادی"),
    ]

    text = r5.render_review_csv(_evaluation(records)).lstrip("﻿")
    rows = list(csv.DictReader(io.StringIO(text)))

    assert tuple(rows[0]) == r5.REVIEW_COLUMNS
    assert [r["message_id"] for r in rows] == ["m1", "m2"], "مشکوک‌ها اول"
    for row in rows:
        for column in (
            "expected_scope",
            "expected_fact_class",
            "expected_part_count",
            "understanding_ok",
            "retrieval_ok",
            "decision_ok",
        ):
            assert row[column] == "", column
    assert rows[0]["actual_scope"] == "in_domain|in_domain"
    assert rows[0]["actual_part_count"] == "2"
    assert rows[0]["message_masked"].startswith("'="), "فرمول اکسل خنثی می‌شود"
    assert "auto-flag: academy_fact_to_silence" in rows[0]["review_note"]


# ---------------------------------------------------------------------------
# اجرا روی پایگاه داده (مدل و بازیابی ساختگی)
# ---------------------------------------------------------------------------


def _args(tmp_path: Path, **overrides: object) -> Namespace:
    values: dict[str, object] = {
        "from_db": 50,
        "seed": 7,
        "max_cost_usd": 1.0,
        "out": str(tmp_path / "out"),
        "dry_run": False,
    }
    values.update(overrides)
    return Namespace(**values)


async def _seed(session: AsyncSession, account: MentorAccount, bodies: list[str]) -> None:
    for n, body in enumerate(bodies, start=1):
        await _message(session, account, body, n)


def _patch_client(monkeypatch: pytest.MonkeyPatch, client: ScriptedClient) -> None:
    monkeypatch.setattr("mentorai.ai.providers.build_client", lambda: client)


async def test_an_empty_database_gives_a_clear_message_and_no_files(
    session: AsyncSession, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    code = await cli.cmd_ro5a_shadow_run(_args(tmp_path))

    assert code == 1
    assert "هیچ پیامی" in capsys.readouterr().err
    assert not (tmp_path / "out").exists()


async def test_sampling_is_seeded_and_respects_the_limit(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _seed(session, account, [f"سؤال شماره {n} درباره ریسک" for n in range(1, 21)])

    await cli.cmd_ro5a_shadow_run(_args(tmp_path, from_db=5, seed=1, dry_run=True))
    first = capsys.readouterr().out
    await cli.cmd_ro5a_shadow_run(_args(tmp_path, from_db=5, seed=1, dry_run=True))
    again = capsys.readouterr().out
    await cli.cmd_ro5a_shadow_run(_args(tmp_path, from_db=100, seed=1, dry_run=True))
    everything = capsys.readouterr().out

    assert "5 پیام انتخاب شد" in first and first == again
    assert "20 پیام انتخاب شد" in everything, "سقف نمونه، تعداد موجود است"
    assert "سقف هزینه: 1.00 دلار" in first and "فرض نمی‌شود" in first
    assert not (tmp_path / "out").exists(), "--dry-run چیزی نمی‌نویسد"

    from mentorai import model_compare as mc

    a = [c.id for c in await mc.sample_from_database(session, limit=5, seed=1)]
    b = [c.id for c in await mc.sample_from_database(session, limit=5, seed=1)]
    c = [c.id for c in await mc.sample_from_database(session, limit=5, seed=2)]
    assert a == b and a != c


def _scenario_router() -> _Router:
    return _Router(
        {
            "نمونه-الف": _payload(
                _part(
                    1,
                    "شرایط ثبت‌نام چیست؟",
                    topic="academy_policy",
                    fact_class="academy_fact",
                    queries=("q-ac",),
                ),
                _part(2, "ریسک چیست؟", queries=("q-gk",)),
            ),
            "نمونه-ب": _payload(
                _part(1, "الان بخرم؟", topic="trading_education", fact_class="trade_advice")
            ),
            "نمونه-ج": _payload(
                _part(1, "غذا", scope="out_of_domain", topic="other", fact_class="none")
            ),
            "نمونه-د": "این JSON نیست",
            "نمونه-ه": _payload(_part(1, "مفهوم", queries=("q-none",))),
        }
    )


_BODIES = [
    "نمونه-الف: دو بخش دارد",
    "نمونه-ب: سیگنال",
    "نمونه-ج: بی‌ربط",
    "نمونه-د: خراب",
    "نمونه-ه: بدون نتیجه",
]


def _fake_results() -> _FakeSearch:
    return _FakeSearch(
        {
            "q-ac": [_fake_hit(1, score=0.0328), _fake_hit(2, score=0.0161)],
            "q-gk": [_fake_hit(3, score=0.0164)],
        }
    )


async def test_the_full_run_writes_three_private_files_with_the_agreed_content(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _seed(session, account, _BODIES)
    _install(monkeypatch, _fake_results())
    _patch_client(monkeypatch, _scenario_router())
    before = await _snapshot(session)

    code = await cli.cmd_ro5a_shadow_run(_args(tmp_path))

    assert code == 0
    out = tmp_path / "out"
    assert sorted(p.name for p in out.iterdir()) == [
        "ro5a_review.csv",
        "ro5a_shadow_evaluation.json",
        "ro5a_shadow_summary.txt",
    ]
    for path in out.iterdir():
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
    doc = json.loads((out / "ro5a_shadow_evaluation.json").read_text(encoding="utf-8"))
    assert doc["run"]["sampling"] == "random_seeded" and doc["run"]["selected"] == 5
    assert any("sampling_not_stratified" in item for item in doc["limitations"])
    by_text = {m["student_message_masked"].split(":")[0]: m for m in doc["messages"]}
    ok = by_text["نمونه-الف"]
    assert ok["evaluation_status"] == "model_run"
    assert [p["scope"] for p in ok["understanding"]["parts"]] == ["in_domain", "in_domain"]
    assert ok["retrieval"]["parts"][0]["retrieval"]["hit_count"] == 2
    assert [p["decision"]["strategy"] for p in ok["decision"]["parts"]] == ["silence", "mixed"]
    assert by_text["نمونه-د"]["evaluation_status"] == "error"
    assert by_text["نمونه-د"]["understanding"]["error"] == "invalid_output"
    assert {
        "message_id",
        "student_message_masked",
        "understanding",
        "retrieval",
        "decision",
        "evaluation_status",
    } <= set(ok)

    summary = (out / "ro5a_shadow_summary.txt").read_text(encoding="utf-8")
    assert "total messages: 4" in summary and "total parts: 5" in summary
    assert "academy_fact → silence: 1" in summary and "academy_fact → kb_grounded: 0" in summary
    assert "general_knowledge → general_knowledge: 1" in summary
    for body in _BODIES:
        assert body not in summary
    assert "5 پیام انتخاب شد" in capsys.readouterr().out
    assert await _snapshot(session) == before, "هیچ نوشتنی در پایگاه داده نبود"


async def test_without_a_model_the_run_does_not_stop_and_marks_the_sample(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _seed(session, account, [f"سؤال شماره {n} با {EMAIL}" for n in range(1, 4)])

    def no_key() -> None:
        raise RuntimeError("no api key configured")

    monkeypatch.setattr("mentorai.ai.providers.build_client", no_key)

    code = await cli.cmd_ro5a_shadow_run(_args(tmp_path))

    assert code == 0
    assert "مدل در دسترس نیست" in capsys.readouterr().err
    doc = json.loads((tmp_path / "out" / "ro5a_shadow_evaluation.json").read_text(encoding="utf-8"))
    assert [m["evaluation_status"] for m in doc["messages"]] == ["model_unavailable"] * 3
    assert all(m["understanding"] is None for m in doc["messages"])
    everything = "".join(p.read_text(encoding="utf-8") for p in (tmp_path / "out").iterdir())
    assert EMAIL not in everything and "no api key" not in everything


async def test_the_cost_cap_stops_the_run_after_the_first_measured_call(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _seed(session, account, [f"سؤال شماره {n} درباره ریسک" for n in range(1, 9)])
    _install(monkeypatch, _FakeSearch())
    client = _Router({"سؤال": _payload(_part(1, "سؤال"))})
    _patch_client(monkeypatch, client)

    code = await cli.cmd_ro5a_shadow_run(_args(tmp_path, max_cost_usd=1e-9))

    assert code == 1
    assert "سقف" in capsys.readouterr().err
    assert len(client.calls) == 1, "پس از نخستین فراخوانیِ اندازه‌گیری‌شده متوقف شد"
    assert not (tmp_path / "out").exists()


async def test_personal_data_never_reaches_any_output_and_no_secret_is_written(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    secret_key = "sk-ant-api03-SECRETVALUE-do-not-leak"
    monkeypatch.setenv("ANTHROPIC_API_KEY", secret_key)
    await _seed(
        session,
        account,
        [f"نمونه-الف: شماره من {PHONE} و ایمیل {EMAIL} و آیدی @student_name"],
    )
    _install(monkeypatch, _fake_results())
    router = _Router(
        {"نمونه-الف": _payload(_part(1, f"تماس {PHONE} {EMAIL}", queries=("q-gk", f"q {EMAIL}")))}
    )
    _patch_client(monkeypatch, router)

    await cli.cmd_ro5a_shadow_run(_args(tmp_path))

    everything = "".join(p.read_text(encoding="utf-8") for p in (tmp_path / "out").iterdir())
    for private in (PHONE, EMAIL, "@student_name", secret_key, "SECRETVALUE"):
        assert private not in everything, private
    assert "[حذف‌شده]" in everything
    assert all(private not in router.calls[0][1] for private in (PHONE, EMAIL, "@student_name"))


async def test_rule_messages_are_counted_but_never_sent_to_the_model(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    await _seed(session, account, ["رسید واریزم رو فرستادم چی شد؟", "نمونه-ه: بدون نتیجه"])
    _install(monkeypatch, _FakeSearch())
    router = _scenario_router()
    _patch_client(monkeypatch, router)

    await cli.cmd_ro5a_shadow_run(_args(tmp_path))

    assert len(router.calls) == 1
    doc = json.loads((tmp_path / "out" / "ro5a_shadow_evaluation.json").read_text(encoding="utf-8"))
    assert doc["run"]["excluded_by_deterministic_rules"] == {"rule_money": 1}
    assert "rule_money: 1" in (tmp_path / "out" / "ro5a_shadow_summary.txt").read_text(
        encoding="utf-8"
    )


def test_max_cost_is_mandatory_and_the_command_is_registered(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = (SRC / "cli.py").read_text(encoding="utf-8")
    assert '"ro5a-shadow-run"' in source and "cmd_ro5a_shadow_run" in source
    monkeypatch.setattr("sys.argv", ["mentorai", "ro5a-shadow-run", "--from-db", "10"])
    with pytest.raises(SystemExit) as raised:
        cli.main()
    assert raised.value.code == 2, "بدون --max-cost-usd (بدون هزینه‌ی پیش‌فرض) اجرا نمی‌شود"


# ---------------------------------------------------------------------------
# معماری
# ---------------------------------------------------------------------------


def test_ro5a_cannot_send_write_or_reach_the_live_path() -> None:
    path = SRC / "ai" / "ro5a_shadow.py"
    forbidden = (
        "mentorai.telegram",
        "mentorai.delivery",
        "mentorai.drafts",
        "mentorai.escalation",
        "mentorai.worker",
        "mentorai.conversation",
        "mentorai.control",
        "mentorai.jobs",
        "mentorai.db",
        "mentorai.ai.runtime",
        "mentorai.knowledge.retrieval",
    )
    assert not {n for n in _imports(path) if n.startswith(forbidden)}, sorted(_imports(path))

    tree = ast.parse(path.read_text(encoding="utf-8"))
    calls = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert not calls & {"add", "add_all", "execute", "commit", "flush", "delete", "merge", "begin"}

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
        SRC / "ai" / "retrieval_shadow.py",
        SRC / "ai" / "decision_shadow.py",
        SRC / "understanding_replay.py",
    )
    for module in live:
        assert not any("ro5a" in n for n in _imports(module)), module.name


def test_the_evaluation_record_shape_is_json_serialisable_and_stable() -> None:
    doc = r5.evaluation_document(_evaluation([_rec("m1")]))

    json.dumps(doc, ensure_ascii=False)
    assert doc["version"] == r5.EVALUATION_VERSION
    assert set(doc) == {"version", "created", "run", "limitations", "messages", "suspicious"}
