"""ورود پایگاه دانش از فایل CSV.

قالب همان چیزی است که در docs/KNOWLEDGE_BASE.md به منتورها داده شده. وارد کردن دوباره‌ی
همان فایل، سند موجود را به‌روز می‌کند و سند تکراری نمی‌سازد.
"""

from __future__ import annotations

import csv
import hashlib
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.db.models import Authority, KnowledgeChunk, KnowledgeDocument, SourceClass
from mentorai.knowledge.chunking import chunk_text
from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.text import normalize_for_search, normalize_for_storage

REQUIRED_COLUMNS = frozenset(
    {"source_class", "category", "question", "answer", "authority", "valid_until", "owner", "notes"}
)


class InvalidRow(ValueError):
    pass


@dataclass
class IngestReport:
    created: int = 0
    updated: int = 0
    skipped: list[str] | None = None

    def __post_init__(self) -> None:
        if self.skipped is None:
            self.skipped = []


def external_key(source_class: str, category: str, question: str) -> str:
    """کلید پایدار یک ردیف.

    از متن نرمال‌شده ساخته می‌شود تا تفاوت‌های نگارشی مثل نیم‌فاصله یا «ی» عربی، همان
    ردیف را دوباره وارد نکند.
    """
    raw = "|".join((source_class, normalize_for_search(category), normalize_for_search(question)))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:64]


def _parse_row(row: dict[str, str]) -> dict[str, object]:
    question = (row.get("question") or "").strip()
    answer = (row.get("answer") or "").strip()
    if not question:
        raise InvalidRow("ستون question خالی است")
    if not answer:
        raise InvalidRow(f"پاسخ برای «{question[:40]}» هنوز نوشته نشده")

    source_class = (row.get("source_class") or "").strip()
    if source_class not in {s.value for s in SourceClass}:
        raise InvalidRow(f"source_class نامعتبر: «{source_class}»")

    authority = (row.get("authority") or "").strip() or Authority.guidance.value
    if authority not in {a.value for a in Authority}:
        raise InvalidRow(f"authority نامعتبر: «{authority}»")

    valid_until_raw = (row.get("valid_until") or "").strip()
    valid_until = date.fromisoformat(valid_until_raw) if valid_until_raw else None

    category = (row.get("category") or "").strip()
    return {
        "external_key": external_key(source_class, category, question),
        "source_class": source_class,
        "authority": authority,
        "category": category or None,
        "title": normalize_for_storage(question),
        "body": normalize_for_storage(answer),
        "valid_until": valid_until,
        "owner": (row.get("owner") or "").strip() or None,
        "notes": (row.get("notes") or "").strip() or None,
    }


async def _rebuild_chunks(
    session: AsyncSession, document: KnowledgeDocument, embedder: EmbeddingProvider | None
) -> None:
    """قطعه‌ها همیشه از نو ساخته می‌شوند.

    به‌روزرسانی جزئی قطعه‌ها یعنی بردار قدیمی کنار متن جدید بماند، که بدترین حالت است:
    بازیابی چیزی را پیدا می‌کند که دیگر آنجا نیست.
    """
    await session.execute(delete(KnowledgeChunk).where(KnowledgeChunk.document_id == document.id))

    # عنوان همراه هر قطعه می‌آید، چون سؤال خودش بهترین سرنخ بازیابی است.
    full_text = f"{document.title}\n\n{document.body}"
    pieces = chunk_text(full_text)
    vectors: list[list[float] | None] = [None] * len(pieces)
    if embedder is not None and pieces:
        embedded = await embedder.embed([normalize_for_search(p) for p in pieces])
        vectors = list(embedded)

    for ordinal, (piece, vector) in enumerate(zip(pieces, vectors, strict=True)):
        session.add(
            KnowledgeChunk(
                document_id=document.id,
                ordinal=ordinal,
                content=piece,
                search_text=normalize_for_search(piece),
                embedding=vector,
                embedding_model=embedder.model if embedder is not None else None,
            )
        )


async def upsert_document(
    session: AsyncSession, parsed: dict[str, object], embedder: EmbeddingProvider | None
) -> bool:
    """سند را بساز یا به‌روز کن. True یعنی تازه ساخته شد."""
    existing = (
        await session.execute(
            select(KnowledgeDocument).where(
                KnowledgeDocument.external_key == parsed["external_key"]
            )
        )
    ).scalar_one_or_none()

    created = existing is None
    document = existing or KnowledgeDocument(external_key=str(parsed["external_key"]))
    for field_name in (
        "source_class",
        "authority",
        "category",
        "title",
        "body",
        "valid_until",
        "owner",
        "notes",
    ):
        setattr(document, field_name, parsed[field_name])
    document.active = True
    session.add(document)
    await session.flush()

    await _rebuild_chunks(session, document, embedder)
    return created


async def ingest_csv(
    session: AsyncSession, path: Path, *, embedder: EmbeddingProvider | None = None
) -> IngestReport:
    """یک فایل CSV را وارد کن.

    ردیف ناقص کل ورود را متوقف نمی‌کند؛ کنار گذاشته و گزارش می‌شود. یک پاسخ ننوشته در
    میان صد ردیف نباید مانع وارد کردن نود و نه تای دیگر شود.
    """
    report = IngestReport()
    assert report.skipped is not None

    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        missing = REQUIRED_COLUMNS - set(reader.fieldnames or [])
        if missing:
            raise InvalidRow(f"ستون‌های لازم در فایل نیست: {', '.join(sorted(missing))}")

        for line_number, row in enumerate(reader, start=2):
            try:
                parsed = _parse_row(row)
            except (InvalidRow, ValueError) as exc:
                report.skipped.append(f"خط {line_number}: {exc}")
                continue
            if await upsert_document(session, parsed, embedder):
                report.created += 1
            else:
                report.updated += 1

    return report
