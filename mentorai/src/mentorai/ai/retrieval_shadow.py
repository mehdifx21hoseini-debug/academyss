"""سایه‌ی بازیابی (`mentorai retrieval-shadow-run`، RO-3، ADR-047).

سؤالی که جواب می‌دهد: **وقتی مرحله‌ی فهم (`understand-v2`) به بازیابی فعلی وصل شود، برای هر بخش
پیام چه عبارت‌هایی ساخته می‌شود و چه اسنادی از پایگاه دانش برمی‌گردد؟** فقط اندازه‌گیری است؛
هیچ چیز را بهتر نمی‌کند.

جریان برای هر پیام ذخیره‌شده:

1. `understanding_replay.run_replay` (دست‌نخورده): پوشاندن اطلاعات شخصی، حذف پیام مشمول قاعده‌ی
   قطعی، ساخت زمینه، فراخوانی `understand`، سقف هزینه.
2. برای هر بخش، **بدون هیچ تصمیمی از خودم**: بخش `out_of_domain` و `realtime` و `trade_advice`
   بازیابی نمی‌شوند و فقط وضعیتشان گزارش می‌شود (`retrieval_skipped`)؛ بقیه (از جمله `borderline`،
   `academy_fact` و `none`) همه‌ی `search_queries`شان را **یکی‌یکی** به `knowledge.retrieval.search`
   فعلی می‌دهند، با همان پارامترهای مسیر زنده.
3. نتیجه‌ی چند عبارت با شناسه‌ی قطعه یکی می‌شود، **بدون دستکاری رتبه**: ترتیب = ترتیب اولین
   دیده‌شدن (عبارت اول با رتبه‌ی خودش، سپس تازه‌های عبارت دوم و…). امتیاز هر قطعه همان امتیاز
   RRF اولین عبارتی است که آن را یافت و برای هر عبارتِ یابنده جدا ثبت می‌شود (`found_by`).

**هیچ اثر جانبی:** به پایگاه داده نمی‌نویسد (فقط `SAVEPOINT` برای اینکه خطای یک پرس‌وجو تراکنش را
خراب نکند)، تلگرام و تحویل و پیش‌نویس و ارجاع و کارگر را import نمی‌کند، و به خط زنده وصل نیست
(آزمونی با AST این‌ها را می‌سنجد). `retrieval.search` و مسیر `understand-run` دست‌نخورده‌اند.

حریم خصوصی: ورودی مدل پیش‌تر پوشانده می‌شود (`mask_personal`)؛ همه‌ی متن‌های خروجی هم دوباره
پوشانده می‌شوند. خروجی کامل (`retrieval_shadow.json`) متن پوشانده‌شده‌ی پیام دانشجو دارد
(مجوز ۶۰۰، هرگز به مخزن نمی‌رود)؛ `retrieval_shadow_summary.txt` فقط شمارش است.

⚠️ این ابزار «خوب بودن» بازیابی را قضاوت نمی‌کند. فقط می‌گوید برای هر بخش چه آمد و چه نیامد؛
درستی را آدم باید روی نمونه ببیند.
"""

from __future__ import annotations

import inspect
import json
import statistics
from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import structlog
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai.client import ModelClient
from mentorai.ai.understanding import FactClass, Part, Scope
from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.knowledge.retrieval import Hit, search
from mentorai.model_compare import Case, _private_dir, _write_private, mask_personal
from mentorai.understanding_replay import run_replay

log = structlog.get_logger(__name__)

SHADOW_NAME = "retrieval_shadow.json"
SUMMARY_NAME = "retrieval_shadow_summary.txt"
SHADOW_VERSION = 1
PREVIEW_CHARS = 160

SKIP_OUT_OF_DOMAIN = "out_of_domain"
SKIP_REALTIME = "realtime"
SKIP_TRADE_ADVICE = "trade_advice"

# پارامترهای پیش‌فرض بازیابی فعلی، خوانده‌شده از خودش (نه کپی‌شده)، تا گزارش هیچ‌وقت با
# مسیر زنده ناهم‌خوان نشود.
_SEARCH_PARAMS = inspect.signature(search).parameters
SEARCH_SOURCE_CLASSES = list(_SEARCH_PARAMS["source_classes"].default)
SEARCH_LIMIT_PER_QUERY = int(_SEARCH_PARAMS["limit"].default)


