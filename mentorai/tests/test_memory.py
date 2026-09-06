"""ذخیره‌سازی حافظه و اثرش روی مسیر پاسخ."""

from __future__ import annotations

import csv
import json
from datetime import UTC, datetime
from pathlib import Path

import pytest
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession
from tests.test_sender import FakeChannel

from mentorai.ai.client import ScriptedClient
from mentorai.ai.schema import ModelAnswer
from mentorai.db.models import (
    Conversation,
    MemorySource,
    MentorAccount,
    Message,
    Sender,
    Student,
    StudentMemory,
)
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.ingest import ingest_csv
from mentorai.memory import job as memory_job
from mentorai.memory import store as memory_store
from mentorai.memory.policy import Candidate
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound
from mentorai.worker import process_message

NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)


@pytest.fixture
def embedder() -> HashingEmbedder:
    return HashingEmbedder()


@pytest.fixture
async def kb(session: AsyncSession, tmp_path: Path, embedder: HashingEmbedder) -> None:
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
        writer.writerow(
            [
                "official",
                "دوره‌ها",
                "دوره مقدماتی چیست؟",
                "شامل شانزده جلسه است.",
                "fact",
                "",
                "",
                "",
            ]
        )
    await ingest_csv(session, path, embedder=embedder)
    await session.commit()


@pytest.fixture
async def student(session: AsyncSession) -> Student:
    row = Student(display_name="دانشجو")
    session.add(row)
    await session.flush()
    return row


def _cand(**kw: object) -> Candidate:
    base = {"category": "interest", "content": "به پرایس اکشن علاقه دارد.", "confidence": 0.9}
    return Candidate(**{**base, **kw})  # type: ignore[arg-type]


async def test_accepted_candidate_is_stored(session: AsyncSession, student: Student) -> None:
    report = await memory_store.apply_candidates(
        session, student_id=student.id, candidates=[_cand()], source=MemorySource.extracted
    )
    await session.commit()

    assert len(report.stored) == 1
    rows = list((await session.execute(select(StudentMemory))).scalars())
    assert len(rows) == 1
    assert rows[0].source == "extracted"


async def test_rejected_candidate_is_counted_but_its_content_is_not_kept(
    session: AsyncSession, student: Student
) -> None:
    """اگر متن ردشده ذخیره شود، همان اطلاعاتی که سیاست جلویش را گرفت جای دیگری می‌ماند."""
    secret = "شماره‌اش ۰۹۱۲۳۴۵۶۷۸۹ است."
    report = await memory_store.apply_candidates(
        session,
        student_id=student.id,
        candidates=[_cand(content=secret)],
        source=MemorySource.extracted,
    )
    await session.commit()

    assert report.stored == [] and len(report.rejected) == 1
    assert (await session.execute(text("select count(*) from student_memories"))).scalar_one() == 0

    stored_rows = (
        await session.execute(text("select reason, detail from memory_rejections"))
    ).all()
    assert stored_rows == [("contains_pii", "phone")]
    dump = json.dumps(
        [
            dict(r._mapping)
            for r in (await session.execute(text("select * from memory_rejections")))
        ],
        default=str,
        ensure_ascii=False,
    )
    assert "0912" not in dump and "۰۹۱۲" not in dump


async def test_the_same_fact_is_not_stored_twice(session: AsyncSession, student: Student) -> None:
    await memory_store.apply_candidates(
        session, student_id=student.id, candidates=[_cand()], source=MemorySource.extracted
    )
    await session.commit()
    report = await memory_store.apply_candidates(
        session,
        student_id=student.id,
        candidates=[_cand(content="به پرايس اکشن علاقه دارد.")],
        source=MemorySource.extracted,
    )
    await session.commit()

    assert report.duplicates == 1
    assert (await session.execute(text("select count(*) from student_memories"))).scalar_one() == 1


async def test_single_valued_category_supersedes_the_previous_value(
    session: AsyncSession, student: Student
) -> None:
    await memory_store.apply_candidates(
        session,
        student_id=student.id,
        candidates=[_cand(category="learning_stage", content="تازه‌کار است.")],
        source=MemorySource.extracted,
    )
    await session.commit()
    report = await memory_store.apply_candidates(
        session,
        student_id=student.id,
        candidates=[_cand(category="learning_stage", content="به سطح متوسط رسیده.")],
        source=MemorySource.extracted,
    )
    await session.commit()

    assert report.superseded == 1
    active = await memory_store.load_active(session, student.id)
    assert [m.content for m in active] == ["به سطح متوسط رسیده."]
    # مقدار قبلی حذف نمی‌شود، فقط کنار می‌رود؛ تاریخچه ارزش دارد.
    total = (await session.execute(text("select count(*) from student_memories"))).scalar_one()
    assert total == 2


async def test_multi_valued_category_keeps_both(session: AsyncSession, student: Student) -> None:
    await memory_store.apply_candidates(
        session,
        student_id=student.id,
        candidates=[
            _cand(content="به پرایس اکشن علاقه دارد."),
            _cand(content="به روانشناسی معامله‌گری علاقه دارد."),
        ],
        source=MemorySource.extracted,
    )
    await session.commit()

    assert len(await memory_store.load_active(session, student.id)) == 2


