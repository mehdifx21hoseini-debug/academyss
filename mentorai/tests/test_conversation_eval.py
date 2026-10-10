"""ارزیابی مکالمه (`conversation-eval-*`، ADR-052).

⚠️ این آزمون‌ها **کیفیت زبانی را اثبات نمی‌کنند**. چیزی که می‌سنجند ایمنی و درستی ابزار است:
هیچ پیامی به تلگرام نمی‌رود، هیچ ردیفی در پایگاه داده نوشته نمی‌شود، کلید یا شناسه‌ی واقعی چاپ
نمی‌شود، مدل فقط با تأیید صریح صدا زده می‌شود، سقف هزینه رعایت می‌شود، بازوی A همان ورودی
مسیر زنده را می‌سازد و بازوی C فقط لحن را عوض می‌کند. مدل در همه‌جا جعلی است.
"""

from __future__ import annotations

import ast
import csv
import io
import json
import re
import stat
from argparse import Namespace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import cli
from mentorai import model_compare as mc
from mentorai.ai import conversation_eval as ce
from mentorai.ai.client import ModelCall, ScriptedClient
from mentorai.ai.prompt import SYSTEM_PROMPT_V2 as SYSTEM_PROMPT
from mentorai.ai.prompt import build_system_prompt
from mentorai.ai.runtime import HISTORY_TURNS, handle_message
from mentorai.ai.schema import ModelAnswer
from mentorai.db.models import MemorySource, MentorAccount, Message, Outcome, Sender
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.ingest import ingest_csv
from mentorai.memory.policy import Candidate
from mentorai.memory.store import apply_candidates
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound

SRC = Path(ce.__file__).resolve().parents[2]
TONE_VARIANTS = Path(__file__).resolve().parents[1] / "tone-variants"
MODULE = Path(ce.__file__)
MODEL = "claude-sonnet-5-5"

PHONE = "09121234567"
EMAIL = "reza.secret@example.com"
HANDLE = "@reza_secret_id"
STUDENT_NAME = "رضا"
MENTOR_NAME = "منتور الف"
OTHER_CHAT_SENTINEL = "سنتینلمنحصربهفردگفتگودیگر"

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

_clock = [0]


def _now() -> datetime:
    _clock[0] += 1
    return datetime(2026, 9, 2, 12, 0, tzinfo=UTC) + timedelta(seconds=_clock[0])


async def _say(
    session: AsyncSession,
    account: MentorAccount,
    *,
    chat: int,
    mid: int,
    body: str,
    who: str = "student",
    first_name: str = "دانشجو",
) -> int:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=chat,
        message_id=mid,
        sender_user_id=chat if who == "student" else 9000 + chat,
        username=None,
        first_name=first_name,
        last_name=None,
        raw_text=body,
        media_type=None,
        reply_to_message_id=None,
        sent_at=_now(),
        is_private=True,
        is_outgoing=who != "student",
    )
    result = await record_inbound(session, account, inbound, sender=Sender(who))
    await session.commit()
    assert result.message_id is not None
    return result.message_id


@pytest.fixture
async def knowledge(session: AsyncSession, tmp_path: Path) -> None:
    path = tmp_path / "kb.csv"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(COLUMNS)
        writer.writerow(
            [
                "official",
                "دوره‌ها",
                "دوره مقدماتی شامل چه چیزهایی است؟",
                "دوره مقدماتی رایگان شامل شانزده جلسه است.",
                "fact",
                "",
                "",
                "",
            ]
        )
        writer.writerow(
            [
                "mentor",
                "آموزش",
                "ثبت نام در دوره مقدماتی چطور انجام می‌شود؟",
                "از طریق پیام به منتور ثبت نام انجام می‌شود.",
                "guidance",
                "",
                "",
                "",
            ]
        )
    await ingest_csv(session, path, embedder=HashingEmbedder())
    await session.commit()


@pytest.fixture
async def scenario(
    session: AsyncSession, account: MentorAccount, knowledge: None
) -> dict[str, int]:
    """چند گفتگوی جدا: نام و تلفن در متن، یک گفتگوی خنثی، یک پیام قاعده‌دار، یک پیام بی‌تاریخچه."""
    ids: dict[str, int] = {}
    # گفتگوی ۵۰۰: نام و داده‌ی شخصی در متن + حافظه
    ids["r1"] = await _say(
        session,
        account,
        chat=500,
        mid=1,
        body=f"سلام من {STUDENT_NAME} هستم و تازه شروع کردم",
        first_name=STUDENT_NAME,
    )
    ids["r2"] = await _say(
        session,
        account,
        chat=500,
        mid=2,
        body=f"سلام {STUDENT_NAME} جان، خوش اومدی. من {MENTOR_NAME} هستم",
        who="mentor",
        first_name="منتور",
    )
    ids["r3"] = await _say(
        session,
        account,
        chat=500,
        mid=3,
        body=f"دوره مقدماتی چند جلسه است؟ شماره‌ام {PHONE} و ایمیلم {EMAIL} و {HANDLE}",
        first_name=STUDENT_NAME,
    )
    student_id = (
        await session.execute(
            text("select student_id from conversations where telegram_chat_id = 500")
        )
    ).scalar_one()
    await apply_candidates(
        session,
        student_id=student_id,
        candidates=[Candidate("goal", f"{STUDENT_NAME} می‌خواهد معامله‌گر حرفه‌ای شود", 0.9)],
        source=MemorySource.extracted,
    )
    await session.commit()

    # گفتگوی ۵۰۱: خنثی (بدون نام و داده‌ی شخصی) برای آزمون وفاداری
    ids["n1"] = await _say(
        session, account, chat=501, mid=1, body="سلام وقت بخیر، می‌خواستم درباره آموزش بپرسم"
    )
    ids["n2"] = await _say(
        session,
        account,
        chat=501,
        mid=2,
        body="سلام، بفرمایید چه کمکی از من برمیاد",
        who="assistant",
        first_name="دستیار",
    )
    ids["n3"] = await _say(
        session,
        account,
        chat=501,
        mid=3,
        body="دوره مقدماتی شامل چه چیزهایی است؟ لطفاً توضیح بدید",
    )

    # گفتگوی ۵۰۲: پیام قاعده‌دار (پول) ← بدون مدل
    ids["m1"] = await _say(session, account, chat=502, mid=1, body="سلام خسته نباشید دوستان")
    ids["m2"] = await _say(
        session, account, chat=502, mid=2, body="رسید واریزم رو فرستادم چی شد؟ دوره مقدماتی"
    )

    # گفتگوی ۵۰۳: جمله‌ی منحصر به همین گفتگو (برای آزمون جداسازی)
    ids["o1"] = await _say(
        session, account, chat=503, mid=1, body=f"{OTHER_CHAT_SENTINEL} پیام قدیمی گفتگوی دیگر"
    )
    ids["o2"] = await _say(
        session, account, chat=503, mid=2, body="ثبت نام در دوره مقدماتی چطور انجام می‌شود؟"
    )
    return ids


