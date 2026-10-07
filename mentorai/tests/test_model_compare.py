"""مقایسه‌ی کور مدل‌ها (`model_compare.py`)، بدون هیچ فراخوانی واقعی."""

from __future__ import annotations

import argparse
import csv
import io
import json
import random
import stat
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession
from tests.test_media import xlsx

from mentorai import cli
from mentorai import model_compare as mc
from mentorai.ai.client import ModelCall
from mentorai.ai.prompt import SYSTEM_PROMPT
from mentorai.ai.runtime import silence_reason_for
from mentorai.ai.schema import ModelAnswer
from mentorai.db.models import ExcludedChat, MentorAccount, Sender
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.ingest import ingest_csv
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound

NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)

# پرسش‌هایی که عیناً در پایگاه دانش هستند، تا جستجوی متنی سندشان را پیدا کند.
KB = {
    "دوره مقدماتی چیست؟": "دوره مقدماتی شامل شانزده جلسه است.",
    "بک‌تست چیست؟": "بک‌تست یعنی آزمودن استراتژی روی داده‌ی گذشته.",
    "دراوداون چیست؟": "دراوداون افت سرمایه از اوج تا کف است.",
    "پروفیت فکتور چیست؟": "پروفیت فکتور نسبت سود ناخالص به زیان ناخالص است.",
}


def _answer(
    text: str = "پاسخ خوب.", *, confidence: float = 0.9, needs_human: bool = False
) -> ModelAnswer:
    return ModelAnswer(
        answer=text,
        confidence=confidence,
        needs_human=needs_human,
        reason="منبع",
        used_chunk_ids=[],
    )


class FakeClient:
    """یک نامزد ساختگی. ورودی هر فراخوانی را ثبت می‌کند و پاسخ را از یک تابع می‌گیرد."""

    def __init__(
        self,
        name: str,
        reply: Any = None,
        *,
        input_tokens: int = 3000,
        output_tokens: int = 400,
    ) -> None:
        self.model = name
        self.effort = None
        self.calls: list[tuple[str, str]] = []
        self._reply = reply or (lambda user: _answer())
        self._tokens = (input_tokens, output_tokens)

    async def complete(self, *, system: str, user: str) -> ModelCall:
        self.calls.append((system, user))
        reply = self._reply(user)
        i, o = self._tokens
        if reply is None:
            return ModelCall(
                answer=None,
                model=self.model,
                latency_ms=100,
                input_tokens=i,
                output_tokens=o,
                error="پاسخ بریده شد",
            )
        return ModelCall(
            answer=reply, model=self.model, latency_ms=2000, input_tokens=i, output_tokens=o
        )

    async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> Any:
        raise AssertionError("مقایسه فقط مسیر پاسخ را می‌سنجد")

    async def describe_image(self, **_: Any) -> Any:
        raise AssertionError("مقایسه تصویر نمی‌خواند")


def _candidates() -> list[mc.Candidate]:
    return mc.parse_candidates(
        ["anthropic:claude-sonnet-5-5:medium", "openai:gpt-test:low@1.0/4.0"]
    )


def _factory(clients: dict[str, FakeClient]) -> mc.ClientFactory:
    return lambda candidate: clients[candidate.id]  # type: ignore[return-value]


@pytest.fixture
async def kb(session: AsyncSession, tmp_path: Path) -> None:
    path = tmp_path / "kb.csv"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "source_class",
                "category",
                "question",
                "answer",
                "authority",
                "valid_until",
                "owner",
                "notes",
            ]
        )
        for question, answer in KB.items():
            writer.writerow(["official", "آموزش", question, answer, "fact", "", "", ""])
    await ingest_csv(session, path, embedder=HashingEmbedder())
    await session.commit()


def _cases(*questions: str) -> list[mc.Case]:
    return [mc.Case(id=f"q{i}", question=q) for i, q in enumerate(questions, start=1)]


# ---------------------------------------------------------------------------
# نامزدها
# ---------------------------------------------------------------------------


def test_a_known_model_takes_its_price_from_the_table() -> None:
    c = mc.parse_candidate("anthropic:claude-sonnet-5-5:medium", index=1)
    assert (c.provider, c.model, c.effort) == ("anthropic", "claude-sonnet-5-5", "medium")
    assert (c.price.input_usd, c.price.output_usd) == (2.0, 10.0)  # type: ignore[union-attr]


def test_the_effort_in_the_name_is_the_one_actually_sent() -> None:
    assert mc.parse_candidate("anthropic:claude-opus-5-5", index=1).effort == "medium"
    assert mc.parse_candidate("openai:gpt-test@1/4", index=1).effort is None


def test_an_unknown_model_needs_a_price_in_the_spec() -> None:
    with pytest.raises(mc.CompareError, match="قیمت"):
        mc.parse_candidate("openai:gpt-test:low", index=1)

    c = mc.parse_candidate("openai:gpt-test:low@0.25/2.0", index=1)
    assert (c.price.input_usd, c.price.output_usd) == (0.25, 2.0)  # type: ignore[union-attr]
    assert mc.parse_candidate("openai:gpt-test@1/4", index=1).effort is None


