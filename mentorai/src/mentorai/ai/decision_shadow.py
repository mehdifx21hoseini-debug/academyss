"""سایه‌ی شواهد و تصمیم (`mentorai decision-shadow-run`، RO-4، ADR-048).

سؤالی که جواب می‌دهد: **با خروجی فهم v2 و نتیجه‌ی بازیابی فعلی، برای هر بخش پیام باید بر چه
اساسی پاسخ ساخته شود، یا اصلاً نباید پاسخ داده شود؟** فقط تصمیم را ثبت می‌کند. هیچ پاسخ،
سؤال روشن‌ساز یا متنی برای دانشجو نمی‌نویسد.

این ماژول **خالص** است: مدل صدا نمی‌زند، به پایگاه داده و بازیابی و تلگرام کاری ندارد، و فقط
یک سند JSON را می‌خواند: خروجی RO-3 (`retrieval_shadow.json`). برای همین مدل فهم دوباره صدا
زده نمی‌شود و هر اجرا قابل‌تکرار است. هر تصمیم یک تابع ساده از میدان‌های شمارشی (حوزه، موضوع،
نوع واقعیت، نیت روش بیرونی، ابهام، سطح شواهد) است؛ **هیچ متن آزادی** (پرسش مستقل، عبارت،
محتوای سند) در تصمیم نقش ندارد، پس مدل نمی‌تواند با متنش قاعده‌ها را دور بزند (آزمون دارد).

### ترتیب قاعده‌ها (اولی که بگیرد تصمیم نهایی است)

۱. `out_of_domain` ← سکوت، بدون انسان (فقط تحلیل).
۲. `trade_advice` ← سکوت + انسان.   ۳. `realtime` ← سکوت + انسان (ابزار لحظه‌ای نداریم).
۴. روش بیرونی با نیت `teach_request` یا `compare_request` ← سکوت + انسان.
۵. ابهام (`needs_clarification`) ← `clarify` برای همان بخشِ مبهم (§ ابهام پایین).
۶. `borderline` که موضوع و نوع واقعیتش قابل‌استفاده نیست ← سکوت + انسان (پیام نباید بی‌ردّ بماند).
۷. روش بیرونی با نیت `concept_question` ← `general_knowledge` (دلیل `external_method_concept`)،
   هرگز مستند به پایگاه دانش.
۸. ماتریس نوع واقعیت × شواهد (پایین).

### ماتریس

- `academy_fact`: قوی ← `kb_grounded`؛ ضعیف ← `mixed` (فقط اگر پشتیبانی بخشی از پرسش تأیید شده)
  وگرنه سکوت + انسان؛ بدون شواهد ← سکوت + انسان.
- `general_knowledge`: قوی ← `kb_grounded`؛ ضعیف ← `mixed`؛ بدون شواهد ← `general_knowledge`.
- `none` (در حوزه): همیشه `general_knowledge`.

`academy_fact` بدون شواهد هرگز `general_knowledge` نمی‌شود. موضوع اختصاصی آکادمی هم در این
ماژول **دوباره** به `academy_fact` ارتقا می‌یابد (دفاع دوم، مستقل از `normalize` مرحله‌ی فهم).

### سطح شواهد، و محدودیت اصلی این مرحله

بازیابی فعلی **هیچ سیگنال ربط قابل‌اتکایی ندارد**: امتیاز آن RRF و فقط ترکیب رتبه است، و
مسیر متنی هر واژه‌ی مشترک را نتیجه می‌کند. پس «`hit_count > 0`» یعنی قوی نیست. بدون اختراع
آستانه، ارزیاب پیش‌فرض (`ConservativeAssessor`) فقط دو سطح می‌دهد: `none` (هیچ نامزد) و `weak`
(نامزد هست، ربطش تأیید نشده). **`strong` با بازیابی فعلی هرگز تولید نمی‌شود**؛ ماتریس برای آن
آماده و آزموده است و وقتی ارزیاب قابل‌اتکا آمد (آستانه‌ی ربط یا مدل پیشنهاددهنده) کافی است
جای ارزیاب پیش‌فرض بنشیند. هر پیشنهاد ارزیاب را **کد** بازبینی می‌کند: فقط می‌تواند سطح را
پایین بیاورد، و `strong` بدون شناسه‌ی قطعه‌ی واقعاً بازیابی‌شده به `weak` برمی‌گردد.
برای `academy_fact` فقط قطعه‌ی `official` نامزد است (قطعه‌ی `mentor` مرجع قیمت و قانون نیست؛
قانون ۳ دستور پاسخ فعلی و §۱۳ سند طراحی).

### ابهام

`ambiguity` فقط در سطح کل پیام است و فیلد هر بخش ندارد (تصمیم مالک: بدون فیلد تازه). پس بخشِ
مبهم این‌طور شناسایی می‌شود: پیام تک‌بخشی ← همان بخش؛ پیام چندبخشی ← بخشی که `borderline` و
نوع واقعیتش `none` و موضوعش `other` است (فهم v2 بخش نامفهوم را با کلمات دانشجو بازتاب می‌دهد).
اگر چنین بخشی نبود (**مبهم، قابل‌ردیابی نیست**)، محافظه‌کارانه همه‌ی بخش‌هایی که قرار بود پاسخ
بگیرند `clarify` می‌شوند (دلیل `ambiguity_unlocalized`)؛ بخش‌هایی که قاعده‌ی ۱ تا ۴ سکوتشان کرده
همان می‌مانند.

بحران: هیچ منطق تازه‌ای نیست (خارج از RO-4).
"""