def skip_reason(part: Part) -> str | None:
    """چرا این بخش بازیابی نمی‌شود، یا `None` اگر باید بازیابی شود.

    فقط سه حالت، و فقط گزارش: تصمیم نهایی درباره‌ی آن‌ها با مراحل بعد است. `borderline`،
    `academy_fact` و `none` رفتار ویژه‌ای ندارند.
    """
    if part.scope is Scope.out_of_domain:
        return SKIP_OUT_OF_DOMAIN
    if part.fact_class is FactClass.realtime:
        return SKIP_REALTIME
    if part.fact_class is FactClass.trade_advice:
        return SKIP_TRADE_ADVICE
    return None


@dataclass
class FoundBy:
    """یک عبارت که این قطعه را یافت، با رتبه و امتیاز همان عبارت."""

    query_index: int
    query: str
    rank: int
    score: float
    matched_by: list[str]


@dataclass
class ShadowHit:
    """یک قطعه، با همان نام فیلدهای `retrieval.Hit` (به‌جز پیش‌نمایش متن)."""

    chunk_id: int
    document_id: int
    title: str
    source_class: str
    authority: str
    category: str | None
    score: float
    vector_rank: int | None
    text_rank: int | None
    matched_by: list[str]
    content_preview: str
    found_by: list[FoundBy] = field(default_factory=list)


@dataclass
class QueryRun:
    index: int
    query: str
    hit_count: int
    error: str | None = None  # فقط نام نوع خطا؛ پیامش ممکن است پرس‌وجو را داشته باشد


@dataclass
class PartRetrieval:
    hits: list[ShadowHit]
    queries: list[QueryRun]
    duplicates_removed: int

    @property
    def hit_count(self) -> int:
        return len(self.hits)

    @property
    def error_count(self) -> int:
        return sum(1 for q in self.queries if q.error is not None)


@dataclass
class PartRecord:
    message_id: str
    part: Part
    skipped: str | None
    retrieval: PartRetrieval | None

    @property
    def has_hits(self) -> bool:
        return self.retrieval is not None and self.retrieval.hit_count > 0


@dataclass
class MessageRecord:
    message_id: str
    question: str  # پوشانده‌شده
    error: str | None = None
    detail: str | None = None
    ambiguity: str | None = None
    scope_confidence: float | None = None
    adjustments: list[str] = field(default_factory=list)
    parts: list[PartRecord] = field(default_factory=list)


@dataclass
class ShadowData:
    model: str
    prompt_version: str
    embedder: str
    created: str
    messages: list[MessageRecord] = field(default_factory=list)
    excluded: Counter[str] = field(default_factory=Counter)
    eligible_messages: int = 0
    spent_usd: float = 0.0
    stopped_early: bool = False
    dry_run: bool = False


def _preview(content: str) -> str:
    flat = " ".join(content.split())
    text = flat if len(flat) <= PREVIEW_CHARS else flat[:PREVIEW_CHARS].rstrip() + "…"
    return mask_personal(text)


def adapt_hit(hit: Hit, *, query_index: int, query: str, rank: int) -> ShadowHit:
    """`retrieval.Hit` → ساختار گزارش. فقط خواندن و کپی؛ هیچ امتیازی دوباره حساب نمی‌شود."""
    return ShadowHit(
        chunk_id=hit.chunk_id,
        document_id=hit.document_id,
        title=mask_personal(hit.title),
        source_class=hit.source_class,
        authority=hit.authority,
        category=hit.category,
        score=round(hit.score, 6),
        vector_rank=hit.vector_rank,
        text_rank=hit.text_rank,
        matched_by=list(hit.matched_by),
        content_preview=_preview(hit.content),
        found_by=[
            FoundBy(
                query_index=query_index,
                query=mask_personal(query),
                rank=rank,
                score=round(hit.score, 6),
                matched_by=list(hit.matched_by),
            )
        ],
    )


async def _retrieve(
    session: AsyncSession, part: Part, *, embedder: EmbeddingProvider | None
) -> PartRetrieval:
    """همه‌ی `search_queries` را اجرا کن و بر اساس شناسه‌ی قطعه یکی کن؛ رتبه دست‌نخورده."""
    by_id: dict[int, ShadowHit] = {}
    order: list[int] = []
    queries: list[QueryRun] = []
    total = 0

    for index, query in enumerate(part.search_queries, start=1):
        try:
            # SAVEPOINT: اگر خود پایگاه داده خطا بدهد، تراکنش خراب نمی‌شود و عبارت بعدی
            # اجرا می‌شود. چیزی نوشته نمی‌شود.
            async with session.begin_nested():
                results = await search(session, query, embedder=embedder)
        except Exception as exc:  # noqa: BLE001 - شکست یک عبارت نباید گزارش را بکشد
            log.warning("retrieval_shadow_query_failed", error=type(exc).__name__)
            queries.append(QueryRun(index, mask_personal(query), 0, type(exc).__name__))
            continue

        queries.append(QueryRun(index, mask_personal(query), len(results)))
        for rank, hit in enumerate(results, start=1):
            total += 1
            adapted = adapt_hit(hit, query_index=index, query=query, rank=rank)
            existing = by_id.get(hit.chunk_id)
            if existing is None:
                by_id[hit.chunk_id] = adapted
                order.append(hit.chunk_id)
            else:
                existing.found_by.extend(adapted.found_by)

    hits = [by_id[chunk_id] for chunk_id in order]
    return PartRetrieval(hits=hits, queries=queries, duplicates_removed=total - len(hits))