@pytest.mark.parametrize(
    "spec", ["claude-sonnet-5-5", "gemini:gemini-x@1/2", "openai:", "openai:m:low@x/y"]
)
def test_a_malformed_candidate_is_refused(spec: str) -> None:
    with pytest.raises(mc.CompareError):
        mc.parse_candidate(spec, index=1)


def test_a_comparison_needs_two_different_candidates() -> None:
    with pytest.raises(mc.CompareError, match="دو نامزد"):
        mc.parse_candidates(["anthropic:claude-sonnet-5-5"])
    with pytest.raises(mc.CompareError, match="یکسان"):
        mc.parse_candidates(["anthropic:claude-sonnet-5-5:low", "anthropic:claude-sonnet-5-5:low"])


def test_the_real_factory_refuses_what_the_real_clients_would_reject() -> None:
    from mentorai.config import Settings

    settings = Settings(  # type: ignore[call-arg]
        database_url="postgresql+asyncpg://u:p@h/d",
        session_encryption_key="k",
        telegram_api_id=1,
        telegram_api_hash="h",
    )
    build = mc.default_client_factory(settings)

    with pytest.raises(mc.CompareError, match="effort"):
        build(mc.parse_candidate("anthropic:claude-haiku-4-5", index=1))
    with pytest.raises(mc.CompareError, match="OPENAI_API_KEY"):
        build(mc.parse_candidate("openai:gpt-test@1/4", index=1))


# ---------------------------------------------------------------------------
# پرسش‌ها
# ---------------------------------------------------------------------------


def test_personal_details_are_masked_but_market_numbers_are_not() -> None:
    masked = mc.mask_personal(
        "شماره‌ام ۰۹۱۲۳۴۵۶۷۸۹ و ایمیل a.b@example.com و @my_handle؛ قیمت ۱۹۰۰ و لات 0.1"
    )

    assert "۰۹۱۲۳۴۵۶۷۸۹" not in masked and "example.com" not in masked
    assert "@my_handle" not in masked
    assert "۱۹۰۰" in masked and "0.1" in masked, "عدد بازار خود پرسش است"


@pytest.mark.parametrize(
    "written",
    [
        "0912 345 6789",
        "0912-345-6789",
        "+98 912 345 6789",
        "6037-9912-3456-7890",
        "۰۹۱۲ ۳۴۵ ۶۷۸۹",
        "شماره‌ام 09123456789 است",
    ],
)
def test_a_phone_or_card_number_is_masked_however_it_is_written(written: str) -> None:
    masked = mc.mask_personal(f"لطفاً زنگ بزنید {written} ممنون")

    assert mc.MASK in masked
    digits_left = "".join(ch for ch in masked.translate(mc._DIGITS) if ch.isdigit())
    assert len(digits_left) < 4, f"رقم‌های شماره جا ماند: {masked}"


def test_short_numbers_dates_and_decimals_are_left_alone() -> None:
    kept = "قیمت 1900 و 1950 با لات 0.1 و تاریخ 2026-10-07 و عدد 0.00012345"
    assert mc.mask_personal(kept) == kept


@pytest.mark.parametrize(
    "dangerous",
    ['=HYPERLINK("http://evil.test","x")', "+1+1", "-2+3", "@SUM(1)", "  =1+1", "\t=1"],
)
def test_nothing_a_student_or_a_model_wrote_can_run_as_a_formula(dangerous: str) -> None:
    """منتور برگه را در اکسل باز می‌کند؛ متن دانشجو و پاسخ مدل نامطمئن‌اند."""
    run = _fake_run(1)
    run.cases[0].question = dangerous
    run.cases[0].sources = dangerous
    run.cases[0].results[run.candidates[0].id].text = dangerous
    run.cases[0].results[run.candidates[1].id].text = "عادی"

    cells = [c for row in csv.reader(io.StringIO(mc.build_sheet(run))) for c in row]

    assert dangerous not in cells, "سلول بدون پیشوند به اکسل می‌رسد"
    for cell in cells:
        assert cell.lstrip()[:1] not in ("=", "+", "-", "@", "\t", "\r") or not cell.strip()
    assert "'" + dangerous in cells


def test_ordinary_text_is_not_touched() -> None:
    for fine in ("سلام، دوره چیست؟", "— پاسخی نداد —", "3 جلسه است", ""):
        assert mc.safe_cell(fine) == fine


def test_a_case_id_from_a_file_can_never_start_a_formula(tmp_path: Path) -> None:
    path = tmp_path / "cases.csv"
    path.write_text(
        "id,question\n=cmd|x,سؤال شماره یک چیست؟\n-5,سؤال شماره دو چیست؟\n,سؤال سه چیست؟\n"
        "a b/c,سؤال چهار چیست؟\n",
        encoding="utf-8",
    )

    ids = [c.id for c in mc.load_cases(path, limit=10, seed=1)]

    assert ids == ["_cmd_x", "q-5", "q3", "a_b_c"]
    assert all(i[0] not in "=+-@" for i in ids)