from __future__ import annotations

import enum
import json
from collections import Counter
from collections.abc import Mapping
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Protocol

from mentorai.ai.understanding import (
    ACADEMY_TOPICS,
    Ambiguity,
    FactClass,
    MethodIntent,
    Scope,
    Topic,
)
from mentorai.model_compare import CompareError, _private_dir, _write_private, mask_personal

DECISION_NAME = "decision_shadow.json"
SUMMARY_NAME = "decision_shadow_summary.txt"
DECISION_VERSION = 1
# نسخه‌ی سند RO-3 که این ماژول می‌خواند؛ آزمونی برابری آن با `retrieval_shadow` را می‌سنجد.
EXPECTED_SHADOW_VERSION = 1

LIMITATIONS = (
    "evidence_relevance_unverified: بازیابی فعلی سیگنال ربط قابل‌اتکا ندارد؛ "
    "بیشترین سطح شواهد weak است و strong تولید نمی‌شود.",
    "ambiguity_message_level: ambiguity فقط در سطح کل پیام است؛ بخش مبهم از روی الگوی "
    "borderline/none/other یا تک‌بخشی بودن حدس زده می‌شود.",
)


class DecisionError(CompareError):
    """سند ورودی معتبر نیست؛ پیام برای مالک است و هرگز مقدار ورودی را در خود ندارد."""


class Strategy(enum.StrEnum):
    kb_grounded = "kb_grounded"
    general_knowledge = "general_knowledge"
    mixed = "mixed"
    clarify = "clarify"
    silence = "silence"


class EvidenceLevel(enum.StrEnum):
    strong = "strong"
    weak = "weak"
    none = "none"


ANSWERABLE = frozenset({Strategy.kb_grounded, Strategy.general_knowledge, Strategy.mixed})

# یادداشت‌هایی که یعنی کد پیشنهاد ارزیاب را پایین آورد یا بخشی از آن را رد کرد.
OVERRIDE_NOTES = frozenset(
    {
        "level_lowered_no_candidates",
        "strong_without_valid_support_lowered",
        "unretrieved_supporting_ids_dropped",
        "partial_support_claim_rejected",
    }
)


# ---------------------------------------------------------------------------
# ورودی: ساختار بی‌طرف، ساخته‌شده از سند RO-3
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class HitRef:
    chunk_id: int
    source_class: str


@dataclass(frozen=True)
class PartInput:
    message_id: str
    part_id: int
    standalone_question: str
    scope: Scope
    topic: Topic
    fact_class: FactClass
    method_intent: MethodIntent
    method_names: tuple[str, ...]
    skipped: str | None
    queries_total: int
    query_errors: int
    hits: tuple[HitRef, ...]


@dataclass(frozen=True)
class MessageInput:
    message_id: str
    question: str
    ambiguity: Ambiguity | None
    error: str | None
    parts: tuple[PartInput, ...]


def _require(condition: bool, what: str) -> None:
    if not condition:
        raise DecisionError(f"سند RO-3 نامعتبر است: {what}")


