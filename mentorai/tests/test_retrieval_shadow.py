"""سایه‌ی بازیابی (RO-3): فهم v2 → بازیابی فعلی، فقط گزارش.

مدل فهم `ScriptedClient` است؛ هیچ فراخوانی واقعی انجام نمی‌شود، پس این تست‌ها **قضاوت Claude**
را نمی‌سنجند. آنچه سنجیده می‌شود رفتار واقعی لایه‌ی پیوند است: چه چیزی به بازیابی داده می‌شود،
چه چیزی نمی‌شود، نتایج چطور یکی و گزارش می‌شوند، خطا چطور مهار می‌شود، و اینکه هیچ اثر جانبی
یا اتصال به خط زنده نیست. بازیابی در بخش‌های «واقعی» روی Postgres واقعی و با `search` اصلی
اجرا می‌شود؛ در بخش‌های «دقیق» برای کنترل کامل، `search` جایگزین می‌شود.
"""

from __future__ import annotations

import ast
import csv
import inspect
import json
import stat
from argparse import Namespace
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from tests import test_runtime as _rt
from tests.test_runtime import COLUMNS, _incoming
from tests.test_understanding import SRC, _imports, _part, _payload
from tests.test_understanding_replay import _snapshot

from mentorai import cli
from mentorai import understanding_replay as ur
from mentorai.ai import retrieval_shadow as rs
from mentorai.ai.client import RawCall, ScriptedClient
from mentorai.db.models import MentorAccount, Message
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.ingest import ingest_csv
from mentorai.knowledge.retrieval import Hit
from mentorai.model_compare import Case

embedder = _rt.embedder

PHONE = "09121234567"
EMAIL = "student@example.com"
KB_EMAIL = "support@academy-example.com"

KB_ROWS = [
    [
        "official",
        "مدیریت ریسک",
        "ریسک به ریوارد چیست؟",
        f"نسبت ریسک به ریوارد یعنی مقایسه ضرر احتمالی با سود احتمالی. تماس {KB_EMAIL}",
        "fact",
    ],
    ["official", "بک‌تست", "بک‌تست چیست؟", "بک‌تست یعنی آزمودن یک روش روی داده‌ی گذشته.", "fact"],
    ["official", "ثبت‌نام", "شرایط ثبت‌نام چیست؟", "ثبت‌نام از طریق فرم سایت انجام می‌شود.", "policy"],
    ["mentor", "فوروارد", "مدت فوروارد تست چقدر است؟", "فوروارد تست دو هفته طول می‌کشد.", "fact"],
]


@pytest.fixture
async def kb(session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder) -> None:
    path = tmp_path / "kb.csv"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(COLUMNS)
        for row in KB_ROWS:
            writer.writerow([*row, *[""] * (len(COLUMNS) - len(row))])
    await ingest_csv(session, path, embedder=embedder)
    await session.commit()


class _Router(ScriptedClient):
    """هر پیام خروجی فهم خودش را می‌گیرد: کلید در متن «پیام فعلی» پیدا می‌شود."""

    def __init__(self, routes: dict[str, str]) -> None:
        super().__init__(raw_text="")
        self._routes = routes

    async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> RawCall:
        self.calls.append((system, user))
        current = user.rsplit("پیام فعلی دانشجو که باید بفهمی:", 1)[-1]
        for marker, payload in self._routes.items():
            if marker in current:
                return RawCall(
                    text=payload, model=self.model, latency_ms=1, input_tokens=10, output_tokens=5
                )
        return RawCall(text=None, model=self.model, latency_ms=1, error="no-route")


async def _message(session: AsyncSession, account: MentorAccount, body: str, n: int) -> Message:
    return await _incoming(session, account, body, message_id=n)


def _cases(*messages: Message) -> list[Case]:
    return [Case(id=f"m{m.id}", question=m.text or "") for m in messages]


