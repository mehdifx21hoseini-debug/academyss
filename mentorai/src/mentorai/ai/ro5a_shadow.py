"""ارزیابی سایه‌ی واقعی (`mentorai ro5a-shadow-run`، RO-5A، ADR-049).

یک ابزار مستقل برای اجرای بعدی **روی سرور و با داده‌ی واقعی**:

    پیام‌های ذخیره‌شده ← فهم v2 ← سایه‌ی بازیابی ← سایه‌ی تصمیم ← گزارش ارزیابی

فقط **اجرا، جمع‌آوری، آمار، و انتخاب نمونه‌های مشکوک با قاعده‌های صریح** انجام می‌دهد. کیفیت
Claude را خودش قضاوت نمی‌کند و هیچ برچسب درستی (ground truth) نمی‌سازد؛ ستون‌های `expected_*`
در CSV خالی می‌مانند تا آدم پر کند. «مشکوک» یعنی «ارزش نگاه کردن دارد»، نه «غلط است».

هیچ مرحله‌ی تازه‌ای نیست: همان `run_retrieval_shadow` (RO-3) و `decide_document` (RO-4) صدا زده
می‌شوند و هیچ‌کدام تغییر نکرده‌اند. هیچ تولید پاسخی نیست. به پایگاه داده نمی‌نویسد.

### نمونه‌گیری
پایگاه داده برچسب دسته (ترید، ریسک، SSProX، …) ندارد، و برچسب مصنوعی نمی‌زنیم. پس نمونه فقط
**تصادفیِ دارای seed** است (`model_compare.sample_from_database`: از ۵۰۰۰ پیام متنیِ اخیر، یکتا،
طول ۸ تا ۶۰۰ نویسه، بدون گفتگوهای استثناشده). تنوع دسته‌ها تضمین نمی‌شود؛ پوشش واقعی را آمار
خروجی نشان می‌دهد و محدودیت در گزارش ثبت می‌شود.

### هزینه
تعداد پیام انتخاب‌شده پیش از هر فراخوانی چاپ می‌شود و `--max-cost-usd` **اجباری** است. هیچ
هزینه‌ی فرضی در کار نیست: بعد از نخستین فراخوانی، هزینه‌ی **اندازه‌گیری‌شده** × تعداد پیام با سقف
مقایسه می‌شود و اگر بیشتر بود، اجرا همان‌جا متوقف می‌شود (رفتار `understanding_replay`).

### حریم خصوصی
ورودی مدل و همه‌ی متن‌های خروجی پوشانده می‌شوند (شماره، ایمیل، نام کاربری). خروجی‌ها مجوز ۶۰۰
دارند. خلاصه هیچ متنی ندارد. هیچ کلید یا راز در خروجی نیست.
"""

from __future__ import annotations

import csv
import io
import json
import math
import statistics
from collections import Counter
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai import decision_shadow as ds
from mentorai.ai import retrieval_shadow as rs
from mentorai.ai.client import ModelClient
from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.model_compare import (
    Case,
    _private_dir,
    _write_private,
    mask_personal,
    safe_cell,
)

EVALUATION_NAME = "ro5a_shadow_evaluation.json"
SUMMARY_NAME = "ro5a_shadow_summary.txt"
REVIEW_NAME = "ro5a_review.csv"
EVALUATION_VERSION = 1

STATUS_MODEL_RUN = "model_run"
STATUS_MODEL_UNAVAILABLE = "model_unavailable"
STATUS_ERROR = "error"

# سقف نمونه به‌ازای هر قاعده‌ی مشکوک، تا یک قاعده‌ی پرتکرار بقیه را نپوشاند.
SUSPICIOUS_PER_RULE = 10
# «حداقل ۳۰ نمونه»: اگر مجموع کمتر بود، همه‌ی مواردِ دارای قاعده (تا سقف دو برابر) افزوده می‌شود.
SUSPICIOUS_MIN_TARGET = 30

SAMPLING_METHOD = "random_seeded"
LIMITATIONS = (
    "sampling_not_stratified: پایگاه داده برچسب دسته ندارد و برچسب مصنوعی زده نشد؛ نمونه فقط "
    "تصادفیِ دارای seed است و تنوع دسته‌ها تضمین نمی‌شود.",
    "sample_pool: فقط پیام‌های متنیِ بی‌فایل (ویس و رسانه نه)، یکتا، با طول ۸ تا ۶۰۰ نویسه.",
    "rule_messages_excluded: پیام مشمول قاعده‌ی قطعی (پول، شکایت، حساب، هویت، درخواست منتور) "
    "مثل مسیر زنده به مدل داده نمی‌شود و فقط شمرده می‌شود.",
    "suspicious_is_not_wrong: «مشکوک» با قاعده‌ی صریح انتخاب می‌شود و غلط‌بودن را ثابت نمی‌کند.",
    "no_ground_truth: هیچ برچسب درستی نیست؛ ستون‌های expected_* خالی‌اند.",
    "score_is_rank_derived: امتیاز بازیابی فعلی RRF است (ترکیب رتبه) و ربط را نمی‌سنجد.",
)