async def shadow_part(
    session: AsyncSession, message_id: str, part: Part, *, embedder: EmbeddingProvider | None
) -> PartRecord:
    reason = skip_reason(part)
    if reason is not None:
        return PartRecord(message_id=message_id, part=part, skipped=reason, retrieval=None)
    retrieval = await _retrieve(session, part, embedder=embedder)
    return PartRecord(message_id=message_id, part=part, skipped=None, retrieval=retrieval)


def _embedder_name(embedder: EmbeddingProvider | None) -> str:
    return "none (text only)" if embedder is None else type(embedder).__name__


async def run_retrieval_shadow(
    session: AsyncSession,
    cases: Sequence[Case],
    client: ModelClient | None,
    *,
    embedder: EmbeddingProvider | None = None,
    max_cost_usd: float = 1.0,
    dry_run: bool = False,
    progress: Callable[[str], None] | None = None,
) -> ShadowData:
    """هر پیام را بفهم، سپس هر بخش را (جز موارد کنارگذاشته) به بازیابی فعلی بده. فقط می‌خواند."""
    replay = await run_replay(
        session, cases, client, max_cost_usd=max_cost_usd, dry_run=dry_run, progress=progress
    )
    data = ShadowData(
        model=replay.model,
        prompt_version=replay.prompt_version,
        embedder=_embedder_name(embedder),
        created=replay.created,
        excluded=replay.excluded,
        eligible_messages=len(replay.cases),
        spent_usd=replay.spent_usd,
        stopped_early=replay.stopped_early,
        dry_run=dry_run,
    )
    if dry_run:
        return data

    for outcome in replay.cases:
        result = outcome.result
        record = MessageRecord(message_id=outcome.id, question=outcome.question)
        data.messages.append(record)
        if result is None or result.understanding is None:
            record.error = result.error if result is not None else "not_run"
            record.detail = result.detail if result is not None else None
            continue
        understanding = result.understanding
        record.ambiguity = understanding.ambiguity.value
        record.scope_confidence = understanding.scope_confidence
        record.adjustments = list(result.adjustments)
        for part in understanding.parts:
            record.parts.append(await shadow_part(session, outcome.id, part, embedder=embedder))
    return data


# ---------------------------------------------------------------------------
# خلاصه (بدون هیچ متن)
# ---------------------------------------------------------------------------


@dataclass
class Metrics:
    total_messages: int
    messages_understood: int
    understanding_errors: Counter[str]
    total_parts: int
    parts_by_scope: Counter[str]
    skipped: Counter[str]
    parts_retrieved: int
    parts_with_hits: int
    parts_without_hits: int
    average_hit_count: float
    average_hit_count_with_hits: float
    average_queries: float
    duplicates_removed: int
    retrieval_query_errors: int
    parts_with_retrieval_errors: int
    by_fact_class: dict[str, tuple[int, int, int]]  # (بخش، بازیابی‌شده، دارای نتیجه)

    @property
    def error_count(self) -> int:
        return sum(self.understanding_errors.values()) + self.retrieval_query_errors