def test_cases_are_read_deduplicated_and_sampled_reproducibly(tmp_path: Path) -> None:
    path = tmp_path / "cases.csv"
    rows = [f"سؤال شماره {i} چیست؟" for i in range(50)] + ["سؤال شماره 3 چیست؟"]
    path.write_text("question\n" + "\n".join(rows), encoding="utf-8-sig")

    first = mc.load_cases(path, limit=10, seed=7)
    again = mc.load_cases(path, limit=10, seed=7)
    other = mc.load_cases(path, limit=10, seed=8)

    assert [c.id for c in first] == [c.id for c in again]
    assert [c.id for c in first] != [c.id for c in other]
    assert len({c.question for c in mc.load_cases(path, limit=1000, seed=1)}) == 50


def test_a_file_without_the_question_column_is_refused(tmp_path: Path) -> None:
    path = tmp_path / "x.csv"
    path.write_text("پرسش\nسلام", encoding="utf-8")
    with pytest.raises(mc.CompareError, match="question"):
        mc.load_cases(path, limit=5, seed=1)


async def _message(
    session: AsyncSession, account: MentorAccount, n: int, body: str, **kw: Any
) -> None:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=kw.get("chat_id", 1000 + n),
        message_id=n,
        sender_user_id=1000 + n,
        username=None,
        first_name="د",
        last_name=None,
        raw_text=body,
        media_type=kw.get("media_type"),
        reply_to_message_id=None,
        sent_at=NOON,
        is_private=True,
        is_outgoing=kw.get("outgoing", False),
    )
    await record_inbound(
        session, account, inbound, sender=Sender.mentor if kw.get("outgoing") else Sender.student
    )


async def test_real_questions_come_only_from_students_text_and_included_chats(
    session: AsyncSession, account: MentorAccount
) -> None:
    await _message(session, account, 1, "دوره مقدماتی چند جلسه است؟")
    await _message(session, account, 2, "دوره مقدماتی چند جلسه است؟")  # تکراری
    await _message(session, account, 3, "بک‌تست را از کجا شروع کنم؟")
    await _message(session, account, 4, "کوتاه")  # کوتاه‌تر از پرسش
    await _message(session, account, 5, "عکس چارت من را ببین لطفاً", media_type="photo")
    await _message(session, account, 6, "پاسخ خود منتور به دانشجو", outgoing=True)
    await _message(session, account, 7, "پرسش همکار که دانشجو نیست", chat_id=777)
    session.add(ExcludedChat(account_id=account.id, telegram_peer_id=777, reason="همکار"))
    await session.commit()

    cases = await mc.sample_from_database(session, limit=50, seed=1)

    assert sorted(c.question for c in cases) == [
        "بک‌تست را از کجا شروع کنم؟",
        "دوره مقدماتی چند جلسه است؟",
    ]


# ---------------------------------------------------------------------------
# اجرا
# ---------------------------------------------------------------------------


async def test_every_candidate_gets_the_same_documents_and_the_production_prompt(
    session: AsyncSession, kb: None
) -> None:
    a, b = FakeClient("a"), FakeClient("b")
    c1, c2 = _candidates()

    run = await mc.run_comparison(
        session,
        _cases("دوره مقدماتی چیست؟", "بک‌تست چیست؟"),
        [c1, c2],
        make_client=_factory({c1.id: a, c2.id: b}),
    )

    assert len(run.cases) == 2 and len(a.calls) == len(b.calls) == 2
    assert a.calls == b.calls, "ورودی دو مدل باید بایت‌به‌بایت یکی باشد"
    assert all(system == SYSTEM_PROMPT for system, _ in a.calls)
    assert "شانزده جلسه" in a.calls[0][1], "سند بازیابی‌شده در ورودی است"


async def test_the_real_run_shuffles_the_answers_reproducibly_and_without_bias(
    session: AsyncSession, kb: None
) -> None:
    """ترتیب را `run_comparison` می‌سازد، نه `_fake_run`؛ پس باید خودش آزموده شود.

    اگر ترتیب ثابت بماند، نامزد اول همیشه «پاسخ ۱» است و سوگیری جایگاه نتیجه را
    خراب می‌کند، بی‌آنکه چیزی خطا بدهد.
    """
    c1, c2 = _candidates()

    async def run(seed: int) -> list[list[str]]:
        result = await mc.run_comparison(
            session,
            [mc.Case(id=f"q{i}", question="دوره مقدماتی چیست؟") for i in range(60)],
            [c1, c2],
            make_client=_factory({c1.id: FakeClient("a"), c2.id: FakeClient("b")}),
            seed=seed,
            max_cost_usd=100,
        )
        return [case.order for case in result.cases]

    first, again, other = await run(7), await run(7), await run(8)

    assert first == again
    assert first != other
    leading = sum(1 for order in first if order[0] == c1.id) / len(first)
    assert 0.3 < leading < 0.7
    assert all(sorted(order) == [c1.id, c2.id] for order in first)


