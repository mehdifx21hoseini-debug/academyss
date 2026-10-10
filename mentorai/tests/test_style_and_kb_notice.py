"""علامت‌های نگارشی پاسخ (v3.2) و حالت آزمایشی «این توی نالج‌بیس نیست»."""

from __future__ import annotations

import re
from collections.abc import Iterator
from pathlib import Path

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from tests import test_runtime as _rt
from tests.test_runtime import _confident, _incoming

from mentorai.ai import prompt as pr
from mentorai.ai.client import ScriptedClient
from mentorai.ai.runtime import KB_MISS_NOTICE_TEXT, handle_message
from mentorai.ai.schema import ModelAnswer
from mentorai.ai.style import humanize_punctuation
from mentorai.config import get_settings
from mentorai.db.models import AiRun, MentorAccount, Outcome

embedder = _rt.embedder
knowledge = _rt.knowledge

FORBIDDEN = re.compile(r"[«»“”\"؛…]|!(?=\s|$)|:(?=\s|$)")


def test_quotes_question_marks_exclamations_and_colons_are_removed() -> None:
    raw = "سلام «دوست من»! دکمه رو چک کنید: سبزه یا قرمزه؟ نمی‌دونم؛ ببینیم..."
    out = humanize_punctuation(raw)

    assert not FORBIDDEN.search(out), out
    assert "دکمه رو چک کنید،" in out and "سبزه یا قرمزه؟" in out


def test_commas_periods_and_message_breaks_are_kept() -> None:
    raw = "اول این، بعد اون.\n\nتکه‌ی دوم."

    assert humanize_punctuation(raw) == raw


def test_times_numbers_and_urls_are_not_damaged() -> None:
    raw = "ساعت 10:30 بیاید و https://example.com/a?b=1 رو ببینید"

    assert humanize_punctuation(raw) == raw


def test_an_occasional_question_mark_is_allowed() -> None:
    assert humanize_punctuation("درسته؟") == "درسته؟"

def test_a_text_of_only_punctuation_is_not_emptied() -> None:
    assert humanize_punctuation("!") == "!"


def test_every_example_answer_in_the_prompt_obeys_the_punctuation_rule() -> None:
    appendix = pr.SYSTEM_PROMPT_TEMPLATE.partition("----- نمونه‌ها و راهنمای لحن -----")[2]
    blocks = re.findall(r"پاسخ مناسب: (.*?)(?=\nدانشجو:|\n\nنمونه |\Z)", appendix, re.S)

    assert len(blocks) >= 10
    for block in blocks:
        assert not FORBIDDEN.search(block), block


async def test_the_live_answer_is_cleaned_before_it_is_sent_and_recorded(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: object
) -> None:
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")
    client = ScriptedClient(_confident("شانزده جلسه است! «کامل» می‌شه؛"))

    result = await handle_message(session, message, model_client=client, embedder=embedder)  # type: ignore[arg-type]
    await session.commit()

    assert result.answer_text is not None and not FORBIDDEN.search(result.answer_text)
    run = (await session.execute(select(AiRun))).scalar_one()
    assert run.response_text == result.answer_text


@pytest.fixture
def kb_notice(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.setenv("KB_MISS_NOTICE", "true")
    get_settings.cache_clear()
    yield
    monkeypatch.delenv("KB_MISS_NOTICE", raising=False)
    get_settings.cache_clear()


def _flagged() -> ModelAnswer:
    return ModelAnswer(
        answer="نمی‌دونم",
        confidence=0.9,
        needs_human=True,
        reason="در منابع نبود",
        used_chunk_ids=[],
    )


async def test_by_default_a_missing_answer_is_still_silent(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: object
) -> None:
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")

    client = ScriptedClient(_flagged())
    result = await handle_message(session, message, model_client=client, embedder=embedder)  # type: ignore[arg-type]

    assert result.outcome is Outcome.silence and result.answer_text is None


@pytest.mark.usefixtures("kb_notice")
async def test_notice_mode_says_it_is_not_in_the_knowledge_base_when_the_model_flags_it(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: object
) -> None:
    message = await _incoming(session, account, "دوره مقدماتی چند جلسه است؟")

    client = ScriptedClient(_flagged())
    result = await handle_message(session, message, model_client=client, embedder=embedder)  # type: ignore[arg-type]
    await session.commit()

    assert result.outcome is Outcome.answer and result.answer_text == KB_MISS_NOTICE_TEXT
    run = (await session.execute(select(AiRun))).scalar_one()
    assert run.reason == "kb_miss_notice:model_flagged" and run.outcome == "answer"


@pytest.mark.usefixtures("kb_notice")
async def test_notice_mode_never_overrides_the_hard_rules(
    session: AsyncSession, account: MentorAccount, knowledge: None, embedder: object
) -> None:
    message = await _incoming(session, account, "رسید واریزم رو فرستادم چی شد؟")
    client = ScriptedClient(_confident())

    result = await handle_message(session, message, model_client=client, embedder=embedder)  # type: ignore[arg-type]

    assert result.outcome is Outcome.silence and client.calls == []


def test_the_notice_text_has_no_forbidden_punctuation() -> None:
    assert not FORBIDDEN.search(KB_MISS_NOTICE_TEXT)
    assert Path(__file__).exists()
