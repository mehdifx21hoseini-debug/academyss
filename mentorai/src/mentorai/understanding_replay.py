"""بازپخش مرحله‌ی فهم روی پیام‌های واقعی (`mentorai understand-run`، RO-2، ADR-046).

این **حالت سایه‌ی RO-2** است: مرحله‌ی فهم (`ai/understanding.py`) را روی پیام‌های دانشجوهای
**ذخیره‌شده** اجرا می‌کند و می‌سنجد، بی‌آنکه به خط زنده‌ی پاسخ‌دهی وصل باشد. چرا بازپخش و نه
اتصال به کارگر: کارگر دست‌نخورده می‌ماند، هزینه فقط وقتی می‌شود که مالک دستور را بزند، و
هیچ تأخیر یا ردپایی روی پاسخ دانشجو نمی‌افتد. اتصال زنده (با جدول و سقف هزینه‌ی خودش) بخش
RO-5 است و تأیید جدا می‌خواهد.

**هیچ اثر جانبی:** این ماژول به پایگاه داده **نمی‌نویسد**، تلگرام و تحویل و پیش‌نویس و ارجاع
را import نمی‌کند (آزمونی با AST این را می‌سنجد)، و فقط دو فایل در پوشه‌ی خروجی خودش می‌نویسد.

- `replay.json`: برای مالک، با متن (پوشانده‌شده) و خروجی کامل. **پیام واقعی دانشجو دارد**؛
  مجوز ۶۰۰ می‌گیرد و هرگز نباید به مخزن برود (`understanding-replay/` در `.gitignore` است).
- `summary.txt`: فقط شمارش و درصد، **بدون هیچ متنی**. این را می‌شود به اشتراک گذاشت.

ورودی مدل از این سه می‌آید و **همان چیزی** است که مسیر پاسخ فعلی هم می‌بیند: متن پیام،
چند پیام آخر همان گفتگو (`runtime._recent_history`، ۴ پیام) و حافظه‌ی فعال دانشجو. شماره،
ایمیل و نام کاربری پیش از ارسال پوشانده می‌شود (`mask_personal`). پیامی که قاعده‌ی قطعی می‌گیرد
(پول، شکایت، حساب، هویت، درخواست منتور) **به مدل داده نمی‌شود**، مثل مسیر زنده. ویس در این
نسخه نیست (نمونه‌گیر فقط پیام بی‌فایل می‌خواند)؛ رفتار ویس در مسیر زنده بی‌تغییر است.

محدودیت‌هایی که باید با نتیجه گفته شوند:

- حافظه‌ی دانشجو **وضعیت امروز** است، نه وضعیت لحظه‌ی آن پیام.
- این ابزار «درست فهمیدن» را قضاوت نمی‌کند؛ توزیع خروجی را نشان می‌دهد (چند بخش، چه حوزه‌ای،
  چند بار کد با مدل مخالف بود). درستی را باید آدم روی نمونه ببیند.
"""

from __future__ import annotations

import json
import re
import statistics
from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.ai import budget
from mentorai.ai.client import ModelClient
from mentorai.ai.decision import deterministic_trigger
from mentorai.ai.runtime import _recent_history
from mentorai.ai.understanding import (
    UNDERSTANDING_PROMPT_VERSION,
    MethodIntent,
    UnderstandingResult,
    understand,
)
from mentorai.db.models import Conversation, Message
from mentorai.memory import store as memory_store
from mentorai.model_compare import (
    Case,
    CompareError,
    _private_dir,
    _write_private,
    mask_personal,
)

REPLAY_NAME = "replay.json"
SUMMARY_NAME = "summary.txt"
REPLAY_VERSION = 1


class ReplayError(CompareError):
    """ورودی یا پیکربندی نادرست یا هزینه‌ی بیش از سقف؛ پیامش برای مالک و بی‌خطر چاپ است."""


class CostLimitExceeded(ReplayError):
    def __init__(self, projected: float, limit: float) -> None:
        super().__init__(
            f"هزینه‌ی برآوردشده {projected:.2f} دلار است و از سقف {limit:.2f} می‌گذرد. "
            "پرسش‌ها را کمتر کنید (--limit یا --from-db) یا سقف را آگاهانه بالا ببرید "
            "(--max-cost-usd)."
        )
        self.projected = projected


@dataclass
class CaseOutcome:
    id: str
    question: str  # پوشانده‌شده
    history_turns: int
    had_memories: bool
    result: UnderstandingResult | None  # None یعنی --dry-run
    cost_usd: float = 0.0


@dataclass
class ReplayData:
    model: str
    prompt_version: str = UNDERSTANDING_PROMPT_VERSION
    cases: list[CaseOutcome] = field(default_factory=list)
    excluded: Counter[str] = field(default_factory=Counter)
    spent_usd: float = 0.0
    stopped_early: bool = False
    dry_run: bool = False
    created: str = ""


_MESSAGE_CASE = re.compile(r"m(\d+)")