def _enum(enum_type: type[enum.StrEnum], value: object, field_name: str) -> Any:
    try:
        return enum_type(str(value)) if isinstance(value, str) else enum_type(None)  # type: ignore[arg-type]
    except ValueError:
        # مقدار ورودی عمداً چاپ نمی‌شود.
        raise DecisionError(f"سند RO-3 نامعتبر است: مقدار «{field_name}» ناشناخته است") from None


def _part_input(raw: Mapping[str, Any]) -> PartInput:
    method = raw.get("external_method")
    retrieval = raw.get("retrieval")
    _require(isinstance(method, Mapping) and "intent" in method, "external_method")
    _require(isinstance(raw.get("part_id"), int), "part_id")
    queries: list[Mapping[str, Any]] = []
    hits: list[HitRef] = []
    if retrieval is not None:
        _require(isinstance(retrieval, Mapping), "retrieval")
        queries = list(retrieval.get("queries", []))
        _require(all(isinstance(q, Mapping) for q in queries), "queries")
        for hit in retrieval.get("hits", []):
            _require(isinstance(hit, Mapping), "hit")
            _require(isinstance(hit.get("chunk_id"), int), "chunk_id")
            _require(isinstance(hit.get("source_class"), str), "source_class")
            hits.append(HitRef(int(hit["chunk_id"]), str(hit["source_class"])))
    method_map: Mapping[str, Any] = method  # type: ignore[assignment]
    skipped = raw.get("retrieval_skipped")
    _require(skipped is None or isinstance(skipped, str), "retrieval_skipped")
    return PartInput(
        message_id=str(raw.get("message_id", "")),
        part_id=int(raw["part_id"]),
        standalone_question=str(raw.get("standalone_question", "")),
        scope=_enum(Scope, raw.get("scope"), "scope"),
        topic=_enum(Topic, raw.get("topic"), "topic"),
        fact_class=_enum(FactClass, raw.get("fact_class"), "fact_class"),
        method_intent=_enum(MethodIntent, method_map["intent"], "external_method.intent"),
        method_names=tuple(str(n) for n in method_map.get("named", [])),
        skipped=skipped,
        queries_total=len(queries),
        query_errors=sum(1 for q in queries if q.get("error") is not None),
        hits=tuple(hits),
    )


def parse_document(doc: Mapping[str, Any]) -> list[MessageInput]:
    """سند RO-3 را به ساختار ورودی تبدیل کن. هر کجا نخواند، `DecisionError` (نه حدس)."""
    _require(isinstance(doc, Mapping), "ریشه")
    _require(doc.get("version") == EXPECTED_SHADOW_VERSION, "نسخه با این ابزار نمی‌خواند")
    messages = doc.get("messages")
    parts = doc.get("parts")
    if not isinstance(messages, list) or not isinstance(parts, list):
        raise DecisionError("سند RO-3 نامعتبر است: messages یا parts")

    by_message: dict[str, list[PartInput]] = {}
    for raw in parts:
        _require(isinstance(raw, Mapping), "part")
        part = _part_input(raw)
        by_message.setdefault(part.message_id, []).append(part)

    result: list[MessageInput] = []
    for raw_message in messages:
        _require(isinstance(raw_message, Mapping), "message")
        message_id = str(raw_message.get("message_id", ""))
        ambiguity = raw_message.get("ambiguity")
        error = raw_message.get("understanding_error")
        result.append(
            MessageInput(
                message_id=message_id,
                question=str(raw_message.get("question", "")),
                ambiguity=None if ambiguity is None else _enum(Ambiguity, ambiguity, "ambiguity"),
                error=None if error is None else str(error),
                parts=tuple(by_message.pop(message_id, [])),
            )
        )
    _require(not by_message, "بخشی بدون پیام")
    return result


# ---------------------------------------------------------------------------
# شواهد
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class EvidenceProposal:
    """پیشنهاد یک ارزیاب. **فقط پیشنهاد است**؛ کد آن را بازبینی و در صورت لزوم پایین می‌آورد."""

    level: EvidenceLevel
    supporting_chunk_ids: tuple[int, ...] = ()
    supports_part_of_question: bool = False