REVIEW_COLUMNS = (
    "message_id",
    "message_masked",
    "expected_scope",
    "actual_scope",
    "expected_fact_class",
    "actual_fact_class",
    "expected_part_count",
    "actual_part_count",
    "understanding_ok",
    "retrieval_ok",
    "decision_ok",
    "review_note",
)


# ---------------------------------------------------------------------------
# ساخت رکورد هر پیام
# ---------------------------------------------------------------------------


def _mask(value: Any) -> Any:
    """همه‌ی رشته‌های یک ساختار تو در تو را می‌پوشاند (دفاع دوم؛ ورودی‌ها پیشتر پوشانده شده‌اند)."""
    if isinstance(value, str):
        return mask_personal(value)
    if isinstance(value, list):
        return [_mask(v) for v in value]
    if isinstance(value, dict):
        return {k: _mask(v) for k, v in value.items()}
    return value


def assemble_records(
    ro3: Mapping[str, Any],
    decision: Mapping[str, Any],
    *,
    status_for_ok: str = STATUS_MODEL_RUN,
) -> list[dict[str, Any]]:
    """رکورد هر پیام از سند RO-3 و سند RO-4 (که از همان ساخته شده)."""
    parts_by_message: dict[str, list[Mapping[str, Any]]] = {}
    for part in ro3["parts"]:
        parts_by_message.setdefault(str(part["message_id"]), []).append(part)
    decisions = {str(m["message_id"]): m for m in decision["messages"]}

    records: list[dict[str, Any]] = []
    for message in ro3["messages"]:
        message_id = str(message["message_id"])
        error = message.get("understanding_error")
        ro3_parts = parts_by_message.get(message_id, [])
        decided = decisions.get(message_id, {})
        records.append(
            _mask(
                {
                    "message_id": message_id,
                    "student_message_masked": message.get("question", ""),
                    "understanding": {
                        "error": error,
                        "ambiguity": message.get("ambiguity"),
                        "scope_confidence": message.get("scope_confidence"),
                        "adjustments": list(message.get("adjustments", [])),
                        "parts": [
                            {
                                "part_id": p["part_id"],
                                "standalone_question": p["standalone_question"],
                                "scope": p["scope"],
                                "topic": p["topic"],
                                "fact_class": p["fact_class"],
                                "external_method": p["external_method"],
                                "search_queries": p["search_queries"],
                            }
                            for p in ro3_parts
                        ],
                    },
                    "retrieval": {
                        "parts": [
                            {
                                "part_id": p["part_id"],
                                "retrieval_skipped": p["retrieval_skipped"],
                                "has_hits": p["has_hits"],
                                "retrieval": p["retrieval"],
                            }
                            for p in ro3_parts
                        ]
                    },
                    "decision": {
                        "overall": decided.get("overall", {}),
                        "parts": [
                            {
                                "part_id": p["part_id"],
                                "effective_fact_class": p["effective_fact_class"],
                                "evidence": p["evidence"],
                                "decision": p["decision"],
                            }
                            for p in decided.get("parts", [])
                        ],
                    },
                    "evaluation_status": STATUS_ERROR if error else status_for_ok,
                }
            )
        )
    return records


def unavailable_records(cases_masked: Sequence[tuple[str, str]]) -> list[dict[str, Any]]:
    """بدون مدل: فقط پیام‌های نمونه (پوشانده‌شده) با وضعیت `model_unavailable`."""
    return [
        {
            "message_id": message_id,
            "student_message_masked": mask_personal(text),
            "understanding": None,
            "retrieval": None,
            "decision": None,
            "evaluation_status": STATUS_MODEL_UNAVAILABLE,
        }
        for message_id, text in cases_masked
    ]


# ---------------------------------------------------------------------------
# آمار
# ---------------------------------------------------------------------------


def percentile(sorted_values: Sequence[float], q: float) -> float:
    """صدک به روش nearest-rank؛ `sorted_values` مرتب و ناتهی باید باشد."""
    index = max(0, math.ceil(q * len(sorted_values)) - 1)
    return sorted_values[index]