def _fake_hit(chunk_id: int, *, score: float = 0.0164, title: str = "سند") -> Hit:
    return Hit(
        chunk_id=chunk_id,
        document_id=chunk_id + 100,
        content=f"متن قطعه‌ی شماره {chunk_id} " * 3,
        source_class="official",
        authority="fact",
        category="دسته",
        title=f"{title} {chunk_id}",
        score=score,
        vector_rank=None,
        text_rank=1,
        matched_by=["text"],
    )


class _FakeSearch:
    """جایگزین `search` برای کنترل دقیق: هر عبارت نتیجه‌ی از پیش‌تعیین‌شده می‌گیرد."""

    def __init__(self, results: dict[str, list[Hit] | Exception] | None = None) -> None:
        self.results = results or {}
        self.calls: list[tuple[str, dict[str, Any]]] = []

    async def __call__(self, session: AsyncSession, question: str, **kwargs: Any) -> list[Hit]:
        self.calls.append((question, kwargs))
        outcome = self.results.get(question, [])
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


def _install(monkeypatch: pytest.MonkeyPatch, fake: _FakeSearch) -> _FakeSearch:
    monkeypatch.setattr(rs, "search", fake)
    return fake


# ---------------------------------------------------------------------------
# بازیابی واقعی (Postgres و `search` اصلی)
# ---------------------------------------------------------------------------


async def test_a_single_part_message_is_retrieved_from_the_real_knowledge_base(
    session: AsyncSession, account: MentorAccount, kb: None
) -> None:
    message = await _message(session, account, "ریسک به ریوارد یعنی چه؟", 1)
    client = _Router({"ریسک به ریوارد": _payload(_part(1, "ریسک به ریوارد یعنی چه؟"))})

    data = await rs.run_retrieval_shadow(session, _cases(message), client)

    assert [m.message_id for m in data.messages] == [f"m{message.id}"]
    record = data.messages[0].parts[0]
    assert record.has_hits and record.skipped is None
    assert record.retrieval is not None and record.retrieval.hit_count >= 1
    assert any("ریسک" in h.content_preview for h in record.retrieval.hits)

    doc = rs.shadow_document(data)
    part = doc["parts"][0]
    assert part["message_id"] == f"m{message.id}" and part["part_id"] == 1
    assert part["scope"] == "in_domain" and part["fact_class"] == "general_knowledge"
    assert part["topic"] == "risk_management"
    assert part["search_queries"] == ["ریسک به ریوارد"]
    assert part["has_hits"] is True and part["retrieval_skipped"] is None
    retrieval = part["retrieval"]
    assert retrieval["hit_count"] == len(retrieval["hits"]) >= 1
    hit = retrieval["hits"][0]
    assert {"chunk_id", "title", "score", "source_class", "content_preview", "found_by"} <= set(hit)
    assert hit["source_class"] in ("official", "mentor")


async def test_a_multi_intent_message_is_retrieved_part_by_part(
    session: AsyncSession, account: MentorAccount, kb: None
) -> None:
    message = await _message(session, account, "ریسک به ریوارد چیست؟ بک‌تست چیست؟ سؤال سوم", 1)
    payload = _payload(
        _part(1, "ریسک به ریوارد چیست؟", queries=("ریسک به ریوارد",)),
        _part(2, "بک‌تست چیست؟", topic="backtest_forward", queries=("بک‌تست",)),
        _part(3, "سؤال سوم", topic="other", fact_class="none", queries=("zzqqxx",)),
    )

    data = await rs.run_retrieval_shadow(session, _cases(message), _Router({"سؤال سوم": payload}))

    parts = data.messages[0].parts
    assert [p.part.id for p in parts] == [1, 2, 3]
    assert [p.has_hits for p in parts] == [True, True, False]
    first, second, third = (p.retrieval for p in parts)
    assert first is not None and second is not None and third is not None
    assert "ریسک" in " ".join(h.content_preview for h in first.hits)
    assert "بک‌تست" in " ".join(h.content_preview for h in second.hits)
    assert third.hit_count == 0