class EvidenceAssessor(Protocol):
    def assess(self, part: PartInput, candidates: tuple[HitRef, ...]) -> EvidenceProposal: ...


class ConservativeAssessor:
    """ارزیاب پیش‌فرض: بدون سیگنال ربط، فقط `none` یا `weak`؛ هرگز `strong`.

    دلیلش در توضیح بالای فایل است. آستانه‌ای اختراع نمی‌شود.
    """

    def assess(self, part: PartInput, candidates: tuple[HitRef, ...]) -> EvidenceProposal:
        return EvidenceProposal(EvidenceLevel.weak if candidates else EvidenceLevel.none)


@dataclass(frozen=True)
class Evidence:
    level: EvidenceLevel
    supporting_chunk_ids: tuple[int, ...]
    candidate_chunk_ids: tuple[int, ...]
    hit_count: int
    supports_part_of_question: bool
    retrieval_skipped: str | None
    retrieval_errors: int
    notes: tuple[str, ...] = ()


def effective_fact_class(part: PartInput) -> FactClass:
    """نوع واقعیتِ مؤثر. موضوع اختصاصی آکادمی هرگز دانش عمومی یا «هیچ» نمی‌ماند.

    تکرار عمدیِ بازبینی `understanding.normalize` است: تصمیم نباید به درستیِ مرحله‌ی قبل تکیه کند.
    """
    if part.topic in ACADEMY_TOPICS and part.fact_class in (
        FactClass.general_knowledge,
        FactClass.none,
    ):
        return FactClass.academy_fact
    return part.fact_class


def finalize_evidence(
    part: PartInput, fact_class: FactClass, assessor: EvidenceAssessor
) -> Evidence:
    """شواهد نهایی = پیشنهاد ارزیاب، پس از بازبینی کد. کد می‌تواند پایین بیاورد، نه بالا ببرد."""
    notes: list[str] = []
    if part.skipped is not None:
        return Evidence(
            EvidenceLevel.none, (), (), 0, False, part.skipped, part.query_errors, ("skipped",)
        )

    # برای واقعیت آکادمی فقط منبع رسمی مرجع است؛ قطعه‌ی منتور قیمت و قانون را مستند نمی‌کند.
    if fact_class is FactClass.academy_fact:
        eligible = tuple(h for h in part.hits if h.source_class == "official")
        if len(eligible) != len(part.hits):
            notes.append("non_official_hits_ignored")
    else:
        eligible = part.hits
    candidate_ids = tuple(dict.fromkeys(h.chunk_id for h in eligible))

    proposal = assessor.assess(part, eligible)
    valid = set(candidate_ids)
    supporting = tuple(dict.fromkeys(c for c in proposal.supporting_chunk_ids if c in valid))
    if len(supporting) != len(set(proposal.supporting_chunk_ids)):
        notes.append("unretrieved_supporting_ids_dropped")

    level = proposal.level
    if not candidate_ids:
        if level is not EvidenceLevel.none:
            notes.append("level_lowered_no_candidates")
        level = EvidenceLevel.none
    elif level is EvidenceLevel.strong and not supporting:
        level = EvidenceLevel.weak
        notes.append("strong_without_valid_support_lowered")
    if level is EvidenceLevel.none:
        supporting = ()

    partial = (
        proposal.supports_part_of_question and level is EvidenceLevel.weak and bool(supporting)
    )
    if proposal.supports_part_of_question and not partial and level is not EvidenceLevel.strong:
        notes.append("partial_support_claim_rejected")

    return Evidence(
        level=level,
        supporting_chunk_ids=supporting,
        candidate_chunk_ids=candidate_ids,
        hit_count=len(part.hits),
        supports_part_of_question=partial,
        retrieval_skipped=None,
        retrieval_errors=part.query_errors,
        notes=tuple(notes),
    )


# ---------------------------------------------------------------------------
# تصمیم
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Decision:
    strategy: Strategy
    needs_human: bool
    reason: str


def _silence(reason: str, *, human: bool) -> Decision:
    return Decision(Strategy.silence, human, reason)