def describe(values: Sequence[float]) -> dict[str, Any]:
    """min / max / mean / median / p90 / p95. با داده‌ی کم، صدک‌ها `None` می‌شوند (نه حدس)."""
    n = len(values)
    if n == 0:
        return {"n": 0}
    ordered = sorted(values)
    out: dict[str, Any] = {
        "n": n,
        "min": ordered[0],
        "max": ordered[-1],
        "mean": statistics.fmean(ordered),
        "median": statistics.median(ordered),
        "p90": percentile(ordered, 0.90) if n >= 10 else None,
        "p95": percentile(ordered, 0.95) if n >= 20 else None,
    }
    return out


@dataclass(frozen=True)
class PartView:
    """نمای یک بخش از همه‌ی مرحله‌ها، برای آمار و قاعده‌های مشکوک."""

    record: Mapping[str, Any]
    message_id: str
    part_id: int
    scope: str
    topic: str
    fact_class: str
    effective_fact_class: str
    intent: str
    named: tuple[str, ...]
    skipped: str | None
    hit_count: int
    scores: tuple[float, ...]
    query_errors: int
    duplicates_removed: int
    evidence_level: str
    strategy: str
    needs_human: bool
    reason: str


def part_views(records: Sequence[Mapping[str, Any]]) -> list[PartView]:
    views: list[PartView] = []
    for record in records:
        understanding, retrieval, decision = (
            record.get("understanding"),
            record.get("retrieval"),
            record.get("decision"),
        )
        if not understanding or not retrieval or not decision:
            continue
        ro3_parts = {p["part_id"]: p for p in retrieval["parts"]}
        decided = {p["part_id"]: p for p in decision["parts"]}
        for part in understanding["parts"]:
            pid = part["part_id"]
            r = ro3_parts.get(pid, {})
            d = decided.get(pid)
            if d is None:
                continue
            block = r.get("retrieval") or {}
            hits = block.get("hits", [])
            views.append(
                PartView(
                    record=record,
                    message_id=str(record["message_id"]),
                    part_id=int(pid),
                    scope=part["scope"],
                    topic=part["topic"],
                    fact_class=part["fact_class"],
                    effective_fact_class=d["effective_fact_class"],
                    intent=part["external_method"]["intent"],
                    named=tuple(part["external_method"]["named"]),
                    skipped=r.get("retrieval_skipped"),
                    hit_count=int(block.get("hit_count", 0)),
                    scores=tuple(float(h["score"]) for h in hits),
                    query_errors=sum(
                        1 for q in block.get("queries", []) if q.get("error") is not None
                    ),
                    duplicates_removed=int(block.get("duplicates_removed", 0)),
                    evidence_level=d["evidence"]["level"],
                    strategy=d["decision"]["strategy"],
                    needs_human=bool(d["decision"]["needs_human"]),
                    reason=d["decision"]["reason"],
                )
            )
    return views