def compute_metrics(data: ShadowData) -> Metrics:
    parts = [p for m in data.messages for p in m.parts]
    retrieved = [p for p in parts if p.retrieval is not None]
    with_hits = [p for p in retrieved if p.has_hits]
    counts = [p.retrieval.hit_count for p in retrieved if p.retrieval is not None]
    counts_with_hits = [p.retrieval.hit_count for p in with_hits if p.retrieval is not None]

    by_fact: dict[str, tuple[int, int, int]] = {}
    for fact in FactClass:
        group = [p for p in parts if p.part.fact_class is fact]
        if group:
            got = [p for p in group if p.retrieval is not None]
            by_fact[fact.value] = (len(group), len(got), sum(1 for p in got if p.has_hits))

    return Metrics(
        total_messages=len(data.messages),
        messages_understood=sum(1 for m in data.messages if m.error is None),
        understanding_errors=Counter(m.error for m in data.messages if m.error is not None),
        total_parts=len(parts),
        parts_by_scope=Counter(p.part.scope.value for p in parts),
        skipped=Counter(p.skipped for p in parts if p.skipped is not None),
        parts_retrieved=len(retrieved),
        parts_with_hits=len(with_hits),
        parts_without_hits=len(retrieved) - len(with_hits),
        average_hit_count=statistics.mean(counts) if counts else 0.0,
        average_hit_count_with_hits=statistics.mean(counts_with_hits) if counts_with_hits else 0.0,
        average_queries=(
            statistics.mean(len(p.retrieval.queries) for p in retrieved if p.retrieval is not None)
            if retrieved
            else 0.0
        ),
        duplicates_removed=sum(p.retrieval.duplicates_removed for p in retrieved if p.retrieval),
        retrieval_query_errors=sum(p.retrieval.error_count for p in retrieved if p.retrieval),
        parts_with_retrieval_errors=sum(
            1 for p in retrieved if p.retrieval is not None and p.retrieval.error_count
        ),
        by_fact_class=by_fact,
    )


def _share(count: int, total: int) -> str:
    return f"{count} ({100 * count / total:.0f}٪)" if total else f"{count}"


def summarise(data: ShadowData) -> str:
    """گزارش شمارشی به فارسی ساده. **هیچ متن پیام، پرسش، عبارت یا سندی در آن نیست.**"""
    lines: list[str] = []
    add = lines.append
    add("خلاصه‌ی سایه‌ی بازیابی (RO-3)")
    add("=" * 28)
    add(f"تاریخ: {data.created} | مدل فهم: {data.model} | نسخه‌ی دستور فهم: {data.prompt_version}")
    add(
        f"بازیابی: {data.embedder} | منبع‌ها: {', '.join(SEARCH_SOURCE_CLASSES)} | "
        f"سقف هر عبارت: {SEARCH_LIMIT_PER_QUERY}"
    )
    excluded = ", ".join(f"{k}: {v}" for k, v in sorted(data.excluded.items())) or "هیچ"
    add(f"کنار گذاشته (قاعده‌ی قطعی، به مدل نرفت): {excluded}")

    if data.dry_run:
        add(f"پیام‌های قابل‌ارسال به مدل: {data.eligible_messages}")
        add("--dry-run بود: نه مدل صدا زده شد و نه بازیابی اجرا شد.")
        return "\n".join(lines)

    m = compute_metrics(data)
    add("")
    add(f"total messages: {m.total_messages} (فهمیده‌شده: {m.messages_understood})")
    add(f"total parts: {m.total_parts}")
    for scope in Scope:
        label = f"{scope.value} parts"
        add(f"{label}: {_share(m.parts_by_scope.get(scope.value, 0), m.total_parts)}")
    skipped_total = sum(m.skipped.values())
    add(f"retrieval_skipped: {_share(skipped_total, m.total_parts)}")
    for reason in (SKIP_OUT_OF_DOMAIN, SKIP_REALTIME, SKIP_TRADE_ADVICE):
        add(f"  {reason}: {m.skipped.get(reason, 0)}")
    add(f"parts_retrieved: {m.parts_retrieved}")
    add(f"parts_with_hits: {_share(m.parts_with_hits, m.parts_retrieved)}")
    add(f"parts_without_hits: {_share(m.parts_without_hits, m.parts_retrieved)}")
    add(f"average hit count (روی بخش‌های بازیابی‌شده): {m.average_hit_count:.2f}")
    add(f"average hit count (فقط بخش‌های دارای نتیجه): {m.average_hit_count_with_hits:.2f}")
    add(f"average queries per part: {m.average_queries:.2f}")
    add(f"duplicate removal count: {m.duplicates_removed}")
    add(
        f"error count: {m.error_count} (فهم: {sum(m.understanding_errors.values())}، "
        f"عبارت بازیابی: {m.retrieval_query_errors} در {m.parts_with_retrieval_errors} بخش)"
    )
    if m.understanding_errors:
        for code, n in m.understanding_errors.most_common():
            add(f"  فهم {code}: {n}")

    if m.by_fact_class:
        add("")
        add("به تفکیک نوع واقعیت (بخش‌ها / بازیابی‌شده / دارای نتیجه):")
        for fact, (n_parts, n_ret, n_hit) in m.by_fact_class.items():
            add(f"  {fact}: {n_parts} / {n_ret} / {n_hit}")

    if data.stopped_early:
        add("⚠️ اجرا به سقف هزینه خورد و زودتر تمام شد؛ فقط پیام‌های اجراشده‌اند.")
    add("")
    add(f"هزینه‌ی مدل فهم: {data.spent_usd:.3f} دلار (بازیابی هزینه ندارد)")
    add("")
    add("یادآوری: این شمارش خوب بودن بازیابی را نمی‌سنجد؛ فقط می‌گوید چه آمد و چه نیامد.")
    add("نتیجه‌ی هر بخش را آدم باید روی نمونه ببیند (retrieval_shadow.json، فقط برای مالک).")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# نوشتن