async def test_questions_the_model_never_sees_in_production_are_not_sent_to_it(
    session: AsyncSession, kb: None
) -> None:
    a, b = FakeClient("a"), FakeClient("b")
    c1, c2 = _candidates()

    run = await mc.run_comparison(
        session,
        _cases(
            "قیمت دوره مقدماتی چقدر است؟",  # قاعده‌ی مالی
            "با منتور صحبت کنم",  # درخواست انسان
            "zzzz qqqq xxxx",  # سندی ندارد
            "دوره مقدماتی چیست؟",
        ),
        [c1, c2],
        make_client=_factory({c1.id: a, c2.id: b}),
    )

    assert len(a.calls) == len(b.calls) == 1
    assert run.excluded == Counter(
        {"rule_money": 1, "rule_explicit_human_request": 1, "no_sources": 1}
    )


async def test_the_production_gate_decides_what_would_be_sent(
    session: AsyncSession, kb: None
) -> None:
    answers = {
        "دوره مقدماتی چیست؟": _answer(confidence=0.7),  # دقیقاً روی آستانه
        "بک‌تست چیست؟": _answer(confidence=0.69),
        "دراوداون چیست؟": _answer(needs_human=True),
        "پروفیت فکتور چیست؟": _answer("قیمتش ۵۰۰ هزار تومان است."),  # قیمتِ بی‌منبع
    }

    def reply(user: str) -> ModelAnswer | None:
        question = user.rsplit("سؤال دانشجو:\n", 1)[1]
        return answers[question]

    client, other = FakeClient("a", reply), FakeClient("b", reply)
    c1, c2 = _candidates()
    run = await mc.run_comparison(
        session,
        _cases(*answers),
        [c1, c2],
        make_client=_factory({c1.id: client, c2.id: other}),
    )

    outcomes = {case.question: case.results[c1.id] for case in run.cases}
    assert outcomes["دوره مقدماتی چیست؟"].outcome == "answer"
    assert outcomes["بک‌تست چیست؟"].silence_reason == "low_confidence"
    assert outcomes["دراوداون چیست؟"].silence_reason == "model_flagged"
    assert outcomes["پروفیت فکتور چیست؟"].silence_reason == "ungrounded_money"
    # و همین تابع است که تولید صدا می‌زند؛ نه کپی آن
    assert silence_reason_for(_answer(confidence=0.69), []) == ("low_confidence", None)


async def test_a_failed_call_is_recorded_not_hidden(session: AsyncSession, kb: None) -> None:
    c1, c2 = _candidates()
    run = await mc.run_comparison(
        session,
        _cases("دوره مقدماتی چیست؟"),
        [c1, c2],
        make_client=_factory({c1.id: FakeClient("a", lambda u: None), c2.id: FakeClient("b")}),
    )

    failed = run.cases[0].results[c1.id]
    assert failed.outcome == "error" and failed.text is None and "بریده" in (failed.error or "")


async def test_cost_comes_from_each_candidates_own_price(session: AsyncSession, kb: None) -> None:
    c1, c2 = _candidates()  # ۲/۱۰ و ۱/۴
    run = await mc.run_comparison(
        session,
        _cases("دوره مقدماتی چیست؟"),
        [c1, c2],
        make_client=_factory({c1.id: FakeClient("a"), c2.id: FakeClient("b")}),
    )

    results = run.cases[0].results
    assert results[c1.id].cost_usd == pytest.approx(3000 * 2 / 1e6 + 400 * 10 / 1e6)
    assert results[c2.id].cost_usd == pytest.approx(3000 * 1 / 1e6 + 400 * 4 / 1e6)


async def test_a_run_that_would_cost_too_much_stops_after_the_first_question(
    session: AsyncSession, kb: None
) -> None:
    """خطای برآورد باید با چند سنت معلوم شود، نه با خالی شدن حساب."""
    a, b = FakeClient("a", input_tokens=200_000), FakeClient("b", input_tokens=200_000)
    c1, c2 = _candidates()

    with pytest.raises(mc.CostLimitExceeded):
        await mc.run_comparison(
            session,
            _cases(
                *(["دوره مقدماتی چیست؟", "بک‌تست چیست؟", "دراوداون چیست؟", "پروفیت فکتور چیست؟"] * 5)
            ),
            [c1, c2],
            make_client=_factory({c1.id: a, c2.id: b}),
            max_cost_usd=0.5,
        )

    assert len(a.calls) == 1, "فقط نخستین پرسش اجرا شد"


async def test_a_run_that_overshoots_midway_keeps_what_it_has(
    session: AsyncSession, kb: None
) -> None:
    class Growing(FakeClient):
        async def complete(self, *, system: str, user: str) -> ModelCall:
            self._tokens = (1000 if not self.calls else 400_000, 100)
            return await super().complete(system=system, user=user)

    a, b = Growing("a"), Growing("b")
    c1, c2 = _candidates()
    run = await mc.run_comparison(
        session,
        _cases("دوره مقدماتی چیست؟", "بک‌تست چیست؟", "دراوداون چیست؟", "پروفیت فکتور چیست؟"),
        [c1, c2],
        make_client=_factory({c1.id: a, c2.id: b}),
        max_cost_usd=1.0,
    )

    assert run.stopped_early and 1 < len(run.cases) < 4