async def test_the_current_search_is_called_exactly_as_the_live_path_calls_it(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    """هر عبارت جداگانه، بدون بازنویسی، با همان پارامترهای مسیر زنده (فقط `embedder`)."""
    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)
    fake = _install(monkeypatch, _FakeSearch())
    payload = _payload(_part(1, "سؤال", queries=("عبارت یک", "عبارت دو", "عبارت سه")))
    used = HashingEmbedder()

    await rs.run_retrieval_shadow(
        session, _cases(message), _Router({"سؤال آزمایشی": payload}), embedder=used
    )

    assert [q for q, _ in fake.calls] == ["عبارت یک", "عبارت دو", "عبارت سه"]
    assert all(kwargs == {"embedder": used} for _, kwargs in fake.calls), "پارامتر دیگری نیست"


def test_the_reported_search_defaults_come_from_the_real_function() -> None:
    from mentorai.knowledge.retrieval import search

    params = inspect.signature(search).parameters
    assert rs.SEARCH_LIMIT_PER_QUERY == params["limit"].default == 8
    assert list(params["source_classes"].default) == rs.SEARCH_SOURCE_CLASSES


# ---------------------------------------------------------------------------
# چند عبارت، تکراری، رتبه
# ---------------------------------------------------------------------------


async def test_duplicate_chunks_are_removed_but_remember_every_query_that_found_them(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)
    a, b, c = _fake_hit(1, score=0.0328), _fake_hit(2, score=0.0161), _fake_hit(3, score=0.0160)
    b_again = _fake_hit(2, score=0.0164)
    _install(monkeypatch, _FakeSearch({"عبارت یک": [a, b], "عبارت دو": [b_again, c]}))
    payload = _payload(_part(1, "سؤال", queries=("عبارت یک", "عبارت دو")))

    data = await rs.run_retrieval_shadow(
        session, _cases(message), _Router({"سؤال آزمایشی": payload})
    )

    retrieval = data.messages[0].parts[0].retrieval
    assert retrieval is not None
    assert [h.chunk_id for h in retrieval.hits] == [1, 2, 3], "ترتیب اولین دیده‌شدن"
    assert retrieval.duplicates_removed == 1
    assert [q.hit_count for q in retrieval.queries] == [2, 2]
    by_chunk = {h.chunk_id: h for h in retrieval.hits}
    assert [f.query_index for f in by_chunk[2].found_by] == [1, 2]
    assert [f.rank for f in by_chunk[2].found_by] == [2, 1], "رتبه‌ی هر عبارت جدا"
    assert [f.score for f in by_chunk[2].found_by] == [0.0161, 0.0164]
    assert by_chunk[2].score == 0.0161, "امتیاز همان عبارت اول؛ هیچ امتیازی ترکیب نشد"
    assert [f.query for f in by_chunk[1].found_by] == ["عبارت یک"]


async def test_ranking_is_never_rearranged_across_queries(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    """حتی اگر قطعه‌ی عبارت دوم امتیاز بالاتری دارد، پشت قطعه‌های عبارت اول می‌ماند."""
    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)
    low = [_fake_hit(1, score=0.0100), _fake_hit(2, score=0.0090)]
    high = [_fake_hit(3, score=0.0900)]
    _install(monkeypatch, _FakeSearch({"عبارت یک": low, "عبارت دو": high}))
    payload = _payload(_part(1, "سؤال", queries=("عبارت یک", "عبارت دو")))

    data = await rs.run_retrieval_shadow(
        session, _cases(message), _Router({"سؤال آزمایشی": payload})
    )

    retrieval = data.messages[0].parts[0].retrieval
    assert retrieval is not None
    assert [h.chunk_id for h in retrieval.hits] == [1, 2, 3]
    assert [h.score for h in retrieval.hits] == [0.01, 0.009, 0.09]