def _guard(part: PartInput, fact_class: FactClass) -> Decision | None:
    """قاعده‌های ۱ تا ۴: ایمنی. مستقل از شواهد و از هر خروجی مدل."""
    if part.scope is Scope.out_of_domain:
        return _silence("out_of_domain", human=False)
    if fact_class is FactClass.trade_advice:
        return _silence("trade_advice", human=True)
    if fact_class is FactClass.realtime:
        return _silence("realtime_unavailable", human=True)
    if part.method_intent is MethodIntent.teach_request:
        return _silence("external_method_teach_request", human=True)
    if part.method_intent is MethodIntent.compare_request:
        return _silence("external_method_compare_request", human=True)
    return None


def _clarification_plan(message: MessageInput) -> dict[int, str]:
    """کدام بخش‌ها `clarify` می‌شوند و چرا. فقط وقتی کل پیام `needs_clarification` است."""
    if message.ambiguity is not Ambiguity.needs_clarification:
        return {}
    open_parts = [p for p in message.parts if _guard(p, effective_fact_class(p)) is None]
    if not open_parts:
        return {}
    if len(message.parts) == 1:
        return {open_parts[0].part_id: "clarification_needed"}
    unresolved = [
        p
        for p in open_parts
        if p.scope is Scope.borderline
        and effective_fact_class(p) is FactClass.none
        and p.topic is Topic.other
    ]
    if unresolved:
        return {p.part_id: "clarification_unresolved_part" for p in unresolved}
    return {p.part_id: "ambiguity_unlocalized" for p in open_parts}


def _borderline_usable(part: PartInput, fact_class: FactClass) -> bool:
    return part.topic is not Topic.other and fact_class in (
        FactClass.academy_fact,
        FactClass.general_knowledge,
    )


def _matrix(part: PartInput, fact_class: FactClass, evidence: Evidence) -> Decision:
    strong = evidence.level is EvidenceLevel.strong
    weak = evidence.level is EvidenceLevel.weak
    if fact_class is FactClass.academy_fact:
        if strong:
            return Decision(Strategy.kb_grounded, False, "academy_fact_strong_evidence")
        if weak and evidence.supports_part_of_question:
            return Decision(Strategy.mixed, False, "academy_fact_weak_partially_supported")
        if weak:
            return _silence("academy_fact_weak_evidence_unverified", human=True)
        return _silence("academy_fact_no_evidence", human=True)
    if fact_class is FactClass.general_knowledge:
        if strong:
            return Decision(Strategy.kb_grounded, False, "general_knowledge_strong_evidence")
        if weak:
            return Decision(Strategy.mixed, False, "general_knowledge_weak_evidence")
        return Decision(Strategy.general_knowledge, False, "general_knowledge_no_evidence")
    if fact_class is FactClass.none:
        # در حوزه و بدون نوع واقعیت: فعلاً دانش عمومی، مستقل از شواهد.
        return Decision(
            Strategy.general_knowledge, False, "no_fact_class_default_general_knowledge"
        )
    # نوعی که هیچ قاعده‌ای نمی‌شناسد هرگز به پاسخ نمی‌رسد (شکست‌بسته).
    return _silence("unhandled_fact_class", human=True)


def decide_part(
    part: PartInput, evidence: Evidence, *, clarify_reason: str | None = None
) -> Decision:
    fact_class = effective_fact_class(part)
    guarded = _guard(part, fact_class)
    if guarded is not None:
        return guarded
    if clarify_reason is not None:
        return Decision(Strategy.clarify, False, clarify_reason)
    if part.scope is Scope.borderline and not _borderline_usable(part, fact_class):
        return _silence("borderline_scope_unclear", human=True)
    if part.method_intent is MethodIntent.concept_question and fact_class in (
        FactClass.general_knowledge,
        FactClass.none,
    ):
        return Decision(Strategy.general_knowledge, False, "external_method_concept")
    return _matrix(part, fact_class, evidence)


@dataclass(frozen=True)
class PartDecision:
    part: PartInput
    effective_fact_class: FactClass
    evidence: Evidence
    decision: Decision


@dataclass
class MessageDecision:
    message_id: str
    question: str
    ambiguity: Ambiguity | None
    error: str | None
    parts: list[PartDecision] = field(default_factory=list)

    @property
    def has_answerable_parts(self) -> bool:
        return any(p.decision.strategy in ANSWERABLE for p in self.parts)

    @property
    def has_human_required_parts(self) -> bool:
        return any(p.decision.needs_human for p in self.parts)

    @property
    def has_silent_parts(self) -> bool:
        return any(p.decision.strategy is Strategy.silence for p in self.parts)

    @property
    def has_clarify_parts(self) -> bool:
        return any(p.decision.strategy is Strategy.clarify for p in self.parts)