async def test_a_dry_run_counts_but_never_calls_a_model(session: AsyncSession, kb: None) -> None:
    a, b = FakeClient("a"), FakeClient("b")
    c1, c2 = _candidates()

    run = await mc.run_comparison(
        session,
        _cases("دوره مقدماتی چیست؟", "با منتور صحبت کنم"),
        [c1, c2],
        make_client=_factory({c1.id: a, c2.id: b}),
        dry_run=True,
    )

    assert a.calls == [] and b.calls == [] and run.spent_usd == 0
    # و هیچ کلاینتی ساخته نمی‌شود، پس کلید هم لازم نیست
    built: list[str] = []
    await mc.run_comparison(
        session,
        _cases("دوره مقدماتی چیست؟"),
        [c1, c2],
        make_client=lambda c: built.append(c.id),  # type: ignore[arg-type,return-value]
        dry_run=True,
    )
    assert built == []
    assert len(run.cases) == 1 and run.excluded["rule_explicit_human_request"] == 1


# ---------------------------------------------------------------------------
# برگه‌ی کور
# ---------------------------------------------------------------------------


def _fake_run(n: int = 8, seed: int = 7) -> mc.RunData:
    """اجرای ساختگی بدون پایگاه داده. نامزد اول همیشه «الف» می‌نویسد، دومی «ب»."""
    candidates = _candidates()
    run = mc.RunData(candidates=candidates, seed=seed, created="2026-10-07T10:00:00+00:00")
    for i in range(n):
        order = [c.id for c in candidates]
        random.Random(f"{seed}:q{i}").shuffle(order)
        run.cases.append(
            mc.CaseRun(
                id=f"q{i}",
                question=f"پرسش شماره {i}؟",
                sources="[official] عنوان: متن سند",
                order=order,
                results={
                    candidates[0].id: mc.CandidateResult(
                        outcome="answer",
                        text="پاسخ الف",
                        confidence=0.9,
                        needs_human=False,
                        input_tokens=3000,
                        output_tokens=400,
                        latency_ms=2000,
                        cost_usd=0.01,
                    ),
                    candidates[1].id: mc.CandidateResult(
                        outcome="answer",
                        text="پاسخ ب",
                        confidence=0.9,
                        needs_human=False,
                        input_tokens=3000,
                        output_tokens=400,
                        latency_ms=3000,
                        cost_usd=0.02,
                    ),
                },
            )
        )
    return run


def test_the_blind_sheet_never_names_a_model_or_a_provider() -> None:
    sheet = mc.build_sheet(_fake_run()).lower()

    for word in (
        "claude",
        "sonnet",
        "gpt",
        "openai",
        "anthropic",
        "gpt-test",
        "effort",
        "c1",
        "c2",
    ):
        assert word not in sheet, f"«{word}» در برگه‌ی کور آمده و داور را لو می‌دهد"


def test_the_sheet_has_a_column_group_per_candidate_and_marks_what_would_be_sent() -> None:
    run = _fake_run(2)
    run.cases[0].results[run.candidates[0].id] = mc.CandidateResult(
        outcome="silence", text="پاسخ ساکت‌شده", silence_reason="low_confidence"
    )
    run.cases[1].results[run.candidates[1].id] = mc.CandidateResult(outcome="error", error="بریده")

    rows = list(csv.reader(io.StringIO(mc.build_sheet(run))))

    assert rows[0] == mc.sheet_header(2) and len(rows[0]) == 3 + 2 * 4 + 1
    flat = " ".join(" ".join(r) for r in rows)
    assert mc.SILENT in flat and mc.SENT in flat and mc.NO_ANSWER in flat
    assert "پاسخ ساکت‌شده" in flat, "متن ساکت‌شده هم دیده می‌شود تا داور درستی سکوت را بسنجد"
    assert "low_confidence" not in flat, "دلیل فنی، سبکِ مدل را لو می‌دهد و به داور مربوط نیست"


def test_the_order_is_reproducible_and_balanced() -> None:
    run = _fake_run(400)
    again = _fake_run(400)
    other = _fake_run(400, seed=8)
    first = run.candidates[0].id

    assert [c.order for c in run.cases] == [c.order for c in again.cases]
    assert [c.order for c in run.cases] != [c.order for c in other.cases]
    leading = sum(1 for c in run.cases if c.order[0] == first) / len(run.cases)
    assert 0.4 < leading < 0.6, "اگر نامزدی اغلب اول بیاید، سوگیری جایگاه نتیجه را خراب می‌کند"


def test_the_files_are_private_and_the_sheet_opens_in_excel(tmp_path: Path) -> None:
    paths = mc.write_run(_fake_run(2), tmp_path / "out")

    assert stat.S_IMODE((tmp_path / "out").stat().st_mode) == 0o700
    for path in paths.values():
        assert stat.S_IMODE(path.stat().st_mode) == 0o600, path.name
    assert paths["sheet"].read_bytes().startswith(b"\xef\xbb\xbf"), (
        "بدون BOM اکسل فارسی را خراب می‌خواند"
    )
    assert "gpt-test" in paths["key"].read_text(encoding="utf-8")
    assert "gpt-test" not in paths["sheet"].read_text(encoding="utf-8")
    assert "امتیاز" in paths["guide"].read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# خواندن برگه‌ی پرشده