class _Answers(ScriptedClient):
    """پاسخ جعلی: متن بازوی A و C را از روی دستور سیستمی تشخیص می‌دهد."""

    def __init__(
        self,
        *,
        input_tokens: int = 100,
        output_tokens: int = 50,
        confidence: float = 0.95,
        needs_human: bool = False,
        model: str = MODEL,
    ) -> None:
        super().__init__(model=model)
        self.input_tokens = input_tokens
        self.output_tokens = output_tokens
        self.confidence = confidence
        self.needs_human = needs_human

    async def complete(self, *, system: str, user: str) -> ModelCall:
        self.calls.append((system, user))
        arm = "A" if system == SYSTEM_PROMPT else "C"
        return ModelCall(
            answer=ModelAnswer(
                answer=f"پاسخ بازوی {arm} شماره {len(self.calls)}",
                confidence=self.confidence,
                needs_human=self.needs_human,
                reason="آزمایشی",
                used_chunk_ids=[],
            ),
            model=self.model,
            latency_ms=7,
            input_tokens=self.input_tokens,
            output_tokens=self.output_tokens,
        )


def _variant(**overrides: Any) -> dict[str, Any]:
    raw: dict[str, Any] = {
        "version": "tone-test-1",
        "rules": {
            "7": "فارسی محاوره‌ای و دوستانه بنویس و مثل منتور واقعی حرف بزن.",
            "9": "هر فکر را در یک پیام کوتاه بنویس و از مقدمه‌چینی پرهیز کن.",
        },
        "appendix": "نمونه‌ی لحن:\nدانشجو: سلام\nمنتور: سلام، بفرمایید.",
    }
    raw.update(overrides)
    return raw


async def _prepare(
    *, variant: bool = True, limit: int = 30, min_history: int = 1
) -> dict[str, Any]:
    async with ce.readonly_session() as session:
        return await ce.prepare(
            session,
            limit=limit,
            seed=7,
            min_history=min_history,
            embedder=None,
            variant=ce.parse_variant(_variant()) if variant else None,
        )


async def _counts(session: AsyncSession) -> dict[str, int]:
    tables = (
        (await session.execute(text("select tablename from pg_tables where schemaname='public'")))
        .scalars()
        .all()
    )
    counts: dict[str, int] = {}
    for table in sorted(tables):
        counts[table] = int(
            (await session.execute(text(f'select count(*) from "{table}"'))).scalar_one()
        )
    return counts


# ---------------------------------------------------------------------------
# ۱) ایمنی ساختاری: هیچ مسیری به تلگرام یا نوشتن
# ---------------------------------------------------------------------------

FORBIDDEN_IMPORTS = (
    "telethon",
    "mentorai.telegram",
    "mentorai.delivery",
    "mentorai.drafts",
    "mentorai.escalation",
    "mentorai.worker",
    "mentorai.control",
    "mentorai.jobs",
    "mentorai.web",
    "mentorai.db.session",
)
FORBIDDEN_CALLS = {"add", "add_all", "commit", "flush", "merge", "delete", "insert", "update"}
FORBIDDEN_NAMES = {"handle_message", "_record", "session_scope", "get_sessionmaker", "get_engine"}


def _imports(tree: ast.AST) -> set[str]:
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            found.add(node.module)
            found.update(f"{node.module}.{alias.name}" for alias in node.names)
    return found


def test_the_module_never_imports_telegram_delivery_drafts_or_a_writable_session() -> None:
    tree = ast.parse(MODULE.read_text(encoding="utf-8"))
    bad = sorted(
        name
        for name in _imports(tree)
        if any(name == p or name.startswith(p + ".") for p in FORBIDDEN_IMPORTS)
    )
    assert bad == []


def test_the_module_has_no_database_write_call_and_never_names_the_writing_pipeline() -> None:
    tree = ast.parse(MODULE.read_text(encoding="utf-8"))
    calls = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    names = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)} | {
        node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute)
    }
    assert calls & FORBIDDEN_CALLS == set()
    assert names & FORBIDDEN_NAMES == set()


async def test_a_readonly_session_rejects_writes_even_after_a_commit(
    scenario: dict[str, int],
) -> None:
    async with ce.readonly_session() as session:
        await ce.assert_read_only(session)
        with pytest.raises(DBAPIError, match="read-only"):
            await session.execute(text("insert into students (display_name) values ('x')"))
        await session.rollback()
        # بعد از پایان تراکنش اول، تراکنش بعدی هم هنوز فقط‌خواندنی است (سطح اتصال).
        await session.commit()
        await ce.assert_read_only(session)
        for statement in (
            "insert into students (display_name) values ('x')",
            "update messages set text = 'x'",
            "delete from messages",
            "truncate messages cascade",
            "create table evil (id int)",
        ):
            with pytest.raises(DBAPIError, match="read-only"):
                await session.execute(text(statement))
            await session.rollback()


async def test_prepare_refuses_a_writable_session(
    session: AsyncSession, scenario: dict[str, int]
) -> None:
    with pytest.raises(ce.EvalError, match="فقط‌خواندنی"):
        await ce.prepare(session, limit=5, seed=7, min_history=1, embedder=None)


async def test_prepare_and_run_change_no_row_in_any_table(
    session: AsyncSession, scenario: dict[str, int], tmp_path: Path
) -> None:
    before = await _counts(session)
    document = await _prepare()
    run = await ce.run_eval(document, _Answers(), arms=["A", "C"], max_cost_usd=50.0)
    ce.write_outputs(document, run, tmp_path / "out")
    await session.rollback()
    after = await _counts(session)

    assert before == after
    assert run.calls > 0