# ---------------------------------------------------------------------------


def _hit_document(hit: ShadowHit) -> dict[str, Any]:
    return {
        "chunk_id": hit.chunk_id,
        "document_id": hit.document_id,
        "title": hit.title,
        "score": hit.score,
        "source_class": hit.source_class,
        "authority": hit.authority,
        "category": hit.category,
        "matched_by": hit.matched_by,
        "vector_rank": hit.vector_rank,
        "text_rank": hit.text_rank,
        "content_preview": hit.content_preview,
        "found_by": [
            {
                "query_index": f.query_index,
                "query": f.query,
                "rank": f.rank,
                "score": f.score,
                "matched_by": f.matched_by,
            }
            for f in hit.found_by
        ],
    }


def _part_document(record: PartRecord) -> dict[str, Any]:
    part = record.part
    retrieval = record.retrieval
    return {
        "message_id": record.message_id,
        "part_id": part.id,
        "standalone_question": mask_personal(part.standalone_question),
        "scope": part.scope.value,
        "topic": part.topic.value,
        "fact_class": part.fact_class.value,
        "external_method": {
            "named": [mask_personal(n) for n in part.external_method.named],
            "intent": part.external_method.intent.value,
        },
        "search_queries": [mask_personal(q) for q in part.search_queries],
        "has_hits": record.has_hits,
        "retrieval_skipped": record.skipped,
        "retrieval": (
            None
            if retrieval is None
            else {
                "hit_count": retrieval.hit_count,
                "duplicates_removed": retrieval.duplicates_removed,
                "queries": [
                    {
                        "index": q.index,
                        "query": q.query,
                        "hit_count": q.hit_count,
                        "error": q.error,
                    }
                    for q in retrieval.queries
                ],
                "hits": [_hit_document(h) for h in retrieval.hits],
            }
        ),
    }


def shadow_document(data: ShadowData) -> dict[str, Any]:
    return {
        "version": SHADOW_VERSION,
        "created": data.created,
        "understanding_model": data.model,
        "understanding_prompt_version": data.prompt_version,
        "retrieval": {
            "embedder": data.embedder,
            "source_classes": SEARCH_SOURCE_CLASSES,
            "limit_per_query": SEARCH_LIMIT_PER_QUERY,
        },
        "spent_usd": round(data.spent_usd, 6),
        "stopped_early": data.stopped_early,
        "excluded": dict(data.excluded),
        "messages": [
            {
                "message_id": m.message_id,
                "question": m.question,
                "understanding_error": m.error,
                "understanding_detail": m.detail,
                "ambiguity": m.ambiguity,
                "scope_confidence": m.scope_confidence,
                "adjustments": m.adjustments,
                "part_ids": [p.part.id for p in m.parts],
            }
            for m in data.messages
        ],
        "parts": [_part_document(p) for m in data.messages for p in m.parts],
    }


def write_shadow(data: ShadowData, out_dir: Path) -> dict[str, Path]:
    """دو فایل خصوصی بنویس: `retrieval_shadow.json` (با متن پوشانده‌شده) و خلاصه (بی‌متن)."""
    _private_dir(out_dir)
    paths = {"json": out_dir / SHADOW_NAME, "summary": out_dir / SUMMARY_NAME}
    _write_private(paths["json"], json.dumps(shadow_document(data), ensure_ascii=False, indent=2))
    _write_private(paths["summary"], summarise(data) + "\n")
    return paths


__all__ = [
    "SHADOW_NAME",
    "SKIP_OUT_OF_DOMAIN",
    "SKIP_REALTIME",
    "SKIP_TRADE_ADVICE",
    "SUMMARY_NAME",
    "MessageRecord",
    "Metrics",
    "PartRecord",
    "PartRetrieval",
    "ShadowData",
    "ShadowHit",
    "adapt_hit",
    "compute_metrics",
    "run_retrieval_shadow",
    "shadow_document",
    "shadow_part",
    "skip_reason",
    "summarise",
    "write_shadow",
]
