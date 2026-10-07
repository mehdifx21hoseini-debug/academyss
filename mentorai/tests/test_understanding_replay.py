"""بازپخش مرحله‌ی فهم (RO-2، حالت سایه): فقط‌خواندنی، بی‌اثر روی پاسخ‌دهی، بی‌متن در خلاصه.

مدل `ScriptedClient` است؛ هیچ فراخوانی واقعی انجام نمی‌شود. آنچه سنجیده می‌شود لوله‌کشی و
**نبودِ اثر جانبی** است، نه درستیِ قضاوت Claude.
"""

from __future__ import annotations

import ast
import dataclasses
import json
import stat
from argparse import Namespace
from pathlib import Path

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from tests import test_runtime as _rt
from tests.test_runtime import _confident, _incoming, _with_media
from tests.test_understanding import SRC, _imports, _part, _payload

from mentorai import cli
from mentorai import understanding_replay as replay
from mentorai.ai import understanding as u
from mentorai.ai.client import RawCall, ScriptedClient
from mentorai.ai.prompt import SYSTEM_PROMPT as LEGACY_PROMPT
from mentorai.ai.runtime import handle_message
from mentorai.db.models import Base, Conversation, MentorAccount, Message, Outcome, StudentMemory
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.model_compare import Case, sample_from_database

embedder = _rt.embedder
knowledge = _rt.knowledge

PHONE = "09121234567"
EMAIL = "student@example.com"


async def _snapshot(session: AsyncSession) -> dict[str, tuple[int, str]]:
    """شمار و checksum هر جدول. اگر چیزی نوشته یا تغییر کند، این عوض می‌شود."""
    snapshot: dict[str, tuple[int, str]] = {}
    for table in Base.metadata.sorted_tables:
        row = (
            await session.execute(
                text(
                    "select count(*), "
                    "md5(coalesce(string_agg(t::text, '|' order by t::text), '')) "
                    f'from "{table.name}" t'
                )
            )
        ).one()
        snapshot[table.name] = (int(row[0]), str(row[1]))
    return snapshot


async def _chat(session: AsyncSession, account: MentorAccount) -> list[Message]:
    """سه پیام پشت‌سرهم از یک دانشجو، و یک حافظه‌ی فعال برای او."""
    first = await _incoming(session, account, "فوروارد تست چیست؟", message_id=1)
    second = await _incoming(session, account, f"من با شماره {PHONE} ثبت‌نام کردم", message_id=2)
    third = await _incoming(session, account, f"چند روز باید انجامش بدم؟ {EMAIL}", message_id=3)
    conversation = await session.get_one(Conversation, third.conversation_id)
    session.add(
        StudentMemory(
            student_id=conversation.student_id,
            category="learning_stage",
            content=f"بعد از دوره مقدماتی است؛ تماس {PHONE}",
            content_key="learning-stage-1",
            confidence=0.9,
            source="mentor",
        )
    )
    await session.commit()
    return [first, second, third]


def _cases(messages: list[Message]) -> list[Case]:
    return [Case(id=f"m{m.id}", question=m.text or "") for m in messages]


def _client(payload: str | None = None) -> ScriptedClient:
    return ScriptedClient(raw_text=payload or _payload(_part()))


# ---------------------------------------------------------------------------
# زمینه و پوشاندن
# ---------------------------------------------------------------------------


async def test_replay_gives_the_model_the_history_and_memory_the_live_path_sees(
    session: AsyncSession, account: MentorAccount
) -> None:
    messages = await _chat(session, account)
    client = _client()

    data = await replay.run_replay(session, _cases(messages[2:]), client)

    assert len(client.calls) == 1
    system, user = client.calls[0]
    assert system == u.SYSTEM_PROMPT
    assert "فوروارد تست چیست؟" in user, "پیام‌های قبلی همان گفتگو"
    assert "بعد از دوره مقدماتی" in user, "حافظه‌ی فعال دانشجو"
    assert user.rstrip().endswith("چند روز باید انجامش بدم؟ " + replay.mask_personal(EMAIL))
    assert data.cases[0].history_turns == 2
    assert data.cases[0].had_memories


