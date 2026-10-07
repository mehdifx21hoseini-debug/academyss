"""رفتار فعلی دو شکاف شناخته‌شده را ثبت می‌کند (RO-1، characterization).

⚠️ این تست‌ها **عیب را تأیید نمی‌کنند**؛ فقط ثبت می‌کنند امروز چه رخ می‌دهد، تا اصلاحشان
در مرحله‌ی خودش یک تصمیم آگاهانه باشد، نه یک تغییر بی‌صدا. هر کدام جایی دارند که باید
برگردانده شود:

- رونویسی ویس به قواعد قطعی داده نمی‌شود ← RO-2 (با تأیید جدای مالک، چون رفتار زنده
  را عوض می‌کند). آن‌وقت `test_current_voice_transcript_is_not_given_to_the_rules`
  باید وارونه شود.
- «شرط‌های» هر قاعده (`conditions`) در ستون `notes` می‌مانند و به مدل نمی‌رسند ← RO-K.
  آن‌وقت `test_current_notes_never_reach_the_model` باید وارونه شود.

ممیزی و شاهد: `docs/RESPONSE_ORCHESTRATION.md` §۲ (یافته‌های A و B).
"""

from __future__ import annotations

import csv
from pathlib import Path

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from tests import test_runtime as _rt
from tests.test_runtime import COLUMNS, _confident, _incoming, _with_media

from mentorai.ai.client import ScriptedClient
from mentorai.ai.runtime import handle_message
from mentorai.db.models import MentorAccount, Outcome
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.ingest import ingest_csv

# فیکسچر بردارساز از test_runtime.py (نسبت دادن، نه import: نام پارامتر را «تعریف دوباره»
# حساب نمی‌کند).
embedder = _rt.embedder

# عبارت مالیِ قاعده‌ی قطعی + سؤالی که در KB جواب دارد.
MONEY_AND_COURSE = "رسید واریزم؛ دوره مقدماتی چند جلسه است؟"

NOTE_MARKER = "شرط-ویژه-۷۷۱"


@pytest.fixture
async def course_knowledge(
    session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder
) -> None:
    """یک سند، همراه یادداشتی که شرط قاعده را نگه می‌دارد."""
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
                "policy",
                "",
                "",
                f"شرط: {NOTE_MARKER}",
            ]
        )
    await ingest_csv(session, path, embedder=embedder)
    await session.commit()


async def test_current_text_with_a_money_phrase_hits_the_rule(
    session: AsyncSession,
    account: MentorAccount,
    course_knowledge: None,
    embedder: HashingEmbedder,
) -> None:
    """شاهدِ مقایسه: همان عبارت، وقتی متن پیام باشد، قاعده را می‌گیرد."""
    message = await _incoming(session, account, MONEY_AND_COURSE)
    client = ScriptedClient(_confident())

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.silence
    assert result.reason == "rule_money"
    assert client.calls == []


async def test_current_voice_transcript_is_not_given_to_the_rules(
    session: AsyncSession,
    account: MentorAccount,
    course_knowledge: None,
    embedder: HashingEmbedder,
) -> None:
    """رونویسی ویس هرگز به قواعد قطعی نمی‌رسد: همان عبارتِ مالی به مدل می‌رسد و پاسخ می‌گیرد.

    CHARACTERIZATION: رفتار امروز. اصلاح در RO-2 (نیازمند تأیید جدا).
    """
    message = await _incoming(session, account, None, media_type="voice")
    await _with_media(session, message, kind="voice", text=MONEY_AND_COURSE)
    client = ScriptedClient(_confident())

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.reason != "rule_money", "اگر این شکست خورد، رونویسی به قواعد داده شده است"
    assert result.outcome is Outcome.answer
    assert client.calls, "مدل با متن رونویسی صدا زده می‌شود"
    assert MONEY_AND_COURSE in client.calls[0][1]


async def test_current_notes_never_reach_the_model(
    session: AsyncSession,
    account: MentorAccount,
    course_knowledge: None,
    embedder: HashingEmbedder,
) -> None:
    """یادداشت سند (جای `conditions`) ذخیره می‌شود ولی هرگز در دستور مدل نمی‌آید.

    CHARACTERIZATION: رفتار امروز. اصلاح در RO-K (اتم‌ها).
    """
    stored = (await session.execute(text("select notes from knowledge_documents"))).scalar_one()
    assert NOTE_MARKER in stored, "پیش‌شرط: یادداشت در پایگاه داده هست"

    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(_confident())
    await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    system, user = client.calls[0]
    assert "شانزده جلسه" in user, "پیش‌شرط: متن سند در دستور مدل هست"
    assert NOTE_MARKER not in user
    assert NOTE_MARKER not in system
    runs = (await session.execute(text("select retrieved from ai_runs"))).scalar_one()
    assert NOTE_MARKER not in str(runs), "حتی در ثبت اسناد بازیابی‌شده هم نیست"