def _message_id(case_id: str) -> int | None:
    """شناسه‌ی پیام از شناسه‌ی پرسش (`m123`، ساخته‌ی `sample_from_database`)؛ CSV شناسه‌ی دیگری دارد."""
    match = _MESSAGE_CASE.fullmatch(case_id)
    return int(match[1]) if match else None


async def _context(session: AsyncSession, case_id: str) -> tuple[list[tuple[str, str]], str]:
    """(پیام‌های قبلی، حافظه) به همان شکل مسیر پاسخ، پوشانده‌شده. بدون پیام ذخیره‌شده: خالی."""
    message_id = _message_id(case_id)
    message = await session.get(Message, message_id) if message_id is not None else None
    if message is None:
        return [], ""
    history = [
        (role, mask_personal(text))
        for role, text in await _recent_history(session, message.conversation_id, message.id)
    ]
    conversation = await session.get_one(Conversation, message.conversation_id)
    memories = memory_store.render(await memory_store.load_active(session, conversation.student_id))
    return history, mask_personal(memories)


def _cost_usd(result: UnderstandingResult) -> float:
    if result.call is None:
        return 0.0
    micros, _ = budget.cost_micros(
        result.call.model,
        input_tokens=result.call.input_tokens,
        output_tokens=result.call.output_tokens,
        cache_read_tokens=result.call.cache_read_tokens,
    )
    return micros / budget.MICROS_PER_USD


async def run_replay(
    session: AsyncSession,
    cases: Sequence[Case],
    client: ModelClient | None,
    *,
    max_cost_usd: float = 1.0,
    dry_run: bool = False,
    progress: Callable[[str], None] | None = None,
) -> ReplayData:
    """هر پرسش را بفهم و نتیجه را جمع کن. به پایگاه داده فقط می‌خواند.

    `client` فقط در `--dry-run` می‌تواند `None` باشد (شمارش خشک کلید نمی‌خواهد).
    """
    if client is None and not dry_run:
        raise ReplayError("بدون --dry-run کلاینت مدل لازم است")
    data = ReplayData(
        model=client.model if client is not None else "—",
        dry_run=dry_run,
        created=datetime.now(UTC).isoformat(timespec="seconds"),
    )
    for position, case in enumerate(cases, start=1):
        question = mask_personal(case.question)

        # پیامی که مسیر زنده هرگز به مدل نمی‌دهد، اینجا هم نمی‌رود (بدون پیام تازه‌ی بیرونی).
        trigger = deterministic_trigger(question)
        if trigger is not None:
            data.excluded[f"rule_{trigger.value}"] += 1
            continue

        history, memories = await _context(session, case.id)
        outcome = CaseOutcome(
            id=case.id,
            question=question,
            history_turns=len(history),
            had_memories=bool(memories),
            result=None,
        )
        data.cases.append(outcome)
        if dry_run or client is None:
            continue

        outcome.result = await understand(
            client, question=question, history=history, memories=memories
        )
        outcome.cost_usd = _cost_usd(outcome.result)
        data.spent_usd += outcome.cost_usd

        # پس از نخستین پرسش، هزینه‌ی کل برآورد می‌شود: خطا در برآورد باید با چند سنت معلوم
        # شود، نه با خالی شدن حساب.
        if len(data.cases) == 1:
            projected = data.spent_usd * len(cases)
            if projected > max_cost_usd:
                raise CostLimitExceeded(projected, max_cost_usd)
        if data.spent_usd > max_cost_usd:
            data.stopped_early = True
            break
        if progress is not None and (position % 10 == 0 or position == len(cases)):
            progress(f"{position}/{len(cases)} — خرج تا اینجا {data.spent_usd:.3f} دلار")
    return data


# ---------------------------------------------------------------------------
# خلاصه (بدون هیچ متن دانشجو)
# ---------------------------------------------------------------------------


def _percentile(values: Sequence[float], q: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, round(q * (len(ordered) - 1)))]


def _share(count: int, total: int) -> str:
    return f"{count} ({100 * count / total:.0f}٪)" if total else "—"


def _counts(counter: Counter[str], total: int) -> list[str]:
    return [f"  {name}: {_share(n, total)}" for name, n in counter.most_common()]