# ---------------------------------------------------------------------------
# بخش‌هایی که بازیابی نمی‌شوند: فقط وضعیت
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("scope", "topic", "fact_class", "reason"),
    [
        ("out_of_domain", "other", "none", "out_of_domain"),
        ("in_domain", "market_concepts", "realtime", "realtime"),
        ("in_domain", "trading_education", "trade_advice", "trade_advice"),
    ],
)
async def test_parts_that_must_not_be_retrieved_are_only_reported(
    session: AsyncSession,
    account: MentorAccount,
    monkeypatch: pytest.MonkeyPatch,
    scope: str,
    topic: str,
    fact_class: str,
    reason: str,
) -> None:
    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)
    fake = _install(monkeypatch, _FakeSearch({"عبارت": [_fake_hit(1)]}))
    payload = _payload(
        _part(1, "سؤال", scope=scope, topic=topic, fact_class=fact_class, queries=("عبارت",))
    )

    data = await rs.run_retrieval_shadow(
        session, _cases(message), _Router({"سؤال آزمایشی": payload})
    )

    record = data.messages[0].parts[0]
    assert record.skipped == reason
    assert record.retrieval is None and not record.has_hits
    assert fake.calls == [], "بازیابی برای این بخش اجرا نشد"
    part_doc = rs.shadow_document(data)["parts"][0]
    assert part_doc["retrieval_skipped"] == reason
    assert part_doc["retrieval"] is None and part_doc["has_hits"] is False
    # نوع واقعیت و حوزه همان‌اند که فهم داد؛ trade_advice به سؤال آموزشی تبدیل نشد.
    assert part_doc["fact_class"] == fact_class and part_doc["scope"] == scope


@pytest.mark.parametrize(
    ("scope", "fact_class"),
    [
        ("in_domain", "academy_fact"),
        ("in_domain", "general_knowledge"),
        ("borderline", "none"),
        ("in_domain", "none"),
    ],
)
async def test_every_other_part_is_retrieved_with_its_queries_untouched(
    session: AsyncSession,
    account: MentorAccount,
    monkeypatch: pytest.MonkeyPatch,
    scope: str,
    fact_class: str,
) -> None:
    """academy_fact هیچ رفتار ویژه‌ای ندارد؛ borderline و none هم فقط همان عبارت‌ها را می‌گیرند."""
    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)
    fake = _install(monkeypatch, _FakeSearch({"عبارت اول": [_fake_hit(1)]}))
    payload = _payload(
        _part(
            1,
            "سؤال",
            scope=scope,
            topic="academy_policy" if fact_class == "academy_fact" else "other",
            fact_class=fact_class,
            queries=("عبارت اول", "عبارت دوم"),
        )
    )

    data = await rs.run_retrieval_shadow(
        session, _cases(message), _Router({"سؤال آزمایشی": payload})
    )

    record = data.messages[0].parts[0]
    assert record.skipped is None
    assert [q for q, _ in fake.calls] == ["عبارت اول", "عبارت دوم"]
    assert record.has_hits and record.part.fact_class.value == fact_class


def test_skip_reason_is_exactly_the_three_agreed_cases() -> None:
    from mentorai.ai.understanding import Understanding

    def part(scope: str, fact: str) -> Any:
        data = json.loads(_payload(_part(1, "س", scope=scope, fact_class=fact, topic="other")))
        return Understanding.model_validate(data).parts[0]

    assert rs.skip_reason(part("out_of_domain", "none")) == "out_of_domain"
    assert rs.skip_reason(part("in_domain", "realtime")) == "realtime"
    assert rs.skip_reason(part("in_domain", "trade_advice")) == "trade_advice"
    for scope in ("in_domain", "borderline"):
        for fact in ("academy_fact", "general_knowledge", "none"):
            assert rs.skip_reason(part(scope, fact)) is None


# ---------------------------------------------------------------------------
# بازیابی خالی و خطا
# ---------------------------------------------------------------------------


