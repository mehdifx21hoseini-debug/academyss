"""کار پس‌زمینه‌ی استخراج حافظه.

جدا از مسیر پاسخ اجرا می‌شود تا بین سؤال دانشجو و پاسخ تأخیری نیندازد.

هر پیام استخراج نمی‌شود. یک فراخوانی مدل به‌ازای هر پیام یعنی دوبرابر شدن هزینه در
ازای چیزی که به‌کندی تغییر می‌کند؛ واقعیت‌های پایدار دانشجو هر پیام عوض نمی‌شوند.
"""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai.client import ModelClient
from mentorai.db.models import Conversation, MemorySource, Message, Sender
from mentorai.memory.extract import MemoryExtractor
from mentorai.memory.store import MemoryReport, apply_candidates

JOB_KIND = "extract_memory"

# هر چند پیام دانشجو یک‌بار استخراج انجام شود.
EXTRACT_EVERY = 5
# چند نوبت آخر مکالمه به مدل داده می‌شود.
EXTRACT_WINDOW = 12


async def student_message_count(session: AsyncSession, conversation_id: int) -> int:
    return int(
        (
            await session.execute(
                select(func.count(Message.id)).where(
                    Message.conversation_id == conversation_id,
                    Message.sender == Sender.student.value,
                )
            )
        ).scalar_one()
    )


async def should_extract(
    session: AsyncSession, conversation_id: int, *, every: int = EXTRACT_EVERY
) -> bool:
    count = await student_message_count(session, conversation_id)
    return count > 0 and count % every == 0


async def recent_turns(
    session: AsyncSession, conversation_id: int, *, window: int = EXTRACT_WINDOW
) -> list[tuple[str, str]]:
    rows = (
        await session.execute(
            select(Message.sender, Message.text)
            .where(Message.conversation_id == conversation_id, Message.text.isnot(None))
            .order_by(Message.id.desc())
            .limit(window)
        )
    ).all()
    labels = {
        Sender.student.value: "دانشجو",
        Sender.assistant.value: "دستیار",
        Sender.mentor.value: "منتور",
    }
    return [(labels.get(sender, sender), body) for sender, body in reversed(rows) if body]


async def run(
    session: AsyncSession,
    conversation_id: int,
    *,
    model_client: ModelClient,
    window: int = EXTRACT_WINDOW,
) -> MemoryReport:
    """یافته‌ها را از مکالمه بگیر، از سیاست بگذران، و آنچه قبول شد را ذخیره کن."""
    conversation = await session.get_one(Conversation, conversation_id)
    turns = await recent_turns(session, conversation_id, window=window)
    candidates = await MemoryExtractor(model_client).extract(turns)
    return await apply_candidates(
        session,
        student_id=conversation.student_id,
        candidates=candidates,
        source=MemorySource.extracted,
        account_id=conversation.account_id,
    )