# ---------------------------------------------------------------------------


def _filled_rows(
    run: mc.RunData, score_for: Any, invented_for: Any = lambda c, i: ""
) -> list[list[str]]:
    """برگه را طوری پر می‌کند که امتیاز هر پاسخ فقط به نامزد واقعی‌اش بستگی دارد."""
    rows = list(csv.reader(io.StringIO(mc.build_sheet(run))))
    for row, case in zip(rows[1:], run.cases, strict=True):
        for k, cid in enumerate(case.order):
            base = 3 + 4 * k
            row[base + 2] = str(score_for(cid, case))
            row[base + 3] = invented_for(cid, case)
    return rows


def _write_csv(path: Path, rows: list[list[str]], *, delimiter: str = ",") -> Path:
    buffer = io.StringIO()
    csv.writer(buffer, delimiter=delimiter, lineterminator="\n").writerows(rows)
    path.write_text("﻿" + buffer.getvalue(), encoding="utf-8")
    return path


def test_grades_survive_persian_digits_a_semicolon_delimiter_and_ragged_rows(
    tmp_path: Path,
) -> None:
    run = _fake_run(3)
    rows = _filled_rows(run, lambda cid, case: "۳")  # ارقام فارسی
    rows[1][3 + 3] = "بله"
    rows[2] = rows[2][:-3]  # اکسل ستون‌های خالی انتهایی را گاهی می‌اندازد
    path = _write_csv(tmp_path / "g.csv", rows, delimiter=";")

    grades, problems = mc.load_grades(path, position_count=2)

    assert grades[("q0", 1)] == mc.Grade(3, True)
    assert grades[("q0", 2)] == mc.Grade(3, False)
    assert grades[("q1", 1)].score == 3
    assert problems == []


def test_a_mistyped_cell_is_reported_not_dropped_silently(tmp_path: Path) -> None:
    run = _fake_run(2)
    rows = _filled_rows(run, lambda cid, case: 2)
    rows[1][3 + 2] = "5"
    rows[2][3 + 2] = "خوب"
    rows[1][3 + 3] = "شاید"
    path = _write_csv(tmp_path / "g.csv", rows)

    grades, problems = mc.load_grades(path, position_count=2)

    assert len(problems) == 3
    assert any("5" in p for p in problems) and any("خوب" in p for p in problems)
    assert grades[("q0", 1)].score is None, "امتیاز نامعتبر امتیاز حساب نمی‌شود"


def test_an_xlsx_saved_by_excel_is_read_like_the_csv(tmp_path: Path) -> None:
    run = _fake_run(2)
    rows = _filled_rows(run, lambda cid, case: 3)
    path = tmp_path / "g.xlsx"
    path.write_bytes(xlsx(rows))

    grades, problems = mc.load_grades(path, position_count=2)

    assert grades[("q1", 2)].score == 3 and problems == []


def test_a_file_that_is_not_the_sheet_is_refused(tmp_path: Path) -> None:
    path = tmp_path / "other.csv"
    path.write_text("نام,سن\nعلی,3\n", encoding="utf-8")

    with pytest.raises(mc.CompareError, match="قالب برگه‌ی کور"):
        mc.load_grades(path, position_count=2)


def test_a_file_that_cannot_be_opened_says_what_to_do_not_a_traceback(tmp_path: Path) -> None:
    """درس تمرین روی کانتینر: فایلی که root با مجوز ۶۰۰ گذاشته برای کاربر کانتینر بسته است."""
    with pytest.raises(mc.CompareError, match="chmod 644"):
        mc.load_grades(tmp_path / "missing.csv", position_count=2)
    with pytest.raises(mc.CompareError, match="chmod 644"):
        mc.load_key(tmp_path / "missing.json")


# ---------------------------------------------------------------------------
# آمار و گزارش
# ---------------------------------------------------------------------------


def test_the_sign_test_is_exact() -> None:
    assert mc.sign_test_p(5, 5) == 1.0
    assert mc.sign_test_p(0, 0) == 1.0
    assert mc.sign_test_p(7, 3) == pytest.approx(0.34375)
    assert mc.sign_test_p(0, 10) == pytest.approx(2 / 1024)
    assert mc.sign_test_p(3, 7) == mc.sign_test_p(7, 3)


def test_the_wilson_interval_matches_the_known_values() -> None:
    lo, hi = mc.wilson(8, 10)
    assert (lo, hi) == (pytest.approx(0.4902, abs=0.002), pytest.approx(0.9433, abs=0.002))
    assert mc.wilson(0, 0) == (0.0, 0.0)
    lo0, hi0 = mc.wilson(0, 20)
    assert lo0 == 0.0 and 0.1 < hi0 < 0.2, "صفر از بیست یعنی «کمتر از ۱۶٪»، نه «صفر»"


