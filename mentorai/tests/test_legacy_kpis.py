"""اعداد KPI برای داده‌ی legacy، قفل‌شده (RO-1).

شکستی که این فایل می‌بندد: افزودن `silence_class` به `ai_runs` نباید هیچ عددی را برای
اجراهای قدیمی عوض کند. اجراهای قدیمی `silence_class` تهی دارند و باید **دقیقاً** مثل
پیش از RO-1 شمرده شوند: پنل (`queries.kpis`) و سلامت (`health.snapshot().facts`).

این تست با اعداد ثابت و دستی نوشته شده، نه با مقایسه‌ی دو تابع؛ پیش از هر تغییر روی کد
اجرا شد و با کد baseline سبز بود. اگر روزی این اعداد عوض شوند، یعنی تعریف یکی از
شاخص‌ها عوض شده و باید آگاهانه باشد.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import health
from mentorai.access import Principal, Role
from mentorai.db.models import AiRun, MentorAccount, Message, Outcome, Sender
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound
from mentorai.web import queries

NOON = datetime(2026, 9, 2, 12, 0, tzinfo=UTC)

# پنج پاسخ و ده سکوت، با همه‌ی دلیل‌های legacy. (دلیل، تعداد)
LEGACY_SILENCES: list[tuple[str, int]] = [
    ("rule_money", 2),
    ("rule_identity_question", 1),
    ("no_sources", 1),
    ("low_confidence", 2),
    ("model_flagged", 1),
    ("model_error", 1),
    ("unsupported_media", 1),
    ("ungrounded_money", 1),
]
ANSWERS = 5


async def _message(session: AsyncSession, account: MentorAccount, message_id: int) -> Message:
    inbound = build_inbound(
        account_slug=account.slug,
        chat_id=910,
        message_id=message_id,
        sender_user_id=910,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text=f"پیام {message_id}",
        media_type=None,
        reply_to_message_id=None,
        sent_at=NOON,
        is_private=True,
        is_outgoing=False,
    )
    result = await record_inbound(session, account, inbound, sender=Sender.student)
    await session.commit()
    assert result.message_id is not None
    return await session.get_one(Message, result.message_id)


async def _seed_legacy_runs(session: AsyncSession, account: MentorAccount) -> None:
    """اجراهای قدیمی: ستون `silence_class` را نمی‌شناسند (تهی می‌مانند)."""
    next_id = 1
    plan = [(Outcome.answer, "answered")] * ANSWERS
    for reason, count in LEGACY_SILENCES:
        plan += [(Outcome.silence, reason)] * count

    for outcome, reason in plan:
        message = await _message(session, account, next_id)
        next_id += 1
        session.add(
            AiRun(
                conversation_id=message.conversation_id,
                message_id=message.id,
                outcome=outcome.value,
                reason=reason,
                prompt_version="v2",
            )
        )
    await session.commit()


async def test_panel_kpis_for_legacy_runs_are_frozen(
    session: AsyncSession, account: MentorAccount
) -> None:
    await _seed_legacy_runs(session, account)

    kpis = await queries.kpis(session, Principal(role=Role.admin, label="test"))

    assert kpis.runs_7d == 15
    assert kpis.answered_7d == 5
    assert kpis.silent_7d == 10
    assert kpis.answer_rate == pytest.approx(5 / 15)


async def test_health_rates_for_legacy_runs_are_frozen(
    session: AsyncSession, account: MentorAccount
) -> None:
    await _seed_legacy_runs(session, account)

    facts = (await health.snapshot(session)).facts

    assert facts["ai_runs"] == 15
    assert facts["answer_rate"] == 0.333
    assert facts["silence_rate"] == 0.667
