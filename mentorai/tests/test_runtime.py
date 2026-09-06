"""خط پردازش پیام: تصمیم، تولید، ثبت.

مهم‌ترین چیزی که این تست‌ها می‌سنجند، جهت شکست است: هر مسیری که به یقین نرسد باید به
سکوت ختم شود، نه به پاسخ حدسی.
"""

from __future__ import annotations

import csv
from datetime import UTC, datetime
from pathlib import Path

import pytest
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai.client import ScriptedClient
from mentorai.ai.runtime import SilenceReason, handle_message
from mentorai.ai.schema import ModelAnswer
from mentorai.db.models import AiRun, Escalation, MentorAccount, Message, Outcome, Sender
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.ingest import ingest_csv
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound

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


@pytest.fixture
def embedder() -> HashingEmbedder:
    return HashingEmbedder()


@pytest.fixture
async def knowledge(session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder) -> None:
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
    await ingest_csv(session, path, embedder=embedder)
    await session.commit()


async def _incoming(
    session: AsyncSession, account: MentorAccount, body: str, message_id: int = 1
) -> Message:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=500,
        message_id=message_id,
        sender_user_id=500,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text=body,
        media_type=None,
        reply_to_message_id=None,
        sent_at=datetime(2026, 9, 2, 12, 0, tzinfo=UTC),
        is_private=True,
        is_outgoing=False,
    )
    result = await record_inbound(session, account, inbound, sender=Sender.student)
    await session.commit()
    assert result.message_id is not None
    return await session.get_one(Message, result.message_id)


def _confident(text_: str = "دوره مقدماتی شانزده جلسه دارد.") -> ModelAnswer:
    return ModelAnswer(
        answer=text_, confidence=0.95, needs_human=False, reason="از منبع رسمی", used_chunk_ids=[1]
    )


async def test_confident_answer_is_produced(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(_confident())

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.answer
    assert result.answer_text == "دوره مقدماتی شانزده جلسه دارد."


async def test_sensitive_topic_is_silent_and_never_calls_the_model(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    """قاعده‌ی قطعی پیش از مدل اجرا می‌شود، پس هزینه‌ی مدل هم ندارد."""
    message = await _incoming(session, account, "رسید واریزم رو فرستادم چی شد؟")
    client = ScriptedClient(_confident())

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.silence
    assert result.reason == "rule_money"
    assert client.calls == [], "مدل نباید فراخوانی می‌شد"


async def test_no_sources_is_silent_and_never_calls_the_model(
    session: AsyncSession, account: MentorAccount, embedder: HashingEmbedder
) -> None:
    message = await _incoming(session, account, "سؤالی که هیچ سندی ندارد")
    client = ScriptedClient(_confident())

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.silence
    assert result.reason == SilenceReason.no_sources.value
    assert client.calls == []


async def test_model_error_falls_back_to_silence_not_a_guess(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(None, error="timeout")

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.silence
    assert result.reason == SilenceReason.model_error.value
    run = (await session.execute(select(AiRun))).scalar_one()
    assert run.error == "timeout"


async def test_model_flagging_human_is_respected(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(
        ModelAnswer(answer="نمی‌دانم", confidence=0.99, needs_human=True, reason="مطمئن نیستم")
    )

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.silence
    assert result.reason == SilenceReason.model_flagged.value


async def test_low_confidence_is_silent(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    """اطمینان پایین باید به سکوت ختم شود.

    در سیستم قبلی آکادمی این عدد گرفته می‌شد ولی در تصمیم هیچ نقشی نداشت.
    """
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(
        ModelAnswer(answer="شاید شانزده جلسه", confidence=0.4, needs_human=False, reason="حدس")
    )

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.silence
    assert result.reason == SilenceReason.low_confidence.value


async def test_empty_answer_is_silent(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(
        ModelAnswer(answer="   ", confidence=0.99, needs_human=False, reason="خالی")
    )

    result = await handle_message(session, message, model_client=client, embedder=embedder)
    await session.commit()

    assert result.outcome is Outcome.silence
    assert result.reason == SilenceReason.empty_answer.value


async def test_every_path_records_a_run(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    for i, (body, client) in enumerate(
        [
            ("دوره مقدماتی چند جلسه است؟", ScriptedClient(_confident())),
            ("رسید واریز", ScriptedClient(_confident())),
            ("دوره مقدماتی چند جلسه است؟", ScriptedClient(None, error="boom")),
        ],
        start=1,
    ):
        message = await _incoming(session, account, body, message_id=i)
        await handle_message(session, message, model_client=client, embedder=embedder)
        await session.commit()

    count = (await session.execute(text("select count(*) from ai_runs"))).scalar_one()
    assert count == 3


async def test_silence_records_an_escalation_and_an_answer_does_not(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    silent = await _incoming(session, account, "شکایت دارم", message_id=1)
    await handle_message(
        session, silent, model_client=ScriptedClient(_confident()), embedder=embedder
    )
    answered = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟", message_id=2)
    await handle_message(
        session, answered, model_client=ScriptedClient(_confident()), embedder=embedder
    )
    await session.commit()

    escalations = list((await session.execute(select(Escalation))).scalars())
    assert len(escalations) == 1
    assert escalations[0].message_id == silent.id
    assert escalations[0].resolved_at is None


async def test_run_records_retrieval_scores(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    """بدون امتیازها نمی‌شود فهمید بازیابی ضعیف بوده یا مدل."""
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    await handle_message(
        session, message, model_client=ScriptedClient(_confident()), embedder=embedder
    )
    await session.commit()

    run = (await session.execute(select(AiRun))).scalar_one()
    assert run.retrieved
    first = run.retrieved[0]
    assert {"chunk_id", "document_id", "score", "source_class", "authority"} <= set(first)
    assert run.model == "scripted-test-only"
    assert run.prompt_version == "v1"
    assert run.latency_ms is not None


async def test_sources_and_question_reach_the_prompt(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(_confident())
    await handle_message(session, message, model_client=client, embedder=embedder)

    system, user = client.calls[0]
    assert "آکادمی سبحان صمدی" in system
    assert "شانزده جلسه" in user, "منبع بازیابی‌شده باید در پیام کاربر باشد"
    assert "دوره مقدماتی چند جلسه است؟" in user
    assert "منابع" in user


async def test_one_run_per_message_even_if_handled_twice(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: HashingEmbedder
) -> None:
    """تلاش دوباره‌ی یک کار نباید رکورد دوم بسازد."""
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    await handle_message(
        session, message, model_client=ScriptedClient(_confident()), embedder=embedder
    )
    await session.commit()

    from sqlalchemy.exc import IntegrityError

    with pytest.raises(IntegrityError):
        await handle_message(
            session, message, model_client=ScriptedClient(_confident()), embedder=embedder
        )
        await session.commit()
    await session.rollback()

    count = (await session.execute(text("select count(*) from ai_runs"))).scalar_one()
    assert count == 1