async def test_personal_data_is_masked_before_anything_is_sent(
    session: AsyncSession, account: MentorAccount
) -> None:
    messages = await _chat(session, account)
    client = _client()

    data = await replay.run_replay(session, _cases(messages[2:]), client)

    _, user = client.calls[0]
    assert PHONE not in user and EMAIL not in user, "حتی در تاریخچه‌ی پیام‌های قبلی"
    assert replay.mask_personal(PHONE) in user
    assert PHONE not in data.cases[0].question and EMAIL not in data.cases[0].question


async def test_a_message_the_live_path_never_gives_the_model_is_not_given_here_either(
    session: AsyncSession, account: MentorAccount
) -> None:
    money = await _incoming(session, account, "رسید واریزم رو فرستادم چی شد؟", message_id=1)
    fine = await _incoming(session, account, "ریسک به ریوارد یعنی چه؟", message_id=2)
    client = _client()

    data = await replay.run_replay(session, _cases([money, fine]), client)

    assert data.excluded == {"rule_money": 1}
    assert len(client.calls) == 1
    assert "رسید واریزم" not in client.calls[0][1].split("پیام فعلی دانشجو")[-1]
    assert [c.id for c in data.cases] == [f"m{fine.id}"]


async def test_a_case_without_a_stored_message_is_understood_without_context(
    session: AsyncSession,
) -> None:
    """پرسش‌های CSV پیام ذخیره‌شده ندارند: بدون تاریخچه و حافظه، ولی بدون خطا."""
    client = _client()

    data = await replay.run_replay(session, [Case(id="probe-1", question="سلام")], client)

    assert data.cases[0].history_turns == 0 and not data.cases[0].had_memories
    assert data.cases[0].result is not None and data.cases[0].result.ok


# ---------------------------------------------------------------------------
# هیچ اثر جانبی
# ---------------------------------------------------------------------------


async def test_replay_writes_nothing_to_the_database(
    session: AsyncSession, account: MentorAccount, tmp_path: Path
) -> None:
    messages = await _chat(session, account)
    before = await _snapshot(session)
    assert any(count for count, _ in before.values()), "پیش‌شرط: پایگاه داده خالی نیست"

    data = await replay.run_replay(session, _cases(messages), _client())
    replay.write_replay(data, tmp_path / "out")
    # اگر بازپخش چیزی نوشته بود، این commit آن را ثابت می‌کرد و مقایسه می‌شکست.
    await session.commit()

    assert await _snapshot(session) == before