def decide_message(
    message: MessageInput, assessor: EvidenceAssessor | None = None
) -> MessageDecision:
    """هر بخش جداگانه تصمیم می‌گیرد؛ تنها چیز مشترک، ابهام کل پیام است."""
    assessor = assessor or ConservativeAssessor()
    result = MessageDecision(
        message_id=message.message_id,
        question=message.question,
        ambiguity=message.ambiguity,
        error=message.error,
    )
    plan = _clarification_plan(message)
    for part in message.parts:
        fact_class = effective_fact_class(part)
        evidence = finalize_evidence(part, fact_class, assessor)
        decision = decide_part(part, evidence, clarify_reason=plan.get(part.part_id))
        result.parts.append(PartDecision(part, fact_class, evidence, decision))
    return result


@dataclass
class DecisionData:
    created: str
    source_created: str
    understanding_model: str
    understanding_prompt_version: str
    embedder: str
    assessor: str
    excluded: dict[str, int]
    messages: list[MessageDecision] = field(default_factory=list)


def decide_document(
    doc: Mapping[str, Any], assessor: EvidenceAssessor | None = None
) -> DecisionData:
    """تصمیم برای کل سند RO-3. خالص است و به هیچ‌چیز بیرون از حافظه دست نمی‌زند."""
    assessor = assessor or ConservativeAssessor()
    messages = parse_document(doc)
    retrieval = doc.get("retrieval")
    return DecisionData(
        created=datetime.now(UTC).isoformat(timespec="seconds"),
        source_created=str(doc.get("created", "")),
        understanding_model=str(doc.get("understanding_model", "")),
        understanding_prompt_version=str(doc.get("understanding_prompt_version", "")),
        embedder=str(retrieval.get("embedder", "")) if isinstance(retrieval, Mapping) else "",
        assessor=type(assessor).__name__,
        excluded={str(k): int(v) for k, v in dict(doc.get("excluded") or {}).items()},
        messages=[decide_message(m, assessor) for m in messages],
    )


def load_and_decide(path: Path, assessor: EvidenceAssessor | None = None) -> DecisionData:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise DecisionError(f"{path.name} باز نشد ({type(exc).__name__})") from exc
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError:
        raise DecisionError(f"{path.name} JSON معتبر نیست") from None
    return decide_document(doc, assessor)


# ---------------------------------------------------------------------------
# خلاصه (بدون هیچ متن)
# ---------------------------------------------------------------------------


@dataclass
class Metrics:
    total_messages: int
    messages_decided: int
    understanding_errors: Counter[str]
    total_parts: int
    strategies: Counter[str]
    needs_human: int
    silence: int
    evidence_levels: Counter[str]
    academy_fact: Counter[str]
    general_knowledge: Counter[str]
    none_class: Counter[str]
    realtime: int
    trade_advice: int
    external_methods: dict[str, Counter[str]]
    clarify: int
    clarify_unlocalized: int
    out_of_domain: int
    borderline_unclear: int
    reasons: Counter[str]
    parts_with_overridden_evidence: int
    messages_answerable: int
    messages_human_required: int
    messages_silent: int

    @property
    def error_count(self) -> int:
        return sum(self.understanding_errors.values())