def compute_stats(records: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """همه‌ی آمارهای خلاصه، از روی رکوردها (قابل‌آزمون بدون پایگاه داده و مدل)."""
    statuses = Counter(r["evaluation_status"] for r in records)
    ok = [r for r in records if r["evaluation_status"] == STATUS_MODEL_RUN]
    errors = Counter(
        r["understanding"]["error"]
        for r in records
        if r["evaluation_status"] == STATUS_ERROR and r.get("understanding")
    )
    views = part_views(records)
    n_messages = len(ok)

    confidences = [
        float(r["understanding"]["scope_confidence"])
        for r in ok
        if r["understanding"]["scope_confidence"] is not None
    ]
    bins: Counter[int] = Counter()
    for c in confidences:
        bins[min(int(c * 5), 4)] += 1  # پنج بازه‌ی ۰٫۲؛ فقط توزیع، نه آستانه
    histogram = {f"{i / 5:.1f}-{(i + 1) / 5:.1f}": bins.get(i, 0) for i in range(5)}

    retrieved = [v for v in views if v.skipped is None]
    with_hits = [v for v in retrieved if v.hit_count > 0]
    all_scores = [s for v in retrieved for s in v.scores]
    top_scores = [max(v.scores) for v in with_hits if v.scores]
    distinct = sorted(set(all_scores))

    def cross(fact: str) -> dict[str, int]:
        return dict(Counter(v.strategy for v in views if v.effective_fact_class == fact))

    academy = cross("academy_fact")
    general = cross("general_knowledge")

    return {
        "statuses": dict(statuses),
        "understanding_errors": dict(errors),
        "understanding": {
            "total_messages": n_messages,
            "total_parts": len(views),
            "average_parts_per_message": (len(views) / n_messages) if n_messages else 0.0,
            "parts_per_message": dict(Counter(str(len(r["understanding"]["parts"])) for r in ok)),
            "scope": dict(Counter(v.scope for v in views)),
            "ambiguity": dict(Counter(r["understanding"]["ambiguity"] for r in ok)),
            "fact_class": dict(Counter(v.fact_class for v in views)),
            "effective_fact_class": dict(Counter(v.effective_fact_class for v in views)),
            "topic": dict(Counter(v.topic for v in views)),
            "external_method_intent": dict(Counter(v.intent for v in views if v.intent != "none")),
            "scope_confidence": describe(confidences),
            "scope_confidence_histogram": histogram,
            "code_adjustments": dict(
                Counter(a.split(":", 1)[0] for r in ok for a in r["understanding"]["adjustments"])
            ),
        },
        "retrieval": {
            "parts_total": len(views),
            "parts_retrieved": len(retrieved),
            "parts_skipped": dict(Counter(v.skipped for v in views if v.skipped)),
            "parts_with_hits": len(with_hits),
            "parts_without_hits": len(retrieved) - len(with_hits),
            "average_hits_per_retrieved_part": (
                statistics.fmean(v.hit_count for v in retrieved) if retrieved else 0.0
            ),
            "duplicates_removed": sum(v.duplicates_removed for v in retrieved),
            "query_errors": sum(v.query_errors for v in retrieved),
            "all_hit_scores": describe(all_scores),
            "top_score_per_part": describe(top_scores),
            "distinct_score_values": len(distinct),
            "distinct_score_values_sample": [round(s, 6) for s in distinct[:5]],
            "hits_at_the_highest_score_seen": (
                sum(1 for s in all_scores if s == distinct[-1]) if distinct else 0
            ),
        },
        "decision": {
            "strategy": dict(Counter(v.strategy for v in views)),
            "needs_human": sum(1 for v in views if v.needs_human),
            "silence": sum(1 for v in views if v.strategy == "silence"),
            "clarify": sum(1 for v in views if v.strategy == "clarify"),
            "evidence_level": dict(Counter(v.evidence_level for v in views)),
            "academy_fact": {
                "kb_grounded": academy.get("kb_grounded", 0),
                "mixed": academy.get("mixed", 0),
                "silence": academy.get("silence", 0),
                "general_knowledge": academy.get("general_knowledge", 0),
                "clarify": academy.get("clarify", 0),
            },
            "general_knowledge": {
                "general_knowledge": general.get("general_knowledge", 0),
                "kb_grounded": general.get("kb_grounded", 0),
                "mixed": general.get("mixed", 0),
                "silence": general.get("silence", 0),
                "clarify": general.get("clarify", 0),
            },
            "realtime": sum(1 for v in views if v.effective_fact_class == "realtime"),
            "trade_advice": sum(1 for v in views if v.effective_fact_class == "trade_advice"),
            "external_method": {
                intent: dict(Counter(v.strategy for v in views if v.intent == intent))
                for intent in sorted({v.intent for v in views if v.intent != "none"})
            },
            "out_of_domain": sum(1 for v in views if v.scope == "out_of_domain"),
            "reasons": dict(Counter(v.reason for v in views)),
        },
    }


# ---------------------------------------------------------------------------
# نمونه‌های مشکوک (فقط قاعده‌های صریح؛ بدون قضاوت)
# ---------------------------------------------------------------------------

ANSWERABLE = {s.value for s in ds.ANSWERABLE}


def _question_marks(text: str) -> int:
    return text.count("؟") + text.count("?")


@dataclass(frozen=True)
class Rule:
    code: str
    description: str
    test: Callable[[PartView, Mapping[str, Any], int], bool]


def _rules() -> tuple[Rule, ...]:
    def parts_of(record: Mapping[str, Any]) -> list[Mapping[str, Any]]:
        return list(record["understanding"]["parts"])

    return (
        Rule(
            "academy_fact_to_general_knowledge",
            "واقعیت آکادمی با تصمیم general_knowledge (کد نباید اجازه دهد)",
            lambda v, r, n: (
                v.effective_fact_class == "academy_fact" and v.strategy == "general_knowledge"
            ),
        ),
        Rule(
            "model_said_general_on_academy_topic",
            "فهم general_knowledge/none داد ولی موضوع اختصاصی آکادمی بود (کد ارتقا داد)",
            lambda v, r, n: (
                v.fact_class != v.effective_fact_class and v.effective_fact_class == "academy_fact"
            ),
        ),
        Rule(
            "academy_fact_to_silence",
            "واقعیت آکادمی ← سکوت",
            lambda v, r, n: v.effective_fact_class == "academy_fact" and v.strategy == "silence",
        ),
        Rule(
            "general_knowledge_to_silence",
            "دانش عمومی ← سکوت",
            lambda v, r, n: (
                v.effective_fact_class == "general_knowledge" and v.strategy == "silence"
            ),
        ),
        Rule(
            "trade_advice_answerable",
            "درخواست تصمیم معاملاتی ← قابل‌پاسخ (کد نباید اجازه دهد)",
            lambda v, r, n: v.fact_class == "trade_advice" and v.strategy in ANSWERABLE,
        ),
        Rule(
            "realtime_answerable",
            "اطلاعات لحظه‌ای ← قابل‌پاسخ (کد نباید اجازه دهد)",
            lambda v, r, n: v.fact_class == "realtime" and v.strategy in ANSWERABLE,
        ),
        Rule(
            "ood_raised_by_code",
            "فهم out_of_domain داد ولی کد آن را ناسازگار دید و بالا برد",
            lambda v, r, n: (
                any(
                    a.startswith("incoherent_out_of_domain_raised")
                    for a in r["understanding"]["adjustments"]
                )
                and v.scope != "out_of_domain"
            ),
        ),
        Rule(
            "ood_inside_a_message_with_domain_parts",
            "بخش out_of_domain در پیامی که بخش‌های در/نزدیک حوزه هم دارد",
            lambda v, r, n: (
                v.scope == "out_of_domain"
                and any(p["scope"] != "out_of_domain" for p in parts_of(r))
            ),
        ),
        Rule(
            "multi_question_marks_but_one_part",
            "پیام بیش از یک نشانه‌ی پرسش دارد ولی فقط یک بخش استخراج شد",
            lambda v, r, n: n == 1 and _question_marks(r["student_message_masked"]) >= 2,
        ),
        Rule(
            "many_parts",
            "پنج بخش یا بیشتر (نزدیک سقف شش)",
            lambda v, r, n: n >= 5,
        ),
        Rule(
            "ambiguity_but_answerable_part",
            "ابهام needs_clarification ولی بخشی قابل‌پاسخ تصمیم گرفته شد (احتمال حدس)",
            lambda v, r, n: (
                r["understanding"]["ambiguity"] == "needs_clarification"
                and v.strategy in ANSWERABLE
            ),
        ),
        Rule(
            "external_method_teach_or_compare",
            "روش بیرونی با نیت آموزش یا مقایسه",
            lambda v, r, n: v.intent in ("teach_request", "compare_request"),
        ),
        Rule(
            "external_method_intent_without_name",
            "نیت روش بیرونی هست ولی هیچ نامی ثبت نشده",
            lambda v, r, n: v.intent != "none" and not v.named,
        ),
        Rule(
            "many_hits_but_weak_evidence",
            "تعداد نتیجه به سقف هر عبارت یا بیشتر رسید ولی شواهد weak است",
            lambda v, r, n: (
                v.skipped is None
                and v.hit_count >= rs.SEARCH_LIMIT_PER_QUERY
                and v.evidence_level == "weak"
            ),
        ),
        Rule(
            "no_hits_for_a_clear_in_domain_question",
            "بازیابی نتیجه‌ای نداد برای بخش در حوزه‌ی بدون ابهام",
            lambda v, r, n: (
                v.skipped is None
                and v.hit_count == 0
                and v.scope == "in_domain"
                and v.effective_fact_class in ("academy_fact", "general_knowledge")
                and r["understanding"]["ambiguity"] == "none"
            ),
        ),
        Rule(
            "borderline_unclear_silence",
            "borderline نامشخص ← سکوت + انسان",
            lambda v, r, n: v.reason == "borderline_scope_unclear",
        ),
    )


RULES = _rules()


def select_suspicious(records: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """نمونه‌های مشکوک: هر قاعده تا `SUSPICIOUS_PER_RULE`، به ترتیب اولویت، یکتا بر اساس بخش.

    اگر مجموع از `SUSPICIOUS_MIN_TARGET` کمتر ماند، باقی موارد دارای قاعده افزوده می‌شود (تا سقف
    دو برابر هدف). هیچ نمونه‌ای بدون قاعده‌ی صریح افزوده نمی‌شود.
    """
    views = part_views(records)
    per_message_parts = Counter(v.message_id for v in views)
    matches: dict[str, list[PartView]] = {}
    for rule in RULES:
        matches[rule.code] = [
            v for v in views if rule.test(v, v.record, per_message_parts[v.message_id])
        ]

    chosen: dict[tuple[str, int], dict[str, Any]] = {}

    def add(view: PartView, code: str) -> None:
        key = (view.message_id, view.part_id)
        entry = chosen.setdefault(
            key, {"message_id": view.message_id, "part_id": view.part_id, "reasons": []}
        )
        if code not in entry["reasons"]:
            entry["reasons"].append(code)

    for rule in RULES:
        for view in matches[rule.code][:SUSPICIOUS_PER_RULE]:
            add(view, rule.code)
    if len(chosen) < SUSPICIOUS_MIN_TARGET:
        for rule in RULES:
            for view in matches[rule.code][SUSPICIOUS_PER_RULE:]:
                if len(chosen) >= 2 * SUSPICIOUS_MIN_TARGET:
                    break
                add(view, rule.code)
    return {
        "rules": [
            {"code": r.code, "description": r.description, "matches": len(matches[r.code])}
            for r in RULES
        ],
        "samples": list(chosen.values()),
    }


# ---------------------------------------------------------------------------
# خروجی‌ها
# ---------------------------------------------------------------------------


@dataclass
class Evaluation:
    created: str
    model: str
    prompt_version: str
    embedder: str
    seed: int
    selected: int
    requested: int
    max_cost_usd: float
    spent_usd: float
    stopped_early: bool
    excluded: dict[str, int]
    records: list[dict[str, Any]] = field(default_factory=list)

    @property
    def model_available(self) -> bool:
        return any(r["evaluation_status"] != STATUS_MODEL_UNAVAILABLE for r in self.records)


def evaluation_document(ev: Evaluation) -> dict[str, Any]:
    suspicious = select_suspicious(ev.records)
    by_key = {(s["message_id"], s["part_id"]): s["reasons"] for s in suspicious["samples"]}
    return {
        "version": EVALUATION_VERSION,
        "created": ev.created,
        "run": {
            "understanding_model": ev.model,
            "understanding_prompt_version": ev.prompt_version,
            "retrieval_embedder": ev.embedder,
            "sampling": SAMPLING_METHOD,
            "seed": ev.seed,
            "requested": ev.requested,
            "selected": ev.selected,
            "max_cost_usd": ev.max_cost_usd,
            "spent_usd": round(ev.spent_usd, 6),
            "stopped_early": ev.stopped_early,
            "excluded_by_deterministic_rules": ev.excluded,
        },
        "limitations": list(LIMITATIONS),
        "messages": ev.records,
        "suspicious": {
            "rules": suspicious["rules"],
            "samples": [
                {**s, "reasons": by_key[(s["message_id"], s["part_id"])]}
                for s in suspicious["samples"]
            ],
        },
    }


def _share(count: int, total: int) -> str:
    return f"{count} ({100 * count / total:.0f}٪)" if total else f"{count}"


def _fmt(counter: Mapping[str, int]) -> str:
    return "، ".join(f"{k}: {v}" for k, v in sorted(counter.items())) or "هیچ"


def _stat_line(label: str, d: Mapping[str, Any]) -> str:
    if d.get("n", 0) == 0:
        return f"  {label}: داده‌ای نیست"

    def f(key: str) -> str:
        value = d.get(key)
        return "—(داده کم)" if value is None else f"{value:.6f}"

    return (
        f"  {label}: n={d['n']} min={f('min')} max={f('max')} mean={f('mean')} "
        f"median={f('median')} p90={f('p90')} p95={f('p95')}"
    )


def render_summary(ev: Evaluation) -> str:
    """خلاصه‌ی شمارشی. **بدون هیچ متن پیام**؛ فقط شناسه، کد قاعده و عدد."""
    stats = compute_stats(ev.records)
    suspicious = select_suspicious(ev.records)
    u, r, d = stats["understanding"], stats["retrieval"], stats["decision"]
    lines: list[str] = []
    add = lines.append
    add("خلاصه‌ی ارزیابی سایه‌ی واقعی (RO-5A)")
    add("=" * 36)
    add(f"تاریخ: {ev.created} | مدل فهم: {ev.model} | نسخه‌ی دستور فهم: {ev.prompt_version}")
    add(f"بازیابی: {ev.embedder} | نمونه‌گیری: {SAMPLING_METHOD} (seed={ev.seed})")
    add(f"درخواستی: {ev.requested} | انتخاب‌شده: {ev.selected}")
    add(
        f"سقف هزینه: {ev.max_cost_usd:.2f} دلار | هزینه‌ی واقعی: {ev.spent_usd:.4f} دلار"
        + (" | ⚠️ به سقف خورد و زودتر تمام شد" if ev.stopped_early else "")
    )
    add(f"کنار گذاشته (قاعده‌ی قطعی، به مدل نرفت): {_fmt(ev.excluded)}")
    add(f"وضعیت پیام‌ها: {_fmt(stats['statuses'])}")
    if not ev.model_available:
        add("")
        add("⚠️ model_unavailable: مدل در دسترس نبود (کلید/پیکربندی). ارزیابی مدل انجام نشد.")
        add("فقط نمونه‌گیری و پوشاندن اجرا شد؛ هیچ آماری از فهم، بازیابی یا تصمیم نیست.")
    else:
        add(f"خطای فهم: {_fmt(stats['understanding_errors'])}")
        add("")
        add("── فهم (Understanding)")
        add(f"total messages: {u['total_messages']}")
        add(f"total parts: {u['total_parts']}")
        add(f"average parts/message: {u['average_parts_per_message']:.2f}")
        add(f"parts per message: {_fmt(u['parts_per_message'])}")
        add(f"scope: {_fmt(u['scope'])}")
        add(f"ambiguity: {_fmt(u['ambiguity'])}")
        add(f"fact_class (فهم): {_fmt(u['fact_class'])}")
        add(f"fact_class (مؤثر، پس از ارتقای کد): {_fmt(u['effective_fact_class'])}")
        add(f"external_method intents: {_fmt(u['external_method_intent'])}")
        add(f"topic: {_fmt(u['topic'])}")
        add(f"اصلاح‌های کدی روی خروجی مدل: {_fmt(u['code_adjustments'])}")
        add("scope_confidence:")
        add(_stat_line("توزیع", u["scope_confidence"]))
        add(f"  بازه‌ها: {_fmt(u['scope_confidence_histogram'])}")
        add("")
        add("── بازیابی (Retrieval)")
        add(f"parts retrieved: {r['parts_retrieved']} از {r['parts_total']}")
        add(f"skipped: {_fmt(r['parts_skipped'])}")
        add(f"with hits: {_share(r['parts_with_hits'], r['parts_retrieved'])}")
        add(f"without hits: {_share(r['parts_without_hits'], r['parts_retrieved'])}")
        add(f"average hits (روی بخش‌های بازیابی‌شده): {r['average_hits_per_retrieved_part']:.2f}")
        add(f"duplicate removal count: {r['duplicates_removed']}")
        add(f"retrieval errors (عبارت): {r['query_errors']}")
        add("score distribution (امتیاز RRF):")
        add(_stat_line("همه‌ی نتیجه‌ها", r["all_hit_scores"]))
        add(_stat_line("بالاترین امتیاز هر بخش", r["top_score_per_part"]))
        add(
            f"  مقدار متمایز امتیاز: {r['distinct_score_values']} "
            f"(نمونه: {r['distinct_score_values_sample']}) | "
            f"نتیجه‌های دارای بالاترین امتیازِ دیده‌شده: {r['hits_at_the_highest_score_seen']}"
        )
        add(
            "  ⚠️ فقط اندازه‌گیری: امتیاز ترکیب رتبه است. بدون برچسب ربط انسانی نمی‌شود گفت "
            "جداکردن relevant از irrelevant ممکن است یا نه."
        )
        add("")
        add("── تصمیم (Decision)")
        add(f"strategy: {_fmt(d['strategy'])}")
        add(f"needs_human: {d['needs_human']}")
        add(f"silence: {d['silence']}")
        add(f"clarify: {d['clarify']}")
        add(f"evidence levels: {_fmt(d['evidence_level'])}")
        ac, gk = d["academy_fact"], d["general_knowledge"]
        add(f"academy_fact → kb_grounded: {ac['kb_grounded']}")
        add(f"academy_fact → mixed: {ac['mixed']}")
        add(f"academy_fact → silence: {ac['silence']}")
        add(f"academy_fact → general_knowledge: {ac['general_knowledge']}")
        add(f"academy_fact → clarify: {ac['clarify']}")
        add(f"general_knowledge → general_knowledge: {gk['general_knowledge']}")
        add(
            f"general_knowledge → kb_grounded / mixed / silence / clarify: "
            f"{gk['kb_grounded']} / {gk['mixed']} / {gk['silence']} / {gk['clarify']}"
        )
        add(f"realtime: {d['realtime']}")
        add(f"trade_advice: {d['trade_advice']}")
        add(
            "external_method decisions: "
            + ("، ".join(f"{k}: {_fmt(v)}" for k, v in d["external_method"].items()) or "هیچ")
        )
        add(f"OOD: {d['out_of_domain']}")
        add(f"دلیل‌ها: {_fmt(d['reasons'])}")

        add("")
        add("── نمونه‌های مشکوک (قاعده‌ی صریح؛ متن فقط در JSON/CSV خصوصی)")
        samples = suspicious["samples"]
        add(f"تعداد نمونه: {len(samples)} (هدف حداقل {SUSPICIOUS_MIN_TARGET} اگر وجود داشت)")
        for rule in suspicious["rules"]:
            add(f"  {rule['code']}: {rule['matches']} مورد — {rule['description']}")
        for s in samples:
            add(f"  {s['message_id']}#{s['part_id']}: {', '.join(s['reasons'])}")

    add("")
    add("محدودیت‌ها:")
    lines.extend(f"  - {item}" for item in LIMITATIONS)
    add("")
    add("یادآوری: این ابزار کیفیت Claude را قضاوت نمی‌کند؛ ground truth را آدم روی نمونه‌ها می‌گذارد.")
    return "\n".join(lines)


def render_review_csv(ev: Evaluation) -> str:
    """یک ردیف برای هر پیام. `expected_*` و `*_ok` عمداً خالی‌اند؛ ground truth را آدم می‌گذارد."""
    suspicious = select_suspicious(ev.records)
    flagged: dict[str, list[str]] = {}
    for sample in suspicious["samples"]:
        flagged.setdefault(sample["message_id"], []).extend(sample["reasons"])

    ordered = sorted(
        ev.records, key=lambda rec: (rec["message_id"] not in flagged, str(rec["message_id"]))
    )
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(REVIEW_COLUMNS)
    for record in ordered:
        understanding = record.get("understanding")
        parts = understanding["parts"] if understanding else []
        reasons = list(dict.fromkeys(flagged.get(record["message_id"], [])))
        writer.writerow(
            [
                safe_cell(str(record["message_id"])),
                safe_cell(record["student_message_masked"]),
                "",
                safe_cell("|".join(p["scope"] for p in parts)),
                "",
                safe_cell("|".join(p["fact_class"] for p in parts)),
                "",
                len(parts) if understanding else "",
                "",
                "",
                "",
                safe_cell(
                    ("auto-flag: " + ", ".join(reasons) + " | " if reasons else "")
                    + f"status={record['evaluation_status']}"
                ),
            ]
        )
    return buffer.getvalue()


def write_outputs(ev: Evaluation, out_dir: Path) -> dict[str, Path]:
    """سه فایل خصوصی (مجوز ۶۰۰)."""
    _private_dir(out_dir)
    paths = {
        "json": out_dir / EVALUATION_NAME,
        "summary": out_dir / SUMMARY_NAME,
        "csv": out_dir / REVIEW_NAME,
    }
    _write_private(paths["json"], json.dumps(evaluation_document(ev), ensure_ascii=False, indent=2))
    _write_private(paths["summary"], render_summary(ev) + "\n")
    # BOM: اکسل بدون آن فارسی را خراب می‌خواند.
    _write_private(paths["csv"], "﻿" + render_review_csv(ev))
    return paths


# ---------------------------------------------------------------------------
# اجرا
# ---------------------------------------------------------------------------


async def run_ro5a(
    session: AsyncSession,
    cases: Sequence[Case],
    client: ModelClient | None,
    *,
    embedder: EmbeddingProvider | None,
    seed: int,
    requested: int,
    max_cost_usd: float,
    progress: Callable[[str], None] | None = None,
) -> Evaluation:
    """فهم ← بازیابی ← تصمیم برای نمونه. فقط می‌خواند. `client=None` یعنی مدل در دسترس نیست."""
    if client is None:
        probe = await rs.run_retrieval_shadow(session, cases, None, dry_run=True)
        return Evaluation(
            created=datetime.now(UTC).isoformat(timespec="seconds"),
            model="—",
            prompt_version=probe.prompt_version,
            embedder=probe.embedder,
            seed=seed,
            selected=len(cases),
            requested=requested,
            max_cost_usd=max_cost_usd,
            spent_usd=0.0,
            stopped_early=False,
            excluded=dict(probe.excluded),
            records=unavailable_records([(c.id, c.question) for c in cases]),
        )

    shadow = await rs.run_retrieval_shadow(
        session,
        cases,
        client,
        embedder=embedder,
        max_cost_usd=max_cost_usd,
        progress=progress,
    )
    ro3 = rs.shadow_document(shadow)
    decided = ds.decision_document(ds.decide_document(ro3))
    return Evaluation(
        created=shadow.created,
        model=shadow.model,
        prompt_version=shadow.prompt_version,
        embedder=shadow.embedder,
        seed=seed,
        selected=len(cases),
        requested=requested,
        max_cost_usd=max_cost_usd,
        spent_usd=shadow.spent_usd,
        stopped_early=shadow.stopped_early,
        excluded=dict(shadow.excluded),
        records=assemble_records(ro3, decided),
    )


__all__ = [
    "EVALUATION_NAME",
    "REVIEW_COLUMNS",
    "REVIEW_NAME",
    "RULES",
    "STATUS_ERROR",
    "STATUS_MODEL_RUN",
    "STATUS_MODEL_UNAVAILABLE",
    "SUMMARY_NAME",
    "Evaluation",
    "assemble_records",
    "compute_stats",
    "describe",
    "evaluation_document",
    "render_review_csv",
    "render_summary",
    "run_ro5a",
    "select_suspicious",
    "unavailable_records",
    "write_outputs",
]