async def test_empty_retrieval_is_reported_as_no_hits(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)
    _install(monkeypatch, _FakeSearch())
    payload = _payload(_part(1, "سؤال"))

    data = await rs.run_retrieval_shadow(
        session, _cases(message), _Router({"سؤال آزمایشی": payload})
    )

    record = data.messages[0].parts[0]
    assert record.retrieval is not None and record.retrieval.hit_count == 0
    assert not record.has_hits
    doc = rs.shadow_document(data)["parts"][0]
    assert doc["has_hits"] is False and doc["retrieval"]["hits"] == []
    metrics = rs.compute_metrics(data)
    assert (metrics.parts_with_hits, metrics.parts_without_hits) == (0, 1)


async def test_a_retrieval_exception_is_recorded_without_its_message_and_does_not_stop_the_run(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)
    other = await _message(session, account, "پیام دوم درباره بک‌تست", 2)
    boom = RuntimeError("متن-محرمانه-پرس‌وجو-۹۹۱")
    fake = _install(
        monkeypatch,
        _FakeSearch(
            {"عبارت خراب": boom, "عبارت سالم": [_fake_hit(1)], "عبارت دوم": [_fake_hit(2)]}
        ),
    )
    router = _Router(
        {
            "سؤال آزمایشی": _payload(_part(1, "سؤال", queries=("عبارت خراب", "عبارت سالم"))),
            "پیام دوم": _payload(_part(1, "دوم", queries=("عبارت دوم",))),
        }
    )

    data = await rs.run_retrieval_shadow(session, _cases(message, other), router)

    first = data.messages[0].parts[0].retrieval
    assert first is not None
    assert [q.error for q in first.queries] == ["RuntimeError", None]
    assert first.hit_count == 1, "نتیجه‌ی عبارت سالم نگه داشته شد"
    assert data.messages[1].parts[0].has_hits, "پیام بعدی بی‌اثر از خطا اجرا شد"
    assert len(fake.calls) == 3
    metrics = rs.compute_metrics(data)
    assert metrics.retrieval_query_errors == 1 and metrics.error_count == 1
    dumped = json.dumps(rs.shadow_document(data), ensure_ascii=False) + rs.summarise(data)
    assert "متن-محرمانه" not in dumped, "فقط نام نوع خطا ثبت می‌شود"


async def test_a_database_error_inside_a_query_does_not_poison_the_session(
    session: AsyncSession, account: MentorAccount, kb: None, monkeypatch: pytest.MonkeyPatch
) -> None:
    """خطای واقعی SQL، تراکنش را خراب می‌کند؛ SAVEPOINT باید عبارت بعدی را سالم نگه دارد."""
    from mentorai.knowledge import retrieval as real

    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)

    async def flaky(sess: AsyncSession, question: str, **kwargs: Any) -> list[Hit]:
        if question == "عبارت خراب":
            await sess.execute(text("select * from table_that_does_not_exist"))
        return await real.search(sess, question, **kwargs)

    monkeypatch.setattr(rs, "search", flaky)
    payload = _payload(_part(1, "سؤال", queries=("عبارت خراب", "ریسک به ریوارد")))

    data = await rs.run_retrieval_shadow(
        session, _cases(message), _Router({"سؤال آزمایشی": payload})
    )

    retrieval = data.messages[0].parts[0].retrieval
    assert retrieval is not None
    assert retrieval.queries[0].error == "ProgrammingError"
    assert retrieval.queries[1].error is None and retrieval.queries[1].hit_count >= 1
    assert (await session.execute(text("select 1"))).scalar_one() == 1


async def test_an_understanding_failure_is_counted_and_nothing_is_retrieved(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)
    fake = _install(monkeypatch, _FakeSearch())

    data = await rs.run_retrieval_shadow(
        session, _cases(message), _Router({"سؤال آزمایشی": "این JSON نیست"})
    )

    record = data.messages[0]
    assert record.error == "invalid_output" and record.parts == []
    assert fake.calls == []
    metrics = rs.compute_metrics(data)
    assert metrics.total_parts == 0 and metrics.error_count == 1
    assert metrics.understanding_errors == {"invalid_output": 1}