async def test_deleting_a_student_removes_their_memory(
    session: AsyncSession, student: Student
) -> None:
    """قاعده‌ی راهنمای امنیت: حذف دانشجو باید به هر جایی که داده‌اش هست برسد."""
    await memory_store.apply_candidates(
        session, student_id=student.id, candidates=[_cand()], source=MemorySource.extracted
    )
    await session.commit()

    await session.execute(text("delete from students where id = :id"), {"id": student.id})
    await session.commit()

    assert (await session.execute(text("select count(*) from student_memories"))).scalar_one() == 0


async def test_render_is_empty_when_there_is_nothing(
    session: AsyncSession, student: Student
) -> None:
    assert memory_store.render(await memory_store.load_active(session, student.id)) == ""


async def test_extraction_is_not_run_on_every_message(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    """یک فراخوانی مدل به‌ازای هر پیام یعنی دوبرابر شدن هزینه، برای چیزی که کند تغییر می‌کند."""
    conversation_id: int | None = None
    for i in range(1, 6):
        inbound = build_inbound(
            account_slug=account.slug,
            chat_id=1000,
            message_id=i,
            sender_user_id=1000,
            username=None,
            first_name="دانشجو",
            last_name=None,
            raw_text="دوره مقدماتی چیست؟",
            media_type=None,
            reply_to_message_id=None,
            sent_at=NOON,
            is_private=True,
            is_outgoing=False,
        )
        result = await record_inbound(session, account, inbound, sender=Sender.student)
        conversation_id = result.conversation_id
        await session.commit()
        assert await memory_job.should_extract(session, conversation_id) is (i % 5 == 0)


async def test_extraction_stores_what_the_policy_allows(
    session: AsyncSession, account: MentorAccount
) -> None:
    student = Student(display_name="دانشجو")
    session.add(student)
    await session.flush()
    conversation = Conversation(account_id=account.id, student_id=student.id, telegram_chat_id=1100)
    session.add(conversation)
    await session.flush()
    session.add(
        Message(
            conversation_id=conversation.id,
            telegram_message_id=1,
            sender=Sender.student.value,
            text="من در دوره پیشرفته‌ام و شماره‌ام ۰۹۱۲۳۴۵۶۷۸۹ است.",
            sent_at=NOON,
        )
    )
    await session.commit()

    payload = json.dumps(
        {
            "candidates": [
                {"category": "course", "content": "در دوره پیشرفته است.", "confidence": 0.9},
                {"category": "note", "content": "شماره‌اش ۰۹۱۲۳۴۵۶۷۸۹ است.", "confidence": 0.9},
            ]
        },
        ensure_ascii=False,
    )
    report = await memory_job.run(
        session, conversation.id, model_client=ScriptedClient(raw_text=payload)
    )
    await session.commit()

    assert report.stored == ["در دوره پیشرفته است."]
    assert len(report.rejected) == 1


async def test_extraction_survives_a_broken_model_response(
    session: AsyncSession, account: MentorAccount
) -> None:
    """نتوانستن در استخراج حافظه هرگز نباید کارگر را بشکند."""
    student = Student(display_name="دانشجو")
    session.add(student)
    await session.flush()
    conversation = Conversation(account_id=account.id, student_id=student.id, telegram_chat_id=1200)
    session.add(conversation)
    await session.flush()
    session.add(
        Message(
            conversation_id=conversation.id,
            telegram_message_id=1,
            sender=Sender.student.value,
            text="سلام",
            sent_at=NOON,
        )
    )
    await session.commit()

    report = await memory_job.run(
        session, conversation.id, model_client=ScriptedClient(raw_text="این JSON نیست")
    )
    assert report.stored == [] and report.rejected == []


async def test_memory_reaches_the_prompt(
    session: AsyncSession, account: MentorAccount, kb: None, embedder: HashingEmbedder
) -> None:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=1300,
        message_id=1,
        sender_user_id=1300,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text="دوره مقدماتی چیست؟",
        media_type=None,
        reply_to_message_id=None,
        sent_at=NOON,
        is_private=True,
        is_outgoing=False,
    )
    result = await record_inbound(session, account, inbound, sender=Sender.student)
    await session.commit()
    conversation = await session.get_one(Conversation, result.conversation_id)

    await memory_store.apply_candidates(
        session,
        student_id=conversation.student_id,
        candidates=[_cand(category="course", content="در دوره پیشرفته است.")],
        source=MemorySource.extracted,
    )
    await session.commit()

    client = ScriptedClient(
        ModelAnswer(answer="شانزده جلسه.", confidence=0.95, needs_human=False, reason="ok")
    )
    await process_message(
        session,
        result.message_id or 0,
        model_client=client,
        embedder=embedder,
        channels={"mentor-a": FakeChannel()},
        gates={},
        notifier=None,
        sleep=False,
    )

    _, user = client.calls[0]
    assert "در دوره پیشرفته است." in user
    assert "زمینه‌اند، نه پاسخ" in user, "حافظه باید صریحاً زمینه معرفی شود، نه منبع"
