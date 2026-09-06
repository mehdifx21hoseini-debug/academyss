"""سنجش کیفیت بازیابی.

بدون عدد، هیچ ادعایی درباره‌ی کیفیت بازیابی قابل اثبات نیست و انتخاب مدل تعبیه‌سازی
تبدیل می‌شود به سلیقه. این ماژول همان عدد را می‌دهد.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.knowledge.embeddings import EmbeddingProvider
from mentorai.knowledge.retrieval import search


@dataclass(frozen=True)
class EvalCase:
    question: str
    expected_document_ids: frozenset[int]


@dataclass
class CaseResult:
    case: EvalCase
    retrieved_document_ids: list[int]

    @property
    def hit(self) -> bool:
        return bool(self.case.expected_document_ids & set(self.retrieved_document_ids))

    @property
    def reciprocal_rank(self) -> float:
        for position, doc_id in enumerate(self.retrieved_document_ids, start=1):
            if doc_id in self.case.expected_document_ids:
                return 1.0 / position
        return 0.0


@dataclass
class Metrics:
    cases: int
    recall_at_k: float
    mrr: float
    misses: list[str]

    def summary(self) -> str:
        return (
            f"موارد: {self.cases} | "
            f"recall@k: {self.recall_at_k:.2f} | "
            f"MRR: {self.mrr:.2f} | "
            f"بی‌نتیجه: {len(self.misses)}"
        )


async def evaluate(
    session: AsyncSession,
    cases: Sequence[EvalCase],
    *,
    embedder: EmbeddingProvider | None = None,
    k: int = 5,
) -> Metrics:
    if not cases:
        raise ValueError("مجموعه‌ی ارزیابی خالی است؛ عددی که از آن دربیاید بی‌معنی است")

    results: list[CaseResult] = []
    for case in cases:
        hits = await search(session, case.question, embedder=embedder, limit=k)
        results.append(CaseResult(case=case, retrieved_document_ids=[h.document_id for h in hits]))

    return Metrics(
        cases=len(results),
        recall_at_k=sum(r.hit for r in results) / len(results),
        mrr=sum(r.reciprocal_rank for r in results) / len(results),
        misses=[r.case.question for r in results if not r.hit],
    )