async def test_a_message_that_hits_a_deterministic_rule_is_never_sent_or_retrieved(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    money = await _message(session, account, "رسید واریزم رو فرستادم چی شد؟", 1)
    fake = _install(monkeypatch, _FakeSearch())
    client = _Router({})

    data = await rs.run_retrieval_shadow(session, _cases(money), client)

    assert data.messages == [] and data.excluded == {"rule_money": 1}
    assert client.calls == [] and fake.calls == []


async def test_dry_run_calls_neither_the_model_nor_the_retrieval(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    message = await _message(session, account, "سؤال آزمایشی درباره ریسک", 1)
    fake = _install(monkeypatch, _FakeSearch())
    client = _Router({})

    data = await rs.run_retrieval_shadow(session, _cases(message), client, dry_run=True)

    assert client.calls == [] and fake.calls == []
    assert data.eligible_messages == 1 and data.messages == []
    assert "--dry-run بود" in rs.summarise(data)


# ---------------------------------------------------------------------------
# معیارها
# ---------------------------------------------------------------------------


async def test_the_summary_metrics_are_exact_on_a_mixed_run(
    session: AsyncSession, account: MentorAccount, monkeypatch: pytest.MonkeyPatch
) -> None:
    m1 = await _message(session, account, "پیام اول درباره ریسک", 1)
    m2 = await _message(session, account, "پیام دوم نامشخص", 2)
    m3 = await _message(session, account, "پیام سوم خراب", 3)
    m4 = await _message(session, account, "پیام چهارم لحظه‌ای", 4)
    fake = _install(
        monkeypatch,
        _FakeSearch(
            {
                "q-الف": [_fake_hit(1), _fake_hit(2)],
                "q-ب": [_fake_hit(2), _fake_hit(3)],
                "q-خراب": RuntimeError("x"),
            }
        ),
    )
    router = _Router(
        {
            "پیام اول": _payload(
                _part(1, "الف", queries=("q-الف", "q-ب")),
                _part(2, "بی‌ربط", scope="out_of_domain", topic="other", fact_class="none"),
            ),
            "پیام دوم": _payload(
                _part(
                    1,
                    "ب",
                    scope="borderline",
                    topic="other",
                    fact_class="none",
                    queries=("q-خالی",),
                ),
                ambiguity="needs_clarification",
            ),
            "پیام سوم": "خراب",
            "پیام چهارم": _payload(
                _part(1, "لحظه‌ای", fact_class="realtime", topic="market_concepts"),
                _part(2, "خرید", fact_class="trade_advice", topic="trading_education"),
                _part(3, "عمومی", queries=("q-خراب",)),
            ),
        }
    )

    data = await rs.run_retrieval_shadow(session, _cases(m1, m2, m3, m4), router)
    metrics = rs.compute_metrics(data)

    assert metrics.total_messages == 4 and metrics.messages_understood == 3
    assert metrics.total_parts == 6
    assert metrics.parts_by_scope == {"in_domain": 4, "out_of_domain": 1, "borderline": 1}
    assert metrics.skipped == {"out_of_domain": 1, "realtime": 1, "trade_advice": 1}
    assert metrics.parts_retrieved == 3
    assert (metrics.parts_with_hits, metrics.parts_without_hits) == (1, 2)
    assert metrics.parts_with_hits + metrics.parts_without_hits == metrics.parts_retrieved
    assert metrics.duplicates_removed == 1
    assert metrics.average_hit_count == pytest.approx(1.0)  # (3 + 0 + 0) / 3
    assert metrics.average_hit_count_with_hits == pytest.approx(3.0)
    assert metrics.average_queries == pytest.approx(4 / 3)
    assert metrics.understanding_errors == {"invalid_output": 1}
    assert (metrics.retrieval_query_errors, metrics.parts_with_retrieval_errors) == (1, 1)
    assert metrics.error_count == 2
    assert metrics.by_fact_class == {
        "general_knowledge": (2, 2, 1),
        "realtime": (1, 0, 0),
        "trade_advice": (1, 0, 0),
        "none": (2, 1, 0),
    }
    assert len(fake.calls) == 4

    summary = rs.summarise(data)
    for expected in (
        "total messages: 4",
        "total parts: 6",
        "in_domain parts: 4",
        "borderline parts: 1",
        "out_of_domain parts: 1",
        "retrieval_skipped: 3",
        "parts_with_hits: 1",
        "parts_without_hits: 2",
        "average hit count",
        "duplicate removal count: 1",
        "error count: 2",
    ):
        assert expected in summary, expected


async def test_the_summary_has_no_text_at_all(
    session: AsyncSession, account: MentorAccount, kb: None
) -> None:
    message = await _message(session, account, "ریسک به ریوارد یعنی چه؟ راز-۷۷۱", 1)
    payload = _payload(_part(1, "راز-۷۷۱ چیست؟", queries=("ریسک به ریوارد", "کلید-راز-۷۷۱")))

    data = await rs.run_retrieval_shadow(session, _cases(message), _Router({"راز-۷۷۱": payload}))
    summary = rs.summarise(data)

    for secret in ("راز-۷۷۱", "ریسک به ریوارد", "نسبت ریسک", "چیست؟"):
        assert secret not in summary


# ---------------------------------------------------------------------------
# حریم خصوصی
# ---------------------------------------------------------------------------


async def test_personal_data_is_masked_everywhere_in_the_output(
    session: AsyncSession, account: MentorAccount, kb: None
) -> None:
    message = await _message(
        session, account, f"ریسک به ریوارد یعنی چه؟ شماره من {PHONE} و ایمیل {EMAIL}", 1
    )
    # حتی اگر مدل (برخلاف دستور) اطلاعات شخصی را در خروجی‌اش تکرار کند، خروجی ما پوشانده است.
    payload = _payload(
        _part(
            1,
            f"ریسک به ریوارد؛ تماس {PHONE} {EMAIL}",
            queries=(f"ریسک به ریوارد {PHONE}", "ریسک به ریوارد"),
        )
    )
    client = _Router({"ریسک به ریوارد": payload})

    data = await rs.run_retrieval_shadow(session, _cases(message), client)
    dumped = json.dumps(rs.shadow_document(data), ensure_ascii=False) + rs.summarise(data)

    assert PHONE not in dumped and EMAIL not in dumped
    assert KB_EMAIL not in dumped, "ایمیل داخل متن سند هم در پیش‌نمایش پوشانده می‌شود"
    assert "[حذف‌شده]" in dumped
    # و آنچه به مدل رسید هم پوشانده بود.
    assert PHONE not in client.calls[0][1] and EMAIL not in client.calls[0][1]


# ---------------------------------------------------------------------------
# هیچ اثر جانبی و هیچ اتصال زنده
# ---------------------------------------------------------------------------


async def test_the_shadow_writes_nothing_to_the_database(
    session: AsyncSession, account: MentorAccount, kb: None, tmp_path: Path
) -> None:
    message = await _message(session, account, "ریسک به ریوارد یعنی چه؟", 1)
    before = await _snapshot(session)
    assert any(count for count, _ in before.values()), "پیش‌شرط: پایگاه داده خالی نیست"
    client = _Router({"ریسک به ریوارد": _payload(_part(1, "ریسک به ریوارد یعنی چه؟"))})

    data = await rs.run_retrieval_shadow(session, _cases(message), client)
    rs.write_shadow(data, tmp_path / "out")
    await session.commit()

    assert await _snapshot(session) == before


def test_the_shadow_module_cannot_send_or_write_and_is_not_in_the_live_path() -> None:
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
    )
    names = _imports(SRC / "ai" / "retrieval_shadow.py")
    assert not {n for n in names if n.startswith(forbidden)}, sorted(names)

    tree = ast.parse((SRC / "ai" / "retrieval_shadow.py").read_text(encoding="utf-8"))
    calls = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert not calls & {"add", "add_all", "execute", "commit", "flush", "delete", "merge"}

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
        SRC / "understanding_replay.py",
    )
    for module in live:
        assert not any("retrieval_shadow" in n for n in _imports(module)), module.name