def compute_metrics(data: DecisionData) -> Metrics:
    parts = [p for m in data.messages for p in m.parts]
    external: dict[str, Counter[str]] = {}
    for p in parts:
        if p.part.method_intent is not MethodIntent.none:
            external.setdefault(p.part.method_intent.value, Counter())[
                p.decision.strategy.value
            ] += 1

    def by_fact(fact: FactClass) -> Counter[str]:
        return Counter(p.decision.strategy.value for p in parts if p.effective_fact_class is fact)

    return Metrics(
        total_messages=len(data.messages),
        messages_decided=sum(1 for m in data.messages if m.error is None),
        understanding_errors=Counter(m.error for m in data.messages if m.error is not None),
        total_parts=len(parts),
        strategies=Counter(p.decision.strategy.value for p in parts),
        needs_human=sum(1 for p in parts if p.decision.needs_human),
        silence=sum(1 for p in parts if p.decision.strategy is Strategy.silence),
        evidence_levels=Counter(p.evidence.level.value for p in parts),
        academy_fact=by_fact(FactClass.academy_fact),
        general_knowledge=by_fact(FactClass.general_knowledge),
        none_class=by_fact(FactClass.none),
        realtime=sum(1 for p in parts if p.effective_fact_class is FactClass.realtime),
        trade_advice=sum(1 for p in parts if p.effective_fact_class is FactClass.trade_advice),
        external_methods=external,
        clarify=sum(1 for p in parts if p.decision.strategy is Strategy.clarify),
        clarify_unlocalized=sum(1 for p in parts if p.decision.reason == "ambiguity_unlocalized"),
        out_of_domain=sum(1 for p in parts if p.part.scope is Scope.out_of_domain),
        borderline_unclear=sum(1 for p in parts if p.decision.reason == "borderline_scope_unclear"),
        reasons=Counter(p.decision.reason for p in parts),
        parts_with_overridden_evidence=sum(
            1 for p in parts if OVERRIDE_NOTES.intersection(p.evidence.notes)
        ),
        messages_answerable=sum(1 for m in data.messages if m.has_answerable_parts),
        messages_human_required=sum(1 for m in data.messages if m.has_human_required_parts),
        messages_silent=sum(1 for m in data.messages if m.has_silent_parts),
    )


def _share(count: int, total: int) -> str:
    return f"{count} ({100 * count / total:.0f}٪)" if total else f"{count}"


def _fmt(counter: Counter[str]) -> str:
    return "، ".join(f"{k}: {v}" for k, v in sorted(counter.items())) or "هیچ"


def summarise(data: DecisionData) -> str:
    """گزارش شمارشی به فارسی ساده. **هیچ متن پیام، پرسش، عبارت یا سندی در آن نیست.**"""
    m = compute_metrics(data)
    lines: list[str] = []
    add = lines.append
    add("خلاصه‌ی سایه‌ی شواهد و تصمیم (RO-4)")
    add("=" * 34)
    add(
        f"منبع: RO-3 ({data.source_created}) | مدل فهم: {data.understanding_model} | "
        f"نسخه‌ی دستور فهم: {data.understanding_prompt_version} | بازیابی: {data.embedder}"
    )
    add(f"ارزیاب شواهد: {data.assessor}")
    add("")
    add(f"total messages: {m.total_messages} (تصمیم‌گرفته‌شده: {m.messages_decided})")
    add(f"total parts: {m.total_parts}")
    add("strategy counts:")
    for strategy in Strategy:
        add(f"  {strategy.value}: {_share(m.strategies.get(strategy.value, 0), m.total_parts)}")
    add(f"needs_human count: {_share(m.needs_human, m.total_parts)}")
    add(f"silence count: {_share(m.silence, m.total_parts)}")
    add("")
    add(f"evidence levels: {_fmt(m.evidence_levels)}")
    add(
        "⚠️ محدودیت: بازیابی فعلی سیگنال ربط قابل‌اتکا ندارد؛ شواهد حداکثر weak است و "
        f"strong تولید نمی‌شود (strong: {m.evidence_levels.get('strong', 0)})."
    )
    add("")
    add(f"academy_fact decisions: {sum(m.academy_fact.values())} ({_fmt(m.academy_fact)})")
    add(
        f"general_knowledge decisions: {sum(m.general_knowledge.values())} "
        f"({_fmt(m.general_knowledge)})"
    )
    add(f"fact_class none decisions: {sum(m.none_class.values())} ({_fmt(m.none_class)})")
    add(f"realtime: {m.realtime}")
    add(f"trade_advice: {m.trade_advice}")
    if m.external_methods:
        add("external_method decisions:")
        for intent, counter in sorted(m.external_methods.items()):
            add(f"  {intent}: {sum(counter.values())} ({_fmt(counter)})")
    else:
        add("external_method decisions: هیچ")
    add(f"clarification: {m.clarify} (قابل‌ردیابی‌نشده: {m.clarify_unlocalized})")
    add(f"OOD: {m.out_of_domain}")
    add(f"borderline_scope_unclear (سکوت + انسان): {m.borderline_unclear}")
    add("")
    add(
        f"پیام‌ها: دارای بخش قابل‌پاسخ {m.messages_answerable}، نیازمند انسان "
        f"{m.messages_human_required}، دارای بخش ساکت {m.messages_silent}"
    )
    add(f"دلیل‌ها: {_fmt(m.reasons)}")
    add(
        f"errors: {m.error_count}" + (f" ({_fmt(m.understanding_errors)})" if m.error_count else "")
    )
    add("")
    add("یادآوری: این فقط تصمیم است؛ هیچ پاسخی ساخته نشد و به هیچ جای زنده وصل نیست.")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# نوشتن