async def test_nothing_that_writes_or_sends_is_ever_called(
    scenario: dict[str, int], monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    def boom(*_: object, **__: object) -> None:
        raise AssertionError("مسیر نوشتن یا ارسال صدا زده شد")

    async def aboom(*_: object, **__: object) -> None:
        raise AssertionError("مسیر نوشتن یا ارسال صدا زده شد")

    for target in (
        "mentorai.drafts.create",
        "mentorai.delivery.enqueue",
        "mentorai.jobs.queue.enqueue",
        "mentorai.escalation.hand_off",
        "mentorai.memory.store.remember",
        "mentorai.ai.budget.record",
        "mentorai.ai.runtime._record",
        "mentorai.media.store.record",
        "mentorai.telegram.sender.push",
    ):
        monkeypatch.setattr(target, aboom)
    monkeypatch.setattr("mentorai.telegram.gateway.AccountGateway.start", aboom)
    monkeypatch.setattr("mentorai.telegram.gateway.AccountGateway.persist", aboom)
    monkeypatch.setattr("mentorai.telegram.sender.record_sent", boom)

    document = await _prepare()
    run = await ce.run_eval(document, _Answers(), arms=["A", "C"], max_cost_usd=50.0)
    ce.write_outputs(document, run, tmp_path / "out")

    assert run.calls == 2 * len(document["cases"])


async def test_run_never_touches_the_database(
    scenario: dict[str, int], monkeypatch: pytest.MonkeyPatch
) -> None:
    document = await _prepare()

    def boom(*_: object, **__: object) -> None:
        raise AssertionError("اجرا به پایگاه داده وصل شد")

    monkeypatch.setattr(ce, "create_async_engine", boom)
    monkeypatch.setattr("mentorai.db.session.get_engine", boom)
    monkeypatch.setattr("mentorai.db.session.get_sessionmaker", boom)
    monkeypatch.setattr("mentorai.db.session.session_scope", boom)

    run = await ce.run_eval(document, _Answers(), arms=["A", "C"], max_cost_usd=50.0)

    assert run.results


# ---------------------------------------------------------------------------
# ۲) نمونه‌گیری، زمینه و جداسازی گفتگوها
# ---------------------------------------------------------------------------


async def test_prepare_builds_the_context_like_the_live_path_and_excludes_what_the_model_never_sees(
    scenario: dict[str, int],
) -> None:
    document = await _prepare()

    by_id = {c["case_id"]: c for c in document["cases"]}
    # فقط پیام‌هایی که تاریخچه دارند و قاعده‌ی قطعی نمی‌گیرند.
    assert set(by_id) == {f"m{scenario[k]}" for k in ("r3", "n3", "o2")}
    assert document["excluded"]["rule_money"] == 1
    assert document["excluded"]["short_history"] >= 3
    assert document["history_turns"] == HISTORY_TURNS == 4
    assert [c["label"] for c in document["cases"]] == ["C01", "C02", "C03"]
    assert document["manifest_sha256"] == ce.manifest_hash(document)

    neutral = by_id[f"m{scenario['n3']}"]
    assert [role for role, _ in neutral["history"]] == ["دانشجو", "دستیار"]
    assert neutral["hits"], "همان بازیابی مسیر زنده"


async def test_history_never_leaks_between_conversations_and_is_capped(
    session: AsyncSession, account: MentorAccount, scenario: dict[str, int]
) -> None:
    for i in range(6):  # گفتگوی ۵۰۱ را بلند می‌کنیم؛ باید فقط ۴ پیام آخر بیاید
        await _say(session, account, chat=501, mid=10 + i, body=f"پیام پرکننده شماره {i} دوره")
    last = await _say(
        session, account, chat=501, mid=30, body="دوره مقدماتی شامل چه چیزهایی است؟ دوباره"
    )
    document = await _prepare()

    case = next(c for c in document["cases"] if c["case_id"] == f"m{last}")
    assert len(case["history"]) == HISTORY_TURNS
    everything = json.dumps(document["cases"], ensure_ascii=False)
    for c in document["cases"]:
        if c["case_id"] != f"m{scenario['o2']}":
            assert OTHER_CHAT_SENTINEL not in c["user"], "پیام گفتگوی دیگر نباید بیاید"
    assert OTHER_CHAT_SENTINEL in everything  # خودش در نمونه‌ی خودش هست
    other = next(c for c in document["cases"] if c["case_id"] == f"m{scenario['o2']}")
    assert OTHER_CHAT_SENTINEL in other["user"]


async def test_the_sample_is_reproducible_and_a_shortfall_is_reported_not_hidden(
    scenario: dict[str, int],
) -> None:
    first = await _prepare(limit=2)
    second = await _prepare(limit=2)

    assert [c["case_id"] for c in first["cases"]] == [c["case_id"] for c in second["cases"]]
    assert len(first["cases"]) == 2
    big = await _prepare(limit=30)
    assert len(big["cases"]) == 3 and big["requested"] == 30
    assert "نمونه آماده شد (درخواستی: 30" in ce.render_prepare_summary(big)


async def test_a_message_without_sources_is_excluded(
    scenario: dict[str, int], monkeypatch: pytest.MonkeyPatch
) -> None:
    async def nothing(*_: object, **__: object) -> list[object]:
        return []

    monkeypatch.setattr(ce, "search", nothing)
    async with ce.readonly_session() as session:
        document = await ce.prepare(session, limit=5, seed=7, min_history=1, embedder=None)

    assert document["cases"] == []
    assert document["excluded"]["no_sources"] == 3


# ---------------------------------------------------------------------------
# ۳) وفاداری بازوی A به مسیر زنده
# ---------------------------------------------------------------------------


async def test_arm_a_builds_exactly_the_input_the_live_pipeline_sends(
    session: AsyncSession, scenario: dict[str, int]
) -> None:
    document = await _prepare()
    case = next(c for c in document["cases"] if c["case_id"] == f"m{scenario['n3']}")
    live_client = ScriptedClient(
        ModelAnswer(
            answer="پاسخ آزمایشی", confidence=0.95, needs_human=False, reason="x", used_chunk_ids=[]
        )
    )
    message = await session.get_one(Message, scenario["n3"])

    result = await handle_message(session, message, model_client=live_client, embedder=None)
    run = await ce.run_eval(document, _Answers(), arms=["A"], max_cost_usd=50.0)

    live_system, live_user = live_client.calls[0]
    # مسیر زنده از ADR-053 دستور v3 با نام منتور دارد؛ بازوی A خط پایه‌ی v2 است. ورودی کاربر
    # (بازیابی، تاریخچه، حافظه) کلمه‌به‌کلمه یکی است.
    assert live_system == build_system_prompt(MENTOR_NAME)
    assert live_user == case["user"], "ورودی مدل کلمه‌به‌کلمه همان مسیر زنده است"
    assert result.outcome is Outcome.answer
    assert run.results[case["label"]]["A"].outcome == "answer"


@pytest.mark.parametrize(
    ("confidence", "needs_human", "reason"),
    [
        (0.95, False, None),
        (0.3, False, "low_confidence"),
        (0.95, True, "model_flagged"),
    ],
)
async def test_arm_a_applies_the_same_decision_gates_as_the_live_pipeline(
    session: AsyncSession,
    scenario: dict[str, int],
    confidence: float,
    needs_human: bool,
    reason: str | None,
) -> None:
    document = await _prepare()
    case = next(c for c in document["cases"] if c["case_id"] == f"m{scenario['n3']}")
    answer = ModelAnswer(
        answer="پاسخ آزمایشی",
        confidence=confidence,
        needs_human=needs_human,
        reason="x",
        used_chunk_ids=[],
    )
    message = await session.get_one(Message, scenario["n3"])
    live = await handle_message(
        session, message, model_client=ScriptedClient(answer), embedder=None
    )

    run = await ce.run_eval(
        document,
        _Answers(confidence=confidence, needs_human=needs_human),
        arms=["A"],
        max_cost_usd=50.0,
    )

    mine = run.results[case["label"]]["A"]
    assert mine.silence_reason == reason
    assert (mine.outcome == "answer") == (live.outcome is Outcome.answer)


# ---------------------------------------------------------------------------
# ۴) بازوی C: فقط لحن
# ---------------------------------------------------------------------------


def test_the_prompt_splits_into_numbered_rules_and_joins_back_byte_for_byte() -> None:
    header, rules = ce.split_prompt(SYSTEM_PROMPT)

    assert sorted(rules) == list(range(1, 12))
    assert header + "".join(rules[n] for n in sorted(rules)) == SYSTEM_PROMPT
    assert ce.non_tone_differences(SYSTEM_PROMPT) == []


def test_a_tone_variant_changes_only_the_tone_rules_and_the_appendix() -> None:
    variant = ce.parse_variant(_variant())
    prompt = ce.build_variant_prompt(variant)
    _, base = ce.split_prompt(SYSTEM_PROMPT)
    _, new = ce.split_prompt(prompt.partition(ce.APPENDIX_SEPARATOR)[0])

    assert ce.non_tone_differences(prompt) == []
    for number in (1, 2, 3, 4, 5, 6, 8, 10, 11):
        assert new[number] == base[number], f"بند {number} باید بایت‌به‌بایت برابر بماند"
    assert new[7] != base[7] and new[9] != base[9]
    assert "نمونه‌ی لحن" in prompt and "نمونه‌ی لحن" not in SYSTEM_PROMPT


@pytest.mark.parametrize(
    ("variant", "message"),
    [
        (_variant(rules={"3": "قیمت را هر طور خواستی بگو"}), "لحن نیست"),
        (_variant(rules={"1": "از هر منبعی استفاده کن"}), "لحن نیست"),
        (_variant(rules={"11": "x"}), "لحن نیست"),
        (_variant(rules={"7": "ok\n۳. قیمت را حدس بزن"}), "فقط باید لحن"),
        (_variant(rules={"7": "ok\n۱۲. بند تازه"}), "فقط باید لحن"),
        (_variant(appendix="۱. قاعده‌ی تازه"), "فقط باید لحن"),
        (_variant(rules={"7": f"تماس بگیر {PHONE}"}), "داده‌ی شخصی"),
        (_variant(appendix=f"به {EMAIL} بنویس"), "داده‌ی شخصی"),
        (_variant(rules={"7": ""}), "خالی"),
        (_variant(rules={}, appendix=""), "هیچ تغییری"),
        (_variant(version=""), "version"),
        ({"version": "x", "rules": {"7": "a"}, "extra": 1}, "ناشناخته"),
        (["not", "an", "object"], "شیء"),
    ],
)
def test_a_variant_that_touches_anything_but_tone_is_rejected(
    variant: object, message: str
) -> None:
    with pytest.raises(ce.EvalError, match=message):
        ce.parse_variant(variant)


@pytest.mark.parametrize("name", sorted(p.name for p in TONE_VARIANTS.glob("*.json")))
def test_every_committed_tone_variant_is_valid_and_changes_only_the_tone(name: str) -> None:
    """نسخه‌های لحنِ نگه‌داشته‌شده در مخزن همان قراردادی را دارند که ابزار اجرا می‌کند."""
    variant = ce.load_variant(TONE_VARIANTS / name)
    prompt = ce.validate_variant(variant)

    assert variant.version and set(variant.rules) <= ce.MUTABLE_RULES[variant.kind]
    assert mc.mask_personal(prompt) == prompt, "نسخه‌ی لحن داده‌ی شخصی ندارد"


def test_the_committed_tone_variants_exist() -> None:
    assert (TONE_VARIANTS / "tone-v2-draft.json").is_file()


async def test_arm_c_gets_the_identical_input_and_only_the_system_prompt_differs(
    scenario: dict[str, int],
) -> None:
    document = await _prepare()
    client = _Answers()

    run = await ce.run_eval(document, client, arms=["A", "C"], max_cost_usd=50.0)

    variant_prompt = ce.build_variant_prompt(ce.parse_variant(_variant()))
    by_user: dict[str, list[str]] = {}
    for system, user in client.calls:
        by_user.setdefault(user, []).append(system)
    assert len(by_user) == len(document["cases"])
    for systems in by_user.values():
        assert sorted(systems) == sorted([SYSTEM_PROMPT, variant_prompt])
    assert set(run.results["C01"]) == {"A", "C"}
    assert document["prompts"]["A"]["sha256"] != document["prompts"]["C"]["sha256"]


async def test_arm_c_needs_a_variant_and_a_tampered_variant_is_caught(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    plain = await _prepare(variant=False)
    with pytest.raises(ce.EvalError, match="در فایل آماده‌سازی نیست"):
        ce.parse_arms("A,C", plain)
    assert ce.parse_arms("A", plain) == ["A"]

    document = await _prepare()
    path = ce.write_prepared(document, tmp_path / "out")
    raw = json.loads(path.read_text(encoding="utf-8"))
    raw["variant"]["rules"]["7"] = "یک دستور دیگر"
    path.write_text(json.dumps(raw, ensure_ascii=False), encoding="utf-8")
    with pytest.raises(ce.EvalError, match="تغییر کرده"):
        ce.load_prepared(path)

    # حتی اگر هش را هم بازسازی کنند، دستور C با هش ثبت‌شده‌ی دستورش نمی‌خواند.
    raw["manifest_sha256"] = ce.manifest_hash(raw)
    path.write_text(json.dumps(raw, ensure_ascii=False), encoding="utf-8")
    loaded = ce.load_prepared(path)
    with pytest.raises(ce.EvalError, match="هش ثبت‌شده"):
        await ce.run_eval(loaded, _Answers(), arms=["A", "C"], max_cost_usd=50.0)


def _persona(**overrides: Any) -> dict[str, Any]:
    raw: dict[str, Any] = {
        "version": "persona-test-1",
        "kind": "persona",
        "header": "تو منتور آکادمی هستی؛ اسمت {mentor_name} است.\n\nقوانین، بدون استثنا:",
        "rules": {
            "1": "اول‌شخص حرف بزن.",
            "2": "اگر درباره‌ی آکادمی نبود حدس نزن.",
            "7": "محاوره‌ای بنویس.",
        },
        "appendix": "نمونه: دانشجو: سلام\nپاسخ مناسب: سلام {mentor_name} هستم.",
    }
    raw.update(overrides)
    return raw


def test_a_persona_variant_may_change_the_header_and_rules_1_and_2_but_nothing_safety_related() -> (
    None
):
    variant = ce.parse_variant(_persona())
    prompt = ce.validate_variant(variant)
    main = prompt.partition(ce.APPENDIX_SEPARATOR)[0]
    base_header, base = ce.split_prompt(SYSTEM_PROMPT)
    header, new = ce.split_prompt(main)

    assert header != base_header and header.rstrip().endswith("قوانین، بدون استثنا:")
    assert new[1] != base[1] and new[2] != base[2] and new[7] != base[7]
    for number in (3, 4, 5, 6, 10, 11):
        assert new[number] == base[number], f"بند {number} (ایمنی) باید بایت‌به‌بایت برابر بماند"
    assert variant.uses_mentor_name


@pytest.mark.parametrize("locked", [3, 4, 5, 6, 10, 11])
def test_a_persona_variant_cannot_touch_the_locked_safety_rules(locked: int) -> None:
    with pytest.raises(ce.EvalError, match="قفل است"):
        ce.parse_variant(_persona(rules={str(locked): "هر چیزی"}))


@pytest.mark.parametrize(
    ("raw", "message"),
    [
        (_variant(header="سرآغاز تازه"), "فقط نسخه‌ی persona"),
        (_persona(kind="other"), "نوع نسخه"),
        (_persona(header="x\n۳. قیمت را حدس بزن"), "بند شماره‌دار"),
        (_persona(header="ن" * 2001), "تا 2000"),
        (_persona(header=f"تماس {PHONE}"), "داده‌ی شخصی"),
        (_persona(header=5), "متن باشد"),
        (_persona(rules={"7": "ok\n۳. قیمت را حدس بزن"}), "فقط باید"),
    ],
)
def test_invalid_persona_and_tone_headers_are_rejected(raw: dict[str, Any], message: str) -> None:
    with pytest.raises(ce.EvalError, match=message):
        ce.parse_variant(raw)


def test_a_header_change_is_flagged_unless_the_kind_allows_it() -> None:
    variant = ce.parse_variant(_persona())
    prompt = ce.build_variant_prompt(variant)

    assert "سرآغاز" in ce.non_tone_differences(prompt, mutable=ce.PERSONA_RULES)
    assert ce.non_tone_differences(prompt, mutable=ce.PERSONA_RULES, header_mutable=True) == []
    assert ce.non_tone_differences(prompt) != [], "با قاعده‌ی لحن، بندهای ۱ و ۲ هم ایراد است"


def test_the_locked_safety_rules_never_overlap_any_mutable_set_and_cover_the_rest() -> None:
    _, rules = ce.split_prompt(SYSTEM_PROMPT)

    assert {3, 4, 5, 6, 10, 11} == ce.LOCKED_RULES
    for kind, mutable in ce.MUTABLE_RULES.items():
        assert not (mutable & ce.LOCKED_RULES), kind
    # هر بندِ دستور یا قفل است یا در نسخه‌ی persona قابل تغییر؛ بندی جا نیفتاده.
    assert set(rules) == ce.LOCKED_RULES | ce.PERSONA_RULES
    assert ce.TONE_RULES <= ce.PERSONA_RULES


def test_a_tone_variant_whose_header_was_changed_is_refused_by_the_validator() -> None:
    persona = ce.parse_variant(_persona())
    tone = ce.parse_variant(_variant())
    changed_header_prompt = ce.build_variant_prompt(persona)

    with pytest.raises(ce.EvalError, match="سرآغاز"):
        ce.validate_variant_prompt(changed_header_prompt, tone)
    ce.validate_variant_prompt(changed_header_prompt, persona)


def test_the_mentor_name_is_cleaned_before_it_enters_a_prompt() -> None:
    assert ce._clean_name("سبحان {صمدی}\n  x") == "سبحان صمدی x"
    assert ce._clean_name("   ") == "منتور"
    assert len(ce._clean_name("ن" * 500)) == 80


async def test_each_case_gets_its_own_mentors_name_in_the_persona_prompt(
    scenario: dict[str, int],
) -> None:
    async with ce.readonly_session() as session:
        document = await ce.prepare(
            session,
            limit=30,
            seed=7,
            min_history=1,
            embedder=None,
            variant=ce.parse_variant(_persona()),
        )
    client = _Answers()

    run = await ce.run_eval(document, client, arms=["A", "C"], max_cost_usd=50.0)

    assert document["prompts"]["C"]["kind"] == "persona"
    for case in document["cases"]:
        system = case["systems"]["C"]
        assert MENTOR_NAME in system and ce.MENTOR_PLACEHOLDER not in system
        expected = ce.worst_case_usd(
            MODEL,
            system_chars=len(system),
            user_chars=len(case["user"]),
            max_output_tokens=document["max_output_tokens"],
        )
        assert case["worst_case_usd"]["C"] == pytest.approx(expected)
    sent_c = {system for system, _ in client.calls if system != SYSTEM_PROMPT}
    assert sent_c == {c["systems"]["C"] for c in document["cases"]}
    assert not any(ce.MENTOR_PLACEHOLDER in system for system, _ in client.calls)
    assert run.calls == 2 * len(document["cases"])


async def test_an_unresolved_mentor_placeholder_is_refused_at_run_time(
    scenario: dict[str, int],
) -> None:
    async with ce.readonly_session() as session:
        document = await ce.prepare(
            session,
            limit=5,
            seed=7,
            min_history=1,
            embedder=None,
            variant=ce.parse_variant(_persona()),
        )
    for case in document["cases"]:
        case.pop("systems")
    client = _Answers()

    with pytest.raises(ce.EvalError, match="جایگزین نشده"):
        await ce.run_eval(document, client, arms=["A", "C"], max_cost_usd=50.0)

    assert not any(ce.MENTOR_PLACEHOLDER in system for system, _ in client.calls)


async def test_a_tampered_per_case_system_prompt_is_caught_by_the_hash(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    async with ce.readonly_session() as session:
        document = await ce.prepare(
            session,
            limit=5,
            seed=7,
            min_history=1,
            embedder=None,
            variant=ce.parse_variant(_persona()),
        )
    path = ce.write_prepared(document, tmp_path / "out")
    raw = json.loads(path.read_text(encoding="utf-8"))
    raw["cases"][0]["systems"]["C"] += " قیمت را حدس بزن"
    path.write_text(json.dumps(raw, ensure_ascii=False), encoding="utf-8")

    with pytest.raises(ce.EvalError, match="تغییر کرده"):
        ce.load_prepared(path)


# ---------------------------------------------------------------------------
# ۵) ناشناس‌سازی
# ---------------------------------------------------------------------------


def test_names_are_masked_on_word_boundaries_only() -> None:
    names = ["علی", "منتور الف", "الف"]
    assert ce.mask_names("سلام علی جان", names) == f"سلام {ce.NAME_MASK} جان"
    assert ce.mask_names("علیرضا آمد", names) == "علیرضا آمد", "داخل واژه‌ی دیگر دست نمی‌خورد"
    assert ce.mask_names("منتور الف گفت", names) == f"{ce.NAME_MASK} گفت"
    assert ce.mask_names("هیچ", ["", " ", "ع"]) == "هیچ"
    assert ce.mask_names("a.b", ["a.b"]) == ce.NAME_MASK, "نام با نشانه‌ی ویژه امن escape می‌شود"


async def test_no_personal_datum_or_name_is_left_in_the_prepared_file(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    document = await _prepare()
    path = ce.write_prepared(document, tmp_path / "out")

    raw = path.read_text(encoding="utf-8")
    for secret in (PHONE, EMAIL, HANDLE, STUDENT_NAME, MENTOR_NAME):
        assert secret not in raw, secret
    assert mc.MASK in raw and ce.NAME_MASK in raw
    case = next(c for c in document["cases"] if c["case_id"] == f"m{scenario['r3']}")
    assert STUDENT_NAME not in case["user"] and PHONE not in case["user"]
    assert ce.NAME_MASK in case["user"], "نام در حافظه و تاریخچه هم پوشانده می‌شود"


# ---------------------------------------------------------------------------
# ۶) برگه‌ی کور، کلید و مجوزها
# ---------------------------------------------------------------------------


async def _full_run(tmp_path: Path) -> tuple[dict[str, Any], ce.EvalRun, dict[str, Path]]:
    document = await _prepare()
    run = await ce.run_eval(document, _Answers(), arms=["A", "C"], max_cost_usd=50.0)
    return document, run, ce.write_outputs(document, run, tmp_path / "out")


async def test_the_blind_sheet_reveals_neither_arm_nor_model_nor_cost_nor_message_ids(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    document, _, paths = await _full_run(tmp_path)

    sheet = paths["sheet"].read_text(encoding="utf-8-sig")
    guide = paths["guide"].read_text(encoding="utf-8-sig")
    key = json.loads(paths["key"].read_text(encoding="utf-8"))
    for forbidden in (
        MODEL,
        "tone-test-1",
        document["prompts"]["A"]["sha256"],
        document["manifest_sha256"],
        "cost",
        "token",
        "latency",
        "tone-test",
    ):
        assert forbidden not in sheet and forbidden not in guide
    for case_id in key["cases"].values():
        assert case_id["case_id"] not in sheet, "شناسه‌ی پیام فقط در کلید است"
    # حتی «بازوی A / بازوی C» داخل متن جعلیِ پاسخ‌های این آزمون آمده؛ ستون‌های برگه نباید.
    assert [h for h in ce.sheet_header() if "بازو" in h] == []
    rows = list(csv.DictReader(io.StringIO(sheet)))
    assert {r[ce.ID_LABEL] for r in rows} == {"C01", "C02", "C03"}
    assert [r[ce.POSITION_LABEL] for r in rows] == ["1", "2"] * 3


async def test_the_answer_order_is_random_per_case_reproducible_and_matches_the_key(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    document, run, paths = await _full_run(tmp_path)

    key = json.loads(paths["key"].read_text(encoding="utf-8"))
    rows = list(csv.DictReader(io.StringIO(paths["sheet"].read_text(encoding="utf-8-sig"))))
    for label in key["cases"]:
        order = ce.sheet_order(key, label, list(key["arms"]))
        shown = [r[ce.TEXT_LABEL] for r in rows if r[ce.ID_LABEL] == label]
        expected = [run.results[label][arm].text for arm in order]
        assert shown == expected
    # قابل بازتولید
    again = ce.build_sheet(document, run)
    assert again == paths["sheet"].read_text(encoding="utf-8-sig")


def test_across_many_cases_both_orders_appear() -> None:
    orders = {tuple(ce.sheet_order({"sheet_seed": 7}, f"C{i:02d}", ["A", "C"])) for i in range(60)}

    assert orders == {("A", "C"), ("C", "A")}


async def test_outputs_are_private_and_the_key_is_a_separate_file(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    _, _, paths = await _full_run(tmp_path)
    prepared = ce.write_prepared(await _prepare(), tmp_path / "out")

    assert stat.S_IMODE((tmp_path / "out").stat().st_mode) == 0o700
    for path in (*paths.values(), prepared):
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert paths["key"] != paths["sheet"]
    assert "A" in json.loads(paths["key"].read_text(encoding="utf-8"))["arms"]
    assert "A" not in paths["sheet"].read_text(encoding="utf-8-sig").split("\n", 1)[0].split(",")


async def test_a_formula_like_answer_is_defused_in_the_sheet(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    document = await _prepare()
    run = await ce.run_eval(document, _Answers(), arms=["A", "C"], max_cost_usd=50.0)
    run.results["C01"]["A"].text = '=HYPERLINK("http://evil","x")'
    run.results["C01"]["C"].text = "+cmd|' /C calc'!A0"

    sheet = ce.build_sheet(document, run)

    answers = [
        r[ce.TEXT_LABEL] for r in csv.DictReader(io.StringIO(sheet)) if r[ce.ID_LABEL] == "C01"
    ]
    assert all(a.startswith("'") for a in answers)


# ---------------------------------------------------------------------------
# ۷) هزینه
# ---------------------------------------------------------------------------


def test_the_worst_case_formula_is_exact() -> None:
    # ورودی ۴۰۰۰ نویسه ≤ ۴۰۰۰ توکن × ۲ دلار × ۱٫۲۵ = ۰٫۰۱ ؛ خروجی ۸۰۰۰ × ۱۰ = ۰٫۰۸
    value = ce.worst_case_usd(MODEL, system_chars=1000, user_chars=3000, max_output_tokens=8000)

    assert value == pytest.approx(0.09)
    assert ce.worst_case_usd(
        MODEL, system_chars=1000, user_chars=3000, max_output_tokens=8000, attempts=3
    ) == pytest.approx(0.27)


def test_strict_mode_never_starts_a_pair_whose_worst_case_would_pass_the_cap() -> None:
    assert ce.may_start(spent=0.0, pair_worst=0.5, cap=0.5, guard="strict", observed_pairs=[0.01])
    assert not ce.may_start(
        spent=0.01, pair_worst=0.5, cap=0.5, guard="strict", observed_pairs=[0.01]
    )
    # حالت measured از خرج دیده‌شده استفاده می‌کند، ولی بیش از بدترین حالت پیش‌بینی نمی‌کند
    assert ce.may_start(spent=0.4, pair_worst=0.5, cap=0.5, guard="measured", observed_pairs=[0.05])
    assert not ce.may_start(
        spent=0.45, pair_worst=0.5, cap=0.5, guard="measured", observed_pairs=[0.05]
    )
    assert not ce.may_start(
        spent=0.0, pair_worst=0.6, cap=0.5, guard="measured", observed_pairs=[]
    ), "پیش از هر مشاهده، بدترین حالت ملاک است"


async def test_a_cap_below_the_first_pair_makes_no_model_call_at_all(
    scenario: dict[str, int],
) -> None:
    document = await _prepare()
    client = _Answers()

    run = await ce.run_eval(document, client, arms=["A", "C"], max_cost_usd=0.001)

    assert client.calls == [] and run.calls == 0
    assert run.stopped_early and run.stop_reason == "cost_cap"
    assert run.spent_charged == 0.0


async def test_strict_mode_stops_before_a_pair_that_could_pass_the_cap_even_in_the_worst_case(
    scenario: dict[str, int],
) -> None:
    document = await _prepare()
    pairs = [sum(c["worst_case_usd"].values()) for c in document["cases"]]
    cap = sum(pairs) * 0.7
    # هزینه‌ی واقعی تقریباً برابر بدترین حالت: ۸۰۰۰ توکن خروجی در هر فراخوانی
    client = _Answers(input_tokens=1, output_tokens=8000)

    run = await ce.run_eval(document, client, arms=["A", "C"], max_cost_usd=cap)

    assert len(run.results) == 2 and len(client.calls) == 4
    assert run.stopped_early and run.stop_reason == "cost_cap"
    assert run.spent_charged <= cap, "قول strict: هرگز از سقف نمی‌گذرد"
    assert set(run.results) == {"C01", "C02"}, "جفت‌ها کامل‌اند؛ هیچ نمونه‌ی نیمه‌کاره‌ای نیست"
    assert all(set(r) == {"A", "C"} for r in run.results.values())


def test_the_guaranteed_pairs_count_uses_the_worst_case_of_each_pair() -> None:
    document = {
        "cases": [{"worst_case_usd": {"A": 0.1, "C": 0.1}} for _ in range(5)],
    }

    assert ce.pairs_that_fit(document, ["A", "C"], 0.5) == 2
    assert ce.pairs_that_fit(document, ["A"], 0.5) == 5
    assert ce.pairs_that_fit(document, ["A", "C"], 0.19) == 0


async def test_the_retry_factor_triples_the_assumed_worst_case(scenario: dict[str, int]) -> None:
    document = await _prepare()
    pairs = [sum(c["worst_case_usd"].values()) for c in document["cases"]]
    cap = pairs[0] * 1.5

    one = await ce.run_eval(document, _Answers(), arms=["A", "C"], max_cost_usd=cap)
    three = await ce.run_eval(
        document, _Answers(), arms=["A", "C"], max_cost_usd=cap, attempts_factor=3
    )

    assert len(one.results) >= 1
    assert len(three.results) == 0, "با تلاش دوباره‌ی کنترل‌نشده، حتی یک جفت جا نمی‌شود"


async def test_measured_mode_runs_more_than_strict_but_still_stops_at_the_cap(
    scenario: dict[str, int],
) -> None:
    real = await _prepare()
    document = dict(real)
    document["cases"] = [
        {**real["cases"][0], "label": f"C{i:02d}", "worst_case_usd": {"A": 0.1, "C": 0.1}}
        for i in range(1, 9)
    ]
    cap = 0.25

    strict = await ce.run_eval(
        document, _Answers(input_tokens=1, output_tokens=2000), arms=["A", "C"], max_cost_usd=cap
    )
    measured = await ce.run_eval(
        document,
        _Answers(input_tokens=1, output_tokens=2000),
        arms=["A", "C"],
        max_cost_usd=cap,
        guard="measured",
    )

    assert len(measured.results) > len(strict.results) >= 1
    assert strict.spent_charged <= cap
    assert measured.stopped_early and measured.stop_reason == "cost_cap"
    assert measured.spent_charged <= cap, "اینجا هم بدون رد کردن سقف تمام شد"


async def test_an_overspend_on_the_last_pair_is_reported_not_hidden(
    scenario: dict[str, int],
) -> None:
    """حالت measured می‌تواند سقف را رد کند؛ حتی روی آخرین نمونه باید گزارش شود."""
    real = await _prepare()
    document = dict(real)
    document["cases"] = [{**real["cases"][0], "worst_case_usd": {"A": 0.001, "C": 0.001}}]

    run = await ce.run_eval(
        document,
        _Answers(input_tokens=1, output_tokens=8000),
        arms=["A", "C"],
        max_cost_usd=0.01,
        guard="measured",
    )

    assert len(run.results) == 1
    assert run.spent_charged > run.cap_usd
    assert run.stopped_early and run.stop_reason == "cost_cap"


async def test_a_call_that_reports_more_input_than_the_assumed_bound_stops_the_run(
    scenario: dict[str, int],
) -> None:
    document = await _prepare()
    client = _Answers(input_tokens=10_000_000)

    run = await ce.run_eval(document, client, arms=["A", "C"], max_cost_usd=50_000.0)

    assert run.stopped_early and run.stop_reason == "estimate_violated"
    assert len(run.results) == 1, "بعد از اولین نقض فرض، هیچ فراخوانی دیگری نمی‌شود"


async def test_the_charged_cost_includes_the_cache_write_allowance(
    scenario: dict[str, int],
) -> None:
    document = await _prepare()

    run = await ce.run_eval(document, _Answers(), arms=["A"], max_cost_usd=50.0)

    assert run.spent_charged > run.spent_measured > 0
    result = run.results["C01"]["A"]
    assert result.cost_usd == pytest.approx((100 * 2.0 + 50 * 10.0) / 1e6)


async def test_the_client_model_must_match_the_prepared_model(scenario: dict[str, int]) -> None:
    document = await _prepare()

    with pytest.raises(ce.EvalError, match="مدل کلاینت"):
        await ce.run_eval(document, _Answers(model="other-model"), arms=["A"], max_cost_usd=5.0)
    with pytest.raises(ce.EvalError, match="مثبت"):
        await ce.run_eval(document, _Answers(), arms=["A"], max_cost_usd=0.0)
    with pytest.raises(ce.EvalError, match="نامعتبر"):
        await ce.run_eval(document, _Answers(), arms=["A"], max_cost_usd=5.0, guard="x")


def test_disabling_sdk_retries_is_reported_honestly() -> None:
    class _Inner:
        seen: dict[str, object] = {}

        def with_options(self, **options: object) -> str:
            self.seen = options
            return "no-retry-client"

    class _With(ScriptedClient):
        def __init__(self) -> None:
            super().__init__(model=MODEL)
            self._client: Any = _Inner()

    with_options = _With()
    assert ce.disable_retries(with_options) is True
    assert with_options._client == "no-retry-client"
    assert ce.disable_retries(ScriptedClient(model=MODEL)) is False


# ---------------------------------------------------------------------------
# ۸) دستورهای CLI: دو مرحله‌ای بودن و چاپ
# ---------------------------------------------------------------------------


def _prep_args(tmp_path: Path, **overrides: object) -> Namespace:
    values: dict[str, object] = {
        "limit": 30,
        "seed": 7,
        "min_history": 1,
        "variant": None,
        "max_output_tokens": None,
        "out": str(tmp_path / "out"),
        "check": False,
    }
    values.update(overrides)
    return Namespace(**values)


def _run_args(prepared: Path, **overrides: object) -> Namespace:
    values: dict[str, object] = {
        "prepared": str(prepared),
        "arms": "A,C",
        "max_cost_usd": 50.0,
        "cost_guard": "strict",
        "approve": None,
        "out": None,
    }
    values.update(overrides)
    return Namespace(**values)


def _no_client(monkeypatch: pytest.MonkeyPatch) -> list[int]:
    built: list[int] = []

    def build() -> ScriptedClient:
        built.append(1)
        raise AssertionError("کلاینت مدل بی‌تأیید ساخته شد")

    monkeypatch.setattr("mentorai.ai.providers.build_client", build)
    return built


async def test_check_writes_nothing_builds_no_client_and_prints_only_counts(
    scenario: dict[str, int],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    built = _no_client(monkeypatch)
    variant = tmp_path / "variant.json"
    variant.write_text(json.dumps(_variant()), encoding="utf-8")

    code = await cli.cmd_conversation_eval_prepare(
        _prep_args(tmp_path, check=True, variant=str(variant))
    )

    out = capsys.readouterr().out
    assert code == 0 and built == []
    assert not (tmp_path / "out").exists()
    assert "3 نمونه آماده شد" in out and "--check بود" in out
    for secret in (PHONE, EMAIL, HANDLE, STUDENT_NAME, OTHER_CHAT_SENTINEL, "دوره مقدماتی"):
        assert secret not in out, "هیچ متن پیامی در ترمینال چاپ نمی‌شود"


async def test_without_the_approval_code_no_client_is_built_and_nothing_is_written(
    scenario: dict[str, int],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    built = _no_client(monkeypatch)
    variant = tmp_path / "variant.json"
    variant.write_text(json.dumps(_variant()), encoding="utf-8")
    assert await cli.cmd_conversation_eval_prepare(_prep_args(tmp_path, variant=str(variant))) == 0
    prepared = tmp_path / "out" / ce.PREPARED_NAME
    capsys.readouterr()

    for approve in (None, "", "00000000", "zzzz"):
        code = await cli.cmd_conversation_eval_run(_run_args(prepared, approve=approve))
        assert code == 2

    captured = capsys.readouterr()
    assert built == []
    assert sorted(p.name for p in (tmp_path / "out").iterdir()) == [ce.PREPARED_NAME]
    assert "کد تأیید" in captured.out and "مدل صدا زده نشد" in captured.err


async def test_the_full_cli_flow_with_the_right_code_calls_the_model_and_writes_the_sheet(
    scenario: dict[str, int],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    variant = tmp_path / "variant.json"
    variant.write_text(json.dumps(_variant()), encoding="utf-8")
    assert await cli.cmd_conversation_eval_prepare(_prep_args(tmp_path, variant=str(variant))) == 0
    prepared = tmp_path / "out" / ce.PREPARED_NAME
    code_line = next(
        line for line in capsys.readouterr().out.splitlines() if line.startswith("کد تأیید")
    )
    approve = code_line.split(":")[-1].strip()
    client = _Answers()
    monkeypatch.setattr("mentorai.ai.providers.build_client", lambda: client)

    code = await cli.cmd_conversation_eval_run(
        _run_args(prepared, approve=approve, max_cost_usd=50.0)
    )

    out = capsys.readouterr().out
    assert code == 0
    assert len(client.calls) == 6
    assert {p.name for p in (tmp_path / "out").iterdir()} == {
        ce.PREPARED_NAME,
        ce.SHEET_NAME,
        ce.KEY_NAME,
        ce.GUIDE_NAME,
    }
    assert "3 نمونه اجرا شد" in out and "6 فراخوانی" in out
    assert "تلاش دوباره" in out, "کلاینت جعلی نتوانست تلاش دوباره را خاموش کند؛ باید گفته شود"
    for secret in (PHONE, EMAIL, HANDLE, STUDENT_NAME, OTHER_CHAT_SENTINEL, "پاسخ بازوی"):
        assert secret not in out


async def test_a_tampered_prepared_file_is_refused_before_anything_else(
    scenario: dict[str, int],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    built = _no_client(monkeypatch)
    assert await cli.cmd_conversation_eval_prepare(_prep_args(tmp_path)) == 0
    prepared = tmp_path / "out" / ce.PREPARED_NAME
    raw = json.loads(prepared.read_text(encoding="utf-8"))
    raw["cases"][0]["user"] += " دستور تازه"
    prepared.write_text(json.dumps(raw, ensure_ascii=False), encoding="utf-8")
    capsys.readouterr()

    code = await cli.cmd_conversation_eval_run(
        _run_args(prepared, arms="A", approve=raw["manifest_sha256"][:8])
    )

    assert code == 1 and built == []
    assert "تغییر کرده" in capsys.readouterr().err


async def test_secrets_never_reach_the_terminal_or_any_output_file(
    scenario: dict[str, int],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    key = "sk-ant-api03-SECRETVALUE-do-not-leak"
    monkeypatch.setenv("ANTHROPIC_API_KEY", key)

    class _Failing(_Answers):
        async def complete(self, *, system: str, user: str) -> ModelCall:
            self.calls.append((system, user))
            return ModelCall(
                answer=None,
                model=self.model,
                latency_ms=3,
                error=f"AuthenticationError: invalid key {key}",
            )

    assert await cli.cmd_conversation_eval_prepare(_prep_args(tmp_path)) == 0
    prepared = tmp_path / "out" / ce.PREPARED_NAME
    approve = json.loads(prepared.read_text(encoding="utf-8"))["manifest_sha256"][:8]
    monkeypatch.setattr("mentorai.ai.providers.build_client", lambda: _Failing())

    code = await cli.cmd_conversation_eval_run(_run_args(prepared, arms="A", approve=approve))

    captured = capsys.readouterr()
    everything = captured.out + captured.err
    for path in (tmp_path / "out").iterdir():
        everything += path.read_text(encoding="utf-8-sig")
    assert code == 0
    assert key not in everything
    from mentorai.config import get_settings

    assert get_settings().database_url.get_secret_value() not in everything


def test_the_run_command_has_no_default_cap() -> None:
    parser_source = Path(cli.__file__).read_text(encoding="utf-8")
    block = parser_source.split('"conversation-eval-run"', 1)[1].split("crep2 =", 1)[0]

    assert re.search(r'"--max-cost-usd",\s*type=float,\s*required=True', block)
    assert "dry-run" not in block


# ---------------------------------------------------------------------------
# ۹) خواندن برگه‌ی پرشده و گزارش
# ---------------------------------------------------------------------------


def _grade_rows(sheet: str, key: dict[str, Any], scores: dict[str, dict[str, Any]]) -> str:
    """برگه‌ی پرشده: نمره‌ی هر بازو را از روی کلید می‌دهیم (داور خودش بازو را نمی‌داند)."""
    rows = list(csv.DictReader(io.StringIO(sheet)))
    out = io.StringIO()
    writer = csv.DictWriter(out, fieldnames=ce.sheet_header(), lineterminator="\n")
    writer.writeheader()
    for row in rows:
        label = row[ce.ID_LABEL]
        arm = ce.sheet_order(key, label, list(key["arms"]))[int(row[ce.POSITION_LABEL]) - 1]
        for crit_key, value in scores[arm].items():
            if crit_key in ce.CRITERIA_LABEL:
                row[f"{ce.CRITERIA_LABEL[crit_key]} (۱ تا ۵)"] = str(value)
            else:
                row[crit_key] = str(value)
        writer.writerow(row)
    return out.getvalue()


async def test_the_report_maps_grades_back_to_the_right_arm_through_the_key(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    _, _, paths = await _full_run(tmp_path)
    key = json.loads(paths["key"].read_text(encoding="utf-8"))
    sheet = paths["sheet"].read_text(encoding="utf-8-sig")
    graded = _grade_rows(
        sheet,
        key,
        {
            "A": {"tone": 2, "accuracy": 4, ce.OVERALL_LABEL: 1, ce.INVENTED_LABEL: 1},
            "C": {"tone": 5, "accuracy": 4, ce.OVERALL_LABEL: 3, ce.SHOULD_REFER_LABEL: 1},
        },
    )
    graded_path = tmp_path / "graded.csv"
    graded_path.write_text("﻿" + graded, encoding="utf-8")

    report = ce.make_report(paths["key"], graded_path)

    assert "طبیعی بودن لحن: A: 2.00 (n=3) | C: 5.00 (n=3)" in report
    assert "صحت آموزشی: A: 4.00 (n=3) | C: 4.00 (n=3)" in report
    assert "طبیعی بودن لحن: +3.00" in report and "C بهتر: 3" in report
    assert "ساخته‌شده=['C01', 'C02', 'C03']" in report.split("A:")[-1] or "ساخته‌شده" in report
    assert "کمتر از 30" in report, "۳ نمونه نتیجه‌ی قطعی نیست و باید گفته شود"
    assert "آستانه‌ی قبولی را مالک تعیین می‌کند" in report
    assert "انجام نشد" not in report
    for secret in (PHONE, STUDENT_NAME, "دوره مقدماتی"):
        assert secret not in report


async def test_invalid_scores_are_reported_not_silently_accepted(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    _, _, paths = await _full_run(tmp_path)
    key = json.loads(paths["key"].read_text(encoding="utf-8"))
    sheet = paths["sheet"].read_text(encoding="utf-8-sig")
    graded = _grade_rows(
        sheet,
        key,
        {
            "A": {"tone": 9, ce.OVERALL_LABEL: 7, ce.INVENTED_LABEL: "شاید"},
            "C": {"tone": 3},
        },
    )
    graded_path = tmp_path / "graded.csv"
    graded_path.write_text(graded, encoding="utf-8")

    grades, problems = ce.load_grades(graded_path, key)

    assert any("نمره‌ی نامعتبر" in p and "طبیعی بودن لحن" in p for p in problems)
    assert any("کلی" in p for p in problems)
    assert any("بله/خیر نامعتبر" in p for p in problems)
    assert all(g.scores["tone"] in (None, 3) for g in grades.values())


async def test_a_sheet_with_changed_columns_is_refused(
    scenario: dict[str, int], tmp_path: Path
) -> None:
    _, _, paths = await _full_run(tmp_path)
    key = json.loads(paths["key"].read_text(encoding="utf-8"))
    bad = tmp_path / "bad.csv"
    bad.write_text("a,b\n1,2\n", encoding="utf-8")

    with pytest.raises(ce.EvalError, match="ستون"):
        ce.load_grades(bad, key)
    with pytest.raises(ce.EvalError, match="کلید"):
        ce.load_key(bad)
    not_a_key = tmp_path / "k.json"
    not_a_key.write_text("{}", encoding="utf-8")
    with pytest.raises(ce.EvalError, match="کلید conversation-eval"):
        ce.load_key(not_a_key)