def _report(
    run: mc.RunData, tmp_path: Path, score_for: Any, invented_for: Any = lambda c, i: ""
) -> str:
    path = _write_csv(tmp_path / "g.csv", _filled_rows(run, score_for, invented_for))
    key = mc.key_document(run)
    grades, problems = mc.load_grades(path, position_count=len(run.candidates))
    return mc.analyse_and_render(key, grades, problems)


def test_the_report_maps_each_position_back_to_the_right_model(tmp_path: Path) -> None:
    """مهم‌ترین آزمون: اگر نگاشت جایگاه به مدل غلط باشد، برنده برعکس اعلام می‌شود.

    ترتیب هر پرسش تصادفی است. پس اگر نگاشت ترتیب را نادیده بگیرد، میانگین هر دو
    نامزد حدود ۲ درمی‌آید، نه ۳ و ۱.
    """
    run = _fake_run(40)
    first, second = run.candidates

    text = _report(run, tmp_path, lambda cid, case: 3 if cid == first.id else 1)

    assert "میانگین امتیاز: 3.00" in text and "میانگین امتیاز: 1.00" in text
    section_a = text.split(f"■ {first.name}")[1].split("■")[0]
    section_b = text.split(f"■ {second.name}")[1].split("■")[0]
    assert "میانگین امتیاز: 3.00" in section_a
    assert "میانگین امتیاز: 1.00" in section_b
    assert f"{first.name} در برابر {second.name}: برد 40، باخت 0" in text
    assert f"{first.name} به‌طور معنی‌دار بهتر است" in text


def test_a_small_sample_is_called_a_hint_not_a_result(tmp_path: Path) -> None:
    run = _fake_run(10)

    text = _report(run, tmp_path, lambda cid, case: 3 if cid == run.candidates[0].id else 2)

    assert "نمونه کم است" in text
    assert "نشانه است، نه نتیجه" in text


def test_a_tie_is_never_declared_a_winner(tmp_path: Path) -> None:
    text = _report(_fake_run(40), tmp_path, lambda cid, case: 2)

    assert "هیچ تفاوتی دیده نشد" in text
    assert "به‌طور معنی‌دار بهتر" not in text


def test_a_difference_the_sample_cannot_support_is_said_so(tmp_path: Path) -> None:
    run = _fake_run(40)
    first = run.candidates[0]
    # الف در ۱۲ پرسش بهتر و در ۱۰ بدتر، بقیه مساوی

    def score(cid: str, case: mc.CaseRun) -> int:
        n = int(case.id[1:])
        if n < 12:
            return 3 if cid == first.id else 2
        if n < 22:
            return 2 if cid == first.id else 3
        return 2

    text = _report(run, tmp_path, score)

    assert "تفاوت قابل تشخیص نیست" in text


def test_invented_facts_and_the_gate_are_reported_per_candidate(tmp_path: Path) -> None:
    run = _fake_run(10)
    first, second = run.candidates
    # نامزد دوم: سه پاسخ ارسال‌شده‌اش ساخته‌شده است؛ دو پاسخ ساکت‌شده‌اش خوب بود
    for case in run.cases[:3]:
        case.results[second.id].outcome = "answer"
    for case in run.cases[3:5]:
        case.results[second.id] = mc.CandidateResult(
            outcome="silence",
            text="پاسخ ب",
            confidence=0.4,
            needs_human=False,
            silence_reason="low_confidence",
            latency_ms=1000,
        )
    for case in run.cases[5:]:
        case.results[second.id].outcome = "answer"

    text = _report(
        run,
        tmp_path,
        lambda cid, case: 3,
        lambda cid, case: "1" if cid == second.id and int(case.id[1:]) < 3 else "",
    )

    section_b = text.split(f"■ {second.name}")[1]
    assert "چیزی از خودش ساخته: 30٪ (3 از 10" in section_b
    assert "از پاسخ‌هایی که می‌رفتند (8 تا): 3 تا غلط یا ساخته‌شده بود" in section_b
    assert "از پاسخ‌هایی که ساکت می‌ماندند (2 تا): 2 تا خوب بود" in section_b
    assert "چیزی از خودش ساخته: 0٪" in text.split(f"■ {first.name}")[1].split("■")[0]


def test_the_threshold_table_shows_what_each_cutoff_would_have_let_through(tmp_path: Path) -> None:
    run = _fake_run(20)
    first = run.candidates[0]
    for i, case in enumerate(run.cases):
        case.results[first.id].confidence = 0.55 if i < 10 else 0.95
    # پاسخ‌های کم‌اطمینان بد بودند و پراطمینان‌ها خوب
    text = _report(
        run,
        tmp_path,
        lambda cid, case: (0 if int(case.id[1:]) < 10 else 3) if cid == first.id else 3,
    )

    section = text.split("آستانه‌ی اطمینان (پاسخ فقط")[1].split(f"{run.candidates[1].name}:")[0]
    assert "0.50  | 20 | 50٪ | 10" in section, "بدون آستانه نصف پاسخ‌ها خوب است و ده تا غلط می‌رود"
    assert "0.60  | 10 | 100٪ | 0" in section
    assert "کمترین آستانه‌ای که در آن هیچ پاسخ غلط یا ساخته‌شده‌ای نمی‌رفت: 0.60" in section