def summarise(data: ReplayData) -> str:
    """گزارش شمارشی به فارسی ساده. **هیچ متن پیام، پرسش یا عبارتی در آن نیست.**"""
    lines: list[str] = []
    add = lines.append
    add("خلاصه‌ی بازپخش مرحله‌ی فهم")
    add("=" * 26)
    add(f"تاریخ: {data.created} | مدل: {data.model} | نسخه‌ی دستور فهم: {data.prompt_version}")
    excluded = ", ".join(f"{k}: {v}" for k, v in sorted(data.excluded.items())) or "هیچ"
    add(f"پرسش‌های قابل‌ارسال به مدل: {len(data.cases)} | کنار گذاشته (قاعده‌ی قطعی): {excluded}")

    if data.dry_run:
        add("--dry-run بود: هیچ فراخوانی مدلی انجام نشد.")
        return "\n".join(lines)

    results = [c.result for c in data.cases if c.result is not None]
    ok = [r for r in results if r.understanding is not None]
    errors = Counter(r.error or "نامشخص" for r in results if r.understanding is None)
    add(f"فهمیده شد: {_share(len(ok), len(results))} | خطا: {sum(errors.values())}")
    if errors:
        add("خطاها:")
        lines.extend(_counts(errors, len(results)))
    if data.stopped_early:
        add("⚠️ اجرا به سقف هزینه خورد و زودتر تمام شد؛ فقط پرسش‌های اجراشده‌اند.")

    if ok:
        understood = [r.understanding for r in ok if r.understanding is not None]
        parts = [p for u in understood for p in u.parts]
        part_total = len(parts)

        add("")
        add("تعداد بخش در هر پیام:")
        sizes = Counter(str(len(u.parts)) for u in understood)
        lines.extend(_counts(sizes, len(understood)))
        multi = sum(1 for u in understood if u.is_multi_intent)
        add(f"پیام چندبخشی: {_share(multi, len(understood))}")

        add("")
        add(f"حوزه (روی {part_total} بخش):")
        lines.extend(_counts(Counter(p.scope.value for p in parts), part_total))
        add("نوع واقعیت:")
        lines.extend(_counts(Counter(p.fact_class.value for p in parts), part_total))
        add("موضوع:")
        lines.extend(_counts(Counter(p.topic.value for p in parts), part_total))
        add("ابهام (روی پیام):")
        lines.extend(_counts(Counter(u.ambiguity.value for u in understood), len(understood)))

        intents = Counter(
            p.external_method.intent.value
            for p in parts
            if p.external_method.intent is not MethodIntent.none
        )
        if intents:
            add("روش بیرونی (فقط طبقه‌بندی):")
            lines.extend(_counts(intents, part_total))

        # چند بار کد با مدل مخالف بود: همان شمارشی که نشان می‌دهد دستور فهم کجا ضعیف است.
        codes = Counter(a.split(":", 1)[0] for r in ok for a in r.adjustments)
        add("")
        add(f"اصلاح‌های کدی (کد با مدل مخالف بود)، روی {len(ok)} پیام:")
        lines.extend(_counts(codes, len(ok)) or ["  هیچ"])

        confidences = [u.scope_confidence for u in understood]
        add("")
        add(
            f"اطمینان حوزه: میانگین {statistics.mean(confidences):.2f}، "
            f"پایین‌ترین {min(confidences):.2f}"
        )

    latencies = [r.call.latency_ms / 1000 for r in results if r.call is not None]
    tokens_in = sum(r.call.input_tokens for r in results if r.call is not None)
    tokens_out = sum(r.call.output_tokens for r in results if r.call is not None)
    add("")
    add(
        f"هزینه‌ی کل: {data.spent_usd:.3f} دلار | توکن ورودی {tokens_in}، خروجی {tokens_out} | "
        f"زمان میانه {_percentile(latencies, 0.5):.1f} ثانیه، ٪۹۰ {_percentile(latencies, 0.9):.1f}"
    )
    add("")
    add("یادآوری: این شمارش درستیِ فهمیدن را نمی‌سنجد؛ فقط توزیع خروجی را نشان می‌دهد.")
    add("درستی را باید آدم روی نمونه ببیند (replay.json، فقط برای مالک).")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# نوشتن
# ---------------------------------------------------------------------------


def _case_document(case: CaseOutcome) -> dict[str, Any]:
    result = case.result
    doc: dict[str, Any] = {
        "id": case.id,
        "question": case.question,
        "history_turns": case.history_turns,
        "had_memories": case.had_memories,
        "cost_usd": round(case.cost_usd, 6),
    }
    if result is not None:
        doc["error"] = result.error
        doc["detail"] = result.detail
        doc["adjustments"] = list(result.adjustments)
        doc["understanding"] = (
            result.understanding.model_dump(mode="json") if result.understanding else None
        )
        doc["raw"] = result.call.text if result.call else None
    return doc


def replay_document(data: ReplayData) -> dict[str, Any]:
    return {
        "version": REPLAY_VERSION,
        "created": data.created,
        "model": data.model,
        "prompt_version": data.prompt_version,
        "spent_usd": round(data.spent_usd, 6),
        "stopped_early": data.stopped_early,
        "excluded": dict(data.excluded),
        "cases": [_case_document(c) for c in data.cases],
    }


def write_replay(data: ReplayData, out_dir: Path) -> dict[str, Path]:
    """دو فایل خصوصی بنویس: `replay.json` (با متن) و `summary.txt` (بی‌متن)."""
    _private_dir(out_dir)
    paths = {"replay": out_dir / REPLAY_NAME, "summary": out_dir / SUMMARY_NAME}
    _write_private(paths["replay"], json.dumps(replay_document(data), ensure_ascii=False, indent=2))
    _write_private(paths["summary"], summarise(data) + "\n")
    return paths


__all__ = [
    "REPLAY_NAME",
    "SUMMARY_NAME",
    "CaseOutcome",
    "CostLimitExceeded",
    "ReplayData",
    "ReplayError",
    "run_replay",
    "summarise",
    "write_replay",
]
