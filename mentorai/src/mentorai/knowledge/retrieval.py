"""بازیابی ترکیبی: جستجوی برداری در کنار جستجوی متنی.

جستجوی برداری تنها، سؤالی را که کاربر با کلمه‌ی دقیق می‌پرسد از دست می‌دهد؛ جستجوی
متنی تنها، سؤالی را که با کلمات دیگری بیان شده. هر دو اجرا می‌شوند و رتبه‌هایشان با
Reciprocal Rank Fusion ترکیب می‌شود.

RRF عمداً روی رتبه کار می‌کند نه روی امتیاز خام: امتیاز کسینوسی و امتیاز ts_rank دو
مقیاس بی‌ربط‌اند و جمع کردنشان بی‌معنی است.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.text import normalize_for_search

# ثابت استاندارد RRF. رتبه‌های پایین را کم‌اثر می‌کند بدون اینکه صفرشان کند.
RRF_K = 60


@dataclass
class Hit:
    chunk_id: int
    document_id: int
    content: str
    source_class: str
    authority: str
    category: str | None
    title: str
    score: float = 0.0
    vector_rank: int | None = None
    text_rank: int | None = None
    matched_by: list[str] = field(default_factory=list)


def _vector_literal(vector: list[float]) -> str:
    return "[" + ",".join(f"{v:.7f}" for v in vector) + "]"


_BASE_COLUMNS = """
    c.id as chunk_id, c.document_id, c.content,
    d.source_class, d.authority, d.category, d.title
"""

_ACTIVE_AND_VALID = """
    d.active
    and (d.valid_until is null or d.valid_until >= current_date)
"""


async def _vector_candidates(
    session: AsyncSession,
    query_vector: list[float],
    *,
    source_classes: tuple[str, ...],
    limit: int,
) -> list[tuple[int, dict[str, Any]]]:
    rows = await session.execute(
        text(
            f"""
            select {_BASE_COLUMNS}
            from knowledge_chunks c
            join knowledge_documents d on d.id = c.document_id
            where {_ACTIVE_AND_VALID}
              and c.embedding is not null
              and d.source_class = any(:source_classes)
            order by c.embedding <=> cast(:qv as vector)
            limit :limit
            """
        ),
        {
            "qv": _vector_literal(query_vector),
            "source_classes": list(source_classes),
            "limit": limit,
        },
    )
    return [(i, dict(r._mapping)) for i, r in enumerate(rows, start=1)]


async def _text_candidates(
    session: AsyncSession,
    query: str,
    *,
    source_classes: tuple[str, ...],
    limit: int,
) -> list[tuple[int, dict[str, Any]]]:
    """جستجوی متنی روی همان کلید نرمال‌شده‌ای که هنگام ذخیره ساخته شده.

    واژه‌های پرسش با «یا» ترکیب می‌شوند، نه «و». پرسش طبیعی همیشه واژه‌های اضافه دارد —
    «چطوری ثبت نام کنم» شامل «چطوری» است که در هیچ سندی نیست — و ترکیب با «و» یعنی
    همان یک واژه کل نتیجه را صفر کند. ts_rank خودش سندی را که واژه‌های بیشتری از پرسش
    را دارد بالاتر می‌آورد، پس سخت‌گیری در شرط لازم نیست.

    در کنارش شباهت واژه‌ای به‌عنوان تور ایمنی برای غلط املایی عمل می‌کند. عملگر <% روی
    بهترین زیررشته حساب می‌کند، نه کل متن؛ عملگر ٪ برای پرسش کوتاه در برابر قطعه‌ی بلند
    همیشه زیر آستانه می‌ماند و عملاً هیچ‌وقت فعال نمی‌شود.

    نکته: این پرس‌وجو فقط با asyncpg اجرا می‌شود که پارامترها را با $n می‌فرستد، پس ٪
    نیازی به فرار دادن ندارد. با درایوری که قالب‌بندی درصدی دارد باید دوبرابر شود.
    """
    rows = await session.execute(
        text(
            f"""
            with q as (
                select
                    to_tsquery(
                        'simple',
                        array_to_string(
                            tsvector_to_array(to_tsvector('simple', :query)), ' | '
                        )
                    ) as tsq
            )
            select {_BASE_COLUMNS},
                   greatest(
                       ts_rank(c.search_vector, q.tsq),
                       word_similarity(:query, c.search_text) / 2
                   ) as rank_score
            from knowledge_chunks c
            join knowledge_documents d on d.id = c.document_id
            cross join q
            where {_ACTIVE_AND_VALID}
              and d.source_class = any(:source_classes)
              and (c.search_vector @@ q.tsq or :query <% c.search_text)
            order by rank_score desc, c.id
            limit :limit
            """
        ),
        {"query": query, "source_classes": list(source_classes), "limit": limit},
    )
    return [(i, dict(r._mapping)) for i, r in enumerate(rows, start=1)]


def _ensure_hit(hits: dict[int, Hit], row: dict[str, Any]) -> Hit:
    chunk_id = int(row["chunk_id"])
    if chunk_id not in hits:
        hits[chunk_id] = Hit(
            chunk_id=chunk_id,
            document_id=int(row["document_id"]),
            content=str(row["content"]),
            source_class=str(row["source_class"]),
            authority=str(row["authority"]),
            category=str(row["category"]) if row["category"] is not None else None,
            title=str(row["title"]),
        )
    return hits[chunk_id]


async def search(
    session: AsyncSession,
    question: str,
    *,
    embedder: EmbeddingProvider | None = None,
    source_classes: tuple[str, ...] = ("official", "mentor"),
    limit: int = 8,
    candidate_pool: int = 40,
) -> list[Hit]:
    """پاسخ‌های نامزد برای یک پرسش، مرتب‌شده.

    اگر ساخت بردار پرسش ممکن نباشد، فقط مسیر متنی اجرا می‌شود. این کاهش کیفیت است، نه
    خطای خاموش: نتیجه‌ی ضعیف به لایه‌ی تصمیم می‌رسد و آن هم به سکوت و ارجاع ختم می‌شود.
    """
    normalized = normalize_for_search(question)
    if not normalized:
        return []

    text_results = await _text_candidates(
        session, normalized, source_classes=source_classes, limit=candidate_pool
    )

    vector_results: list[tuple[int, dict[str, Any]]] = []
    if embedder is not None:
        vectors = await embedder.embed([normalized])
        vector_results = await _vector_candidates(
            session, vectors[0], source_classes=source_classes, limit=candidate_pool
        )

    hits: dict[int, Hit] = {}
    for rank, row in vector_results:
        hit = _ensure_hit(hits, row)
        hit.vector_rank = rank
        hit.score += 1.0 / (RRF_K + rank)
        hit.matched_by.append("vector")
    for rank, row in text_results:
        hit = _ensure_hit(hits, row)
        hit.text_rank = rank
        hit.score += 1.0 / (RRF_K + rank)
        hit.matched_by.append("text")

    return sorted(hits.values(), key=lambda h: (-h.score, h.chunk_id))[:limit]