def test_the_previous_understand_run_keeps_its_public_shape() -> None:
    """`understand-run` دست‌نخورده است: همان تابع‌ها و امضا، و دستورش هنوز ثبت است."""
    assert list(inspect.signature(ur.run_replay).parameters) == [
        "session",
        "cases",
        "client",
        "max_cost_usd",
        "dry_run",
        "progress",
    ]
    source = (SRC / "cli.py").read_text(encoding="utf-8")
    assert '"understand-run"' in source and "cmd_understand_run" in source
    assert '"retrieval-shadow-run"' in source and "cmd_retrieval_shadow_run" in source


# ---------------------------------------------------------------------------
# خط فرمان
# ---------------------------------------------------------------------------


def _args(tmp_path: Path, **overrides: object) -> Namespace:
    values: dict[str, object] = {
        "cases": None,
        "from_db": 10,
        "limit": 60,
        "seed": 7,
        "max_cost_usd": 1.0,
        "out": str(tmp_path / "out"),
        "dry_run": False,
    }
    values.update(overrides)
    return Namespace(**values)


async def test_the_command_dry_run_counts_and_writes_nothing(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _message(session, account, "ریسک به ریوارد یعنی چه؟", 1)

    code = await cli.cmd_retrieval_shadow_run(_args(tmp_path, dry_run=True))

    out = capsys.readouterr().out
    assert code == 0 and "--dry-run بود" in out
    assert not (tmp_path / "out").exists()


async def test_the_command_runs_end_to_end_and_writes_the_two_files(
    session: AsyncSession,
    account: MentorAccount,
    kb: None,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _message(session, account, "ریسک به ریوارد یعنی چه؟", 1)
    client = _Router({"ریسک به ریوارد": _payload(_part(1, "ریسک به ریوارد یعنی چه؟"))})
    monkeypatch.setattr("mentorai.ai.providers.build_client", lambda: client)
    before = await _snapshot(session)

    code = await cli.cmd_retrieval_shadow_run(_args(tmp_path))

    out = capsys.readouterr().out
    assert code == 0
    out_dir = tmp_path / "out"
    assert sorted(p.name for p in out_dir.iterdir()) == [
        "retrieval_shadow.json",
        "retrieval_shadow_summary.txt",
    ]
    for path in out_dir.iterdir():
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
    doc = json.loads((out_dir / "retrieval_shadow.json").read_text(encoding="utf-8"))
    assert doc["version"] == rs.SHADOW_VERSION and doc["parts"][0]["has_hits"] is True
    assert doc["retrieval"]["embedder"] == "none (text only)", "بازیابی فعلی: فقط متنی"
    summary = (out_dir / "retrieval_shadow_summary.txt").read_text(encoding="utf-8")
    assert "total parts: 1" in summary and "ریسک به ریوارد" not in summary
    assert "خلاصه (بی‌متن)" in out and "پیام واقعی" in out
    assert await _snapshot(session) == before


async def test_the_command_reports_a_broken_ai_configuration_without_a_traceback(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _message(session, account, "ریسک به ریوارد یعنی چه؟", 1)

    def broken() -> ScriptedClient:
        raise ValueError("AI_MODEL ناقص است")

    monkeypatch.setattr("mentorai.ai.providers.build_client", broken)

    code = await cli.cmd_retrieval_shadow_run(_args(tmp_path))

    assert code == 1
    assert "AI_MODEL ناقص است" in capsys.readouterr().err
    assert not (tmp_path / "out").exists()