# ---------------------------------------------------------------------------


def _part_document(item: PartDecision) -> dict[str, Any]:
    part, evidence, decision = item.part, item.evidence, item.decision
    return {
        "part_id": part.part_id,
        "standalone_question": mask_personal(part.standalone_question),
        "scope": part.scope.value,
        "topic": part.topic.value,
        "fact_class": part.fact_class.value,
        "effective_fact_class": item.effective_fact_class.value,
        "external_method": {
            "named": [mask_personal(n) for n in part.method_names],
            "intent": part.method_intent.value,
        },
        "evidence": {
            "level": evidence.level.value,
            "supporting_chunk_ids": list(evidence.supporting_chunk_ids),
            "candidate_chunk_ids": list(evidence.candidate_chunk_ids),
            "hit_count": evidence.hit_count,
            "supports_part_of_question": evidence.supports_part_of_question,
            "retrieval_skipped": evidence.retrieval_skipped,
            "retrieval_errors": evidence.retrieval_errors,
            "notes": list(evidence.notes),
        },
        "decision": {
            "strategy": decision.strategy.value,
            "needs_human": decision.needs_human,
            "reason": decision.reason,
        },
    }


def decision_document(data: DecisionData) -> dict[str, Any]:
    return {
        "version": DECISION_VERSION,
        "created": data.created,
        "source": {
            "retrieval_shadow_version": EXPECTED_SHADOW_VERSION,
            "created": data.source_created,
            "understanding_model": data.understanding_model,
            "understanding_prompt_version": data.understanding_prompt_version,
            "retrieval_embedder": data.embedder,
            "excluded": data.excluded,
        },
        "evidence_assessor": data.assessor,
        "limitations": list(LIMITATIONS),
        "messages": [
            {
                "message_id": m.message_id,
                "question": mask_personal(m.question),
                "ambiguity": m.ambiguity.value if m.ambiguity is not None else None,
                "understanding_error": m.error,
                "parts": [_part_document(p) for p in m.parts],
                "overall": {
                    "has_answerable_parts": m.has_answerable_parts,
                    "has_human_required_parts": m.has_human_required_parts,
                    "has_silent_parts": m.has_silent_parts,
                    "has_clarify_parts": m.has_clarify_parts,
                },
            }
            for m in data.messages
        ],
    }


def write_decision(data: DecisionData, out_dir: Path) -> dict[str, Path]:
    """دو فایل خصوصی: `decision_shadow.json` (با متن پوشانده‌شده) و خلاصه‌ی بی‌متن."""
    _private_dir(out_dir)
    paths = {"json": out_dir / DECISION_NAME, "summary": out_dir / SUMMARY_NAME}
    _write_private(paths["json"], json.dumps(decision_document(data), ensure_ascii=False, indent=2))
    _write_private(paths["summary"], summarise(data) + "\n")
    return paths


__all__ = [
    "ANSWERABLE",
    "DECISION_NAME",
    "OVERRIDE_NOTES",
    "EXPECTED_SHADOW_VERSION",
    "LIMITATIONS",
    "SUMMARY_NAME",
    "ConservativeAssessor",
    "Decision",
    "DecisionData",
    "DecisionError",
    "Evidence",
    "EvidenceAssessor",
    "EvidenceLevel",
    "EvidenceProposal",
    "HitRef",
    "MessageDecision",
    "MessageInput",
    "Metrics",
    "PartDecision",
    "PartInput",
    "Strategy",
    "compute_metrics",
    "decide_document",
    "decide_message",
    "decide_part",
    "decision_document",
    "effective_fact_class",
    "finalize_evidence",
    "load_and_decide",
    "parse_document",
    "summarise",
    "write_decision",
]
