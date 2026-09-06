"""ورود پایگاه دانش و بازیابی ترکیبی."""

from __future__ import annotations

import csv
from datetime import date, timedelta
from pathlib import Path

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.evaluate import EvalCase, evaluate
from mentorai.knowledge.ingest import InvalidRow, ingest_csv
from mentorai.knowledge.retrieval import search

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


def _write_csv(tmp_path: Path, rows: list[dict[str, str]], name: str = "kb.csv") -> Path:
    path = tmp_path / name
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow({c: row.get(c, "") for c in COLUMNS})
    return path


def _row(**kw: str) -> dict[str, str]:
    base = {
        "source_class": "official",
        "category": "دوره‌ها",
        "question": "دوره مقدماتی چیست؟",
        "answer": "دوره مقدماتی رایگان شامل شانزده جلسه آموزشی است.",
        "authority": "fact",
    }
    return {**base, **kw}


@pytest.fixture
def embedder() -> HashingEmbedder:
    return HashingEmbedder(dimensions=1024)


async def test_ingest_creates_document_and_chunks(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    report = await ingest_csv(session, _write_csv(tmp_path, [_row()]), embedder=embedder)
    await session.commit()

    assert report.created == 1
    counts = (
        await session.execute(
            text(
                "select (select count(*) from knowledge_documents),"
                "       (select count(*) from knowledge_chunks)"
            )
        )
    ).one()
    assert counts == (1, 1)


async def test_reimporting_the_same_file_updates_instead_of_duplicating(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    path = _write_csv(tmp_path, [_row()])
    await ingest_csv(session, path, embedder=embedder)
    await session.commit()
    second = await ingest_csv(session, path, embedder=embedder)
    await session.commit()

    assert second.created == 0 and second.updated == 1
    total = (await session.execute(text("select count(*) from knowledge_documents"))).scalar_one()
    assert total == 1


async def test_persian_spelling_variants_map_to_the_same_document(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    """«ي» عربی و «ی» فارسی نباید دو سند جدا بسازند."""
    await ingest_csv(
        session, _write_csv(tmp_path, [_row(question="شرايط ثبت نام چيست؟")]), embedder=embedder
    )
    await session.commit()
    again = await ingest_csv(
        session,
        _write_csv(tmp_path, [_row(question="شرایط ثبت نام چیست؟")], name="kb2.csv"),
        embedder=embedder,
    )
    await session.commit()

    assert again.created == 0, "همان ردیف با نگارش دیگر، سند تازه نمی‌سازد"


async def test_row_without_an_answer_is_skipped_not_fatal(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    path = _write_csv(tmp_path, [_row(answer=""), _row(question="سؤال دوم؟")])
    report = await ingest_csv(session, path, embedder=embedder)
    await session.commit()

    assert report.created == 1
    assert report.skipped is not None and len(report.skipped) == 1


async def test_missing_columns_raise_before_anything_is_written(
    session: AsyncSession, tmp_path: Path
) -> None:
    path = tmp_path / "bad.csv"
    path.write_text("question,answer\nالف,ب\n", encoding="utf-8")
    with pytest.raises(InvalidRow):
        await ingest_csv(session, path)


async def test_search_finds_the_document_by_exact_words(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    await ingest_csv(session, _write_csv(tmp_path, [_row()]), embedder=embedder)
    await session.commit()

    hits = await search(session, "دوره مقدماتی چیست؟", embedder=embedder)
    assert hits and "شانزده جلسه" in hits[0].content


async def test_search_matches_across_persian_spelling_variants(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    """پرسش با «ي» عربی باید سندی را که با «ی» فارسی ذخیره شده پیدا کند."""
    await ingest_csv(
        session,
        _write_csv(
            tmp_path,
            [_row(question="شرایط ثبت‌نام چیست؟", answer="ثبت‌نام از طریق فرم سایت انجام می‌شود.")],
        ),
        embedder=embedder,
    )
    await session.commit()

    hits = await search(session, "شرايط ثبت نام", embedder=embedder)
    assert hits, "نگارش عربی باید همان سند فارسی را پیدا کند"


async def test_search_matches_across_digit_systems(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    await ingest_csv(
        session,
        _write_csv(
            tmp_path, [_row(question="دوره ۲ چند جلسه است؟", answer="دوره ۲ شامل ۱۰ جلسه است.")]
        ),
        embedder=embedder,
    )
    await session.commit()

    assert await search(session, "دوره 2 چند جلسه", embedder=embedder)


async def test_source_class_filter_keeps_mentor_answers_out_of_policy_questions(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    """پرسش محدود به منبع رسمی نباید پاسخ تجربی منتور را برگرداند.

    این همان چیزی است که جلوی اعلام قیمت قدیمی از روی یک گفتگوی دو ماه پیش را می‌گیرد.
    """
    rows = [
        _row(
            source_class="official",
            question="هزینه دوره چقدر است؟",
            answer="اطلاعات هزینه از طریق مشاوره اعلام می‌شود.",
            authority="policy",
        ),
        _row(
            source_class="mentor",
            question="هزینه دوره چقدر است؟",
            answer="قیمت دوره دو میلیون تومان است.",
            authority="guidance",
        ),
    ]
    await ingest_csv(session, _write_csv(tmp_path, rows), embedder=embedder)
    await session.commit()

    official_only = await search(
        session, "هزینه دوره چقدر است", embedder=embedder, source_classes=("official",)
    )
    assert official_only
    assert all(h.source_class == "official" for h in official_only)
    assert all("دو میلیون" not in h.content for h in official_only)


async def test_expired_documents_are_not_retrieved(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    await ingest_csv(
        session,
        _write_csv(tmp_path, [_row(question="تخفیف نوروزی چقدر است؟", valid_until=yesterday)]),
        embedder=embedder,
    )
    await session.commit()

    assert await search(session, "تخفیف نوروزی", embedder=embedder) == []


async def test_inactive_documents_are_not_retrieved(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    await ingest_csv(session, _write_csv(tmp_path, [_row()]), embedder=embedder)
    await session.execute(text("update knowledge_documents set active = false"))
    await session.commit()

    assert await search(session, "دوره مقدماتی", embedder=embedder) == []


async def test_search_reports_which_ranker_matched(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    """امتیاز و منشأ هر نتیجه باید قابل بازخوانی باشد؛ همین در ai_runs ثبت می‌شود."""
    await ingest_csv(session, _write_csv(tmp_path, [_row()]), embedder=embedder)
    await session.commit()

    hits = await search(session, "دوره مقدماتی چیست", embedder=embedder)
    assert hits[0].score > 0
    assert set(hits[0].matched_by) <= {"vector", "text"}
    assert hits[0].matched_by


async def test_search_works_without_an_embedder(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    """اگر ساخت بردار ممکن نبود، مسیر متنی باید همچنان جواب بدهد."""
    await ingest_csv(session, _write_csv(tmp_path, [_row()]), embedder=embedder)
    await session.commit()

    hits = await search(session, "دوره مقدماتی", embedder=None)
    assert hits and hits[0].matched_by == ["text"]


async def test_blank_question_returns_nothing(session: AsyncSession) -> None:
    assert await search(session, "   ", embedder=None) == []


async def test_evaluation_reports_recall_and_mrr(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    rows = [
        _row(question="دوره مقدماتی چیست؟", answer="دوره مقدماتی شانزده جلسه دارد."),
        _row(question="پرایس اکشن چیست؟", answer="پرایس اکشن خواندن بازار از روی حرکت قیمت است."),
    ]
    await ingest_csv(session, _write_csv(tmp_path, rows), embedder=embedder)
    await session.commit()

    ids = list(
        (await session.execute(text("select id from knowledge_documents order by id"))).scalars()
    )
    cases = [
        EvalCase(question="دوره مقدماتی چیست", expected_document_ids=frozenset({ids[0]})),
        EvalCase(question="پرایس اکشن یعنی چه", expected_document_ids=frozenset({ids[1]})),
    ]

    metrics = await evaluate(session, cases, embedder=embedder, k=5)
    assert metrics.cases == 2
    assert metrics.recall_at_k == 1.0
    assert metrics.mrr > 0


async def test_evaluation_rejects_an_empty_case_set(session: AsyncSession) -> None:
    with pytest.raises(ValueError):
        await evaluate(session, [], embedder=None)


async def test_natural_question_with_extra_words_still_matches_by_text(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    """پرسش طبیعی همیشه واژه‌ی اضافه دارد.

    «چطوری ثبت نام کنم» شامل «چطوری» است که در هیچ سندی نیست. اگر واژه‌ها با «و»
    ترکیب شوند، همان یک واژه کل نتیجه را صفر می‌کند.
    """
    await ingest_csv(
        session,
        _write_csv(
            tmp_path,
            [_row(question="برای ثبت نام چه کار کنم؟", answer="از فرم سایت اقدام کنید.")],
        ),
        embedder=embedder,
    )
    await session.commit()

    hits = await search(session, "چطوری ثبت نام کنم", embedder=None)
    assert hits, "مسیر متنی باید پرسش طبیعی را پیدا کند"
    assert hits[0].matched_by == ["text"]


async def test_misspelled_query_is_caught_by_word_similarity(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    await ingest_csv(
        session,
        _write_csv(
            tmp_path,
            [_row(question="پرایس اکشن چیست؟", answer="خواندن بازار از روی حرکت قیمت.")],
        ),
        embedder=embedder,
    )
    await session.commit()

    assert await search(session, "پرایس اکشون", embedder=None), "غلط املایی باید گرفته شود"


async def test_both_rankers_contribute_when_both_match(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    await ingest_csv(session, _write_csv(tmp_path, [_row()]), embedder=embedder)
    await session.commit()

    hits = await search(session, "دوره مقدماتی چیست", embedder=embedder)
    assert sorted(hits[0].matched_by) == ["text", "vector"]