def test_the_report_never_repeats_what_the_students_wrote(tmp_path: Path) -> None:
    """گزارش جایی دست‌به‌دست می‌شود که کلید و برگه نباید برود."""
    text = _report(_fake_run(12), tmp_path, lambda cid, case: 3)

    assert "پرسش شماره" not in text and "متن سند" not in text and "پاسخ الف" not in text


def test_problems_and_early_stops_are_visible_in_the_report(tmp_path: Path) -> None:
    run = _fake_run(5)
    run.stopped_early = True
    run.excluded["rule_money"] = 4
    rows = _filled_rows(run, lambda cid, case: 3)
    rows[1][3 + 2] = "9"
    path = _write_csv(tmp_path / "g.csv", rows)
    grades, problems = mc.load_grades(path, position_count=2)

    text = mc.analyse_and_render(mc.key_document(run), grades, problems)

    assert "به سقف هزینه خورد" in text and "rule_money: 4" in text
    assert "1 خانه‌ی نامعتبر" in text


# ---------------------------------------------------------------------------
# فرمان‌ها
# ---------------------------------------------------------------------------


async def test_the_commands_run_end_to_end_and_the_report_unblinds(
    session: AsyncSession,
    kb: None,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    cases = tmp_path / "cases.csv"
    cases.write_text(
        "question\n" + "\n".join(KB) + "\nقیمت دوره مقدماتی چقدر است؟\n", encoding="utf-8"
    )
    clients: dict[str, FakeClient] = {}

    def fake_factory(_settings: Any) -> mc.ClientFactory:
        def build(candidate: mc.Candidate) -> Any:
            reply = (
                (lambda u: _answer("پاسخ الف"))
                if candidate.id == "c1"
                else (lambda u: _answer("پاسخ ب"))
            )
            clients[candidate.id] = FakeClient(candidate.model, reply)
            return clients[candidate.id]

        return build

    monkeypatch.setattr(mc, "default_client_factory", fake_factory)
    out = tmp_path / "out"
    args = argparse.Namespace(
        candidate=["anthropic:claude-sonnet-5-5:medium", "openai:gpt-test:low@1.0/4.0"],
        cases=str(cases),
        from_db=None,
        limit=60,
        seed=7,
        max_cost_usd=5.0,
        out=str(out),
        dry_run=False,
    )

    assert await cli.cmd_compare_run(args) == 0
    printed = capsys.readouterr().out
    assert "rule_money: 1" in printed and "هرگز" not in printed.split("برگه‌ی داور")[0]
    assert (out / mc.SHEET_NAME).exists() and (out / mc.KEY_NAME).exists()

    rows = list(csv.reader(io.StringIO((out / mc.SHEET_NAME).read_text(encoding="utf-8-sig"))))
    key = json.loads((out / mc.KEY_NAME).read_text(encoding="utf-8"))
    assert len(rows) - 1 == len(KB) == len(key["cases"])
    # داور همیشه «پاسخ الف» را ۳ و «پاسخ ب» را ۱ می‌دهد، در هر جایگاهی که باشد
    for row in rows[1:]:
        for k in range(2):
            base = 3 + 4 * k
            row[base + 2] = "3" if row[base] == "پاسخ الف" else "1"
    graded = _write_csv(tmp_path / "graded.csv", rows)

    assert (
        await cli.cmd_compare_report(
            argparse.Namespace(key=str(out / mc.KEY_NAME), graded=str(graded))
        )
        == 0
    )
    report = capsys.readouterr().out
    assert report.split("■ anthropic:claude-sonnet-5-5:medium")[1].startswith(
        "\n  میانگین امتیاز: 3.00"
    )
    assert (out / mc.REPORT_NAME).exists()


async def test_a_dry_run_writes_nothing_and_a_bad_spec_says_why(
    session: AsyncSession,
    kb: None,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    cases = tmp_path / "cases.csv"
    cases.write_text("question\nدوره مقدماتی چیست؟\n", encoding="utf-8")
    base = {"cases": str(cases), "from_db": None, "limit": 60, "seed": 7, "max_cost_usd": 5.0}

    bad = argparse.Namespace(
        candidate=["openai:gpt-test:low", "anthropic:claude-sonnet-5-5"],
        out=str(tmp_path / "x"),
        dry_run=True,
        **base,
    )
    assert await cli.cmd_compare_run(bad) == 1
    assert "قیمت" in capsys.readouterr().err

    good = argparse.Namespace(
        candidate=["anthropic:claude-sonnet-5-5", "anthropic:claude-opus-5-5"],
        out=str(tmp_path / "x"),
        dry_run=True,
        **base,
    )
    assert await cli.cmd_compare_run(good) == 0
    assert not (tmp_path / "x").exists()