async def test_replay_leaves_the_live_decision_on_a_real_message_unchanged(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    """همان پرسش، پیش و پس از بازپخش، همان حکم و همان فراخوانی مدلِ قدیمی را می‌گیرد."""
    question = "دوره مقدماتی چند جلسه است؟"
    before_message = await _incoming(session, account, question, message_id=1)
    case = Case(id=f"m{before_message.id}", question=question)
    before_client = ScriptedClient(_confident())
    before = await handle_message(
        session, before_message, model_client=before_client, embedder=embedder
    )
    await session.commit()

    await replay.run_replay(session, [case], _client())

    after_message = await _incoming(session, account, question, message_id=9)
    after_client = ScriptedClient(_confident())
    after = await handle_message(
        session, after_message, model_client=after_client, embedder=embedder
    )
    await session.commit()

    assert (before.outcome, before.reason, before.answer_text) == (
        after.outcome,
        after.reason,
        after.answer_text,
    )
    assert before_client.calls[0][0] == after_client.calls[0][0] == LEGACY_PROMPT
    assert len(before_client.calls) == len(after_client.calls) == 1
    runs = (await session.execute(text("select count(*) from ai_runs"))).scalar_one()
    assert runs == 2, "بازپخش هیچ اجرای تازه‌ای نساخت"


def test_the_replay_module_cannot_send_anything() -> None:
    forbidden = (
        "mentorai.telegram",
        "mentorai.delivery",
        "mentorai.drafts",
        "mentorai.escalation",
        "mentorai.worker",
        "mentorai.conversation",
        "mentorai.control",
        "mentorai.jobs",
    )
    names = _imports(SRC / "understanding_replay.py")
    assert not {n for n in names if n.startswith(forbidden)}, sorted(names)


def test_the_replay_module_has_no_database_write_calls() -> None:
    """هیچ add/execute/commit/flush/delete: فقط get و خواندن از طریق توابع موجود."""
    tree = ast.parse((SRC / "understanding_replay.py").read_text(encoding="utf-8"))
    calls = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert not calls & {"add", "add_all", "execute", "commit", "flush", "delete", "merge"}


# ---------------------------------------------------------------------------
# خلاصه و فایل‌ها
# ---------------------------------------------------------------------------


async def test_the_summary_has_counts_but_no_text_at_all(
    session: AsyncSession, account: MentorAccount
) -> None:
    messages = await _chat(session, account)
    payload = _payload(
        _part(1, "فوروارد-تست-راز-۷۷۱ چیست؟", queries=("کلید-راز-۷۷۱",)),
        _part(2, "پرسش دوم", topic="academy_policy", fact_class="general_knowledge"),
    )

    data = await replay.run_replay(session, _cases(messages), _client(payload))
    summary = replay.summarise(data)

    assert "پیام چندبخشی" in summary and "اصلاح‌های کدی" in summary
    assert "academy_topic_forces_academy_fact" in summary
    for secret in ("راز-۷۷۱", "فوروارد تست چیست", "پرسش دوم", PHONE, EMAIL, "بعد از دوره مقدماتی"):
        assert secret not in summary
    assert "اطمینان حوزه" in summary


async def test_the_files_are_private_and_the_json_has_the_full_output(
    session: AsyncSession, account: MentorAccount, tmp_path: Path
) -> None:
    messages = await _chat(session, account)
    data = await replay.run_replay(session, _cases(messages[2:]), _client())

    paths = replay.write_replay(data, tmp_path / "out")

    for path in paths.values():
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert stat.S_IMODE((tmp_path / "out").stat().st_mode) == 0o700
    doc = json.loads(paths["replay"].read_text(encoding="utf-8"))
    assert doc["version"] == replay.REPLAY_VERSION
    assert doc["prompt_version"] == "understand-v2"
    case = doc["cases"][0]
    assert case["understanding"]["parts"][0]["standalone_question"]
    assert case["raw"] and case["error"] is None
    assert PHONE not in paths["replay"].read_text(encoding="utf-8")


async def test_errors_are_counted_not_hidden(session: AsyncSession, account: MentorAccount) -> None:
    messages = await _chat(session, account)

    data = await replay.run_replay(session, _cases(messages), _client("نه JSON"))
    summary = replay.summarise(data)

    assert all(c.result is not None and c.result.error == "invalid_output" for c in data.cases)
    assert "invalid_output" in summary
    assert "فهمیده شد: 0 (0٪)" in summary


async def test_dry_run_calls_no_model_and_counts_eligible_messages(
    session: AsyncSession, account: MentorAccount
) -> None:
    messages = await _chat(session, account)
    client = _client()

    data = await replay.run_replay(session, _cases(messages), client, dry_run=True)

    assert client.calls == []
    assert len(data.cases) == 3 and all(c.result is None for c in data.cases)
    assert "--dry-run بود" in replay.summarise(data)


# ---------------------------------------------------------------------------
# سقف هزینه
# ---------------------------------------------------------------------------


class _Growing(ScriptedClient):
    """هر فراخوانی گران‌تر از قبلی: برآورد اول کم است و بعداً از سقف می‌گذرد."""

    async def raw(self, *, system: str, user: str, schema: dict[str, object]) -> RawCall:
        call = await super().raw(system=system, user=user, schema=schema)
        grown = call.input_tokens * 100 * len(self.calls) ** 3
        return dataclasses.replace(call, input_tokens=grown)


async def test_the_first_cost_estimate_stops_a_run_that_would_overspend(
    session: AsyncSession, account: MentorAccount
) -> None:
    messages = await _chat(session, account)
    client = _client()

    with pytest.raises(replay.CostLimitExceeded):
        await replay.run_replay(session, _cases(messages), client, max_cost_usd=1e-9)

    assert len(client.calls) == 1, "پس از نخستین پرسش متوقف می‌شود"


async def test_a_run_whose_cost_grows_stops_early_and_says_so(
    session: AsyncSession, account: MentorAccount
) -> None:
    messages = await _chat(session, account)
    client = _Growing(raw_text=_payload(_part()))

    data = await replay.run_replay(session, _cases(messages), client, max_cost_usd=0.05)

    assert data.stopped_early
    assert len(client.calls) < 3
    assert "به سقف هزینه خورد" in replay.summarise(data)


# ---------------------------------------------------------------------------
# ویس: رفتار فعلی بی‌تغییر (characterization)
# ---------------------------------------------------------------------------


async def test_a_voice_message_still_goes_through_the_legacy_prompt_only(
    session: AsyncSession,
    account: MentorAccount,
    knowledge: None,
    embedder: HashingEmbedder,
) -> None:
    """CHARACTERIZATION. ویسِ رونویسی‌شده امروز یک بار به مدل پاسخ می‌رسد و بس.

    مرحله‌ی فهم به این مسیر وصل نیست: دستور قدیمی تنها دستور فرستاده‌شده است، و قاعده‌های
    قطعی هنوز روی رونویسی اجرا نمی‌شوند (اصلاحش RO-2 قدیمیِ طرح است و تأیید جدا می‌خواهد).
    """
    message = await _incoming(session, account, None, media_type="voice")
    await _with_media(
        session, message, kind="voice", text="رسید واریزم؛ دوره مقدماتی چند جلسه است؟"
    )
    client = ScriptedClient(_confident())

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.answer and result.reason != "rule_money"
    assert len(client.calls) == 1
    assert client.calls[0][0] == LEGACY_PROMPT
    assert u.SYSTEM_PROMPT not in client.calls[0][0]


async def test_voice_messages_are_not_part_of_the_replay_sample(
    session: AsyncSession, account: MentorAccount
) -> None:
    """CHARACTERIZATION. نمونه‌گیر فقط پیام بی‌فایل می‌خواند، پس ویس در این نسخه نیست."""
    voice = await _incoming(session, account, None, media_type="voice", message_id=1)
    await _with_media(session, voice, kind="voice", text="ریسک به ریوارد یعنی چه؟ لطفاً بگویید")
    text_message = await _incoming(session, account, "ریسک به ریوارد یعنی چه؟", message_id=2)

    sampled = await sample_from_database(session, limit=10, seed=1)

    assert [c.id for c in sampled] == [f"m{text_message.id}"]


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
    await _chat(session, account)

    code = await cli.cmd_understand_run(_args(tmp_path, dry_run=True))

    assert code == 0
    assert "--dry-run بود" in capsys.readouterr().out
    assert not (tmp_path / "out").exists()


async def test_the_command_runs_end_to_end_with_a_scripted_client(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _chat(session, account)
    client = _client()
    monkeypatch.setattr("mentorai.ai.providers.build_client", lambda: client)
    before = await _snapshot(session)

    code = await cli.cmd_understand_run(_args(tmp_path))

    out = capsys.readouterr().out
    assert code == 0
    assert (tmp_path / "out" / replay.SUMMARY_NAME).exists()
    assert "خلاصه (بی‌متن)" in out and "replay.json" in out
    assert "پیام واقعی" in out, "هشدار حریم خصوصی چاپ می‌شود"
    assert len(client.calls) >= 1
    assert await _snapshot(session) == before


async def test_the_command_reports_a_broken_ai_configuration_without_a_traceback(
    session: AsyncSession,
    account: MentorAccount,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    await _chat(session, account)

    def broken() -> ScriptedClient:
        raise ValueError("AI_MODEL ناقص است")

    monkeypatch.setattr("mentorai.ai.providers.build_client", broken)

    code = await cli.cmd_understand_run(_args(tmp_path))

    assert code == 1
    assert "AI_MODEL ناقص است" in capsys.readouterr().err
    assert not (tmp_path / "out").exists()


def test_the_command_is_registered_on_the_cli_parser() -> None:
    parser_source = (SRC / "cli.py").read_text(encoding="utf-8")
    assert '"understand-run"' in parser_source
    assert "cmd_understand_run" in parser_source
