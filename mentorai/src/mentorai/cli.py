"""خط فرمان مدیریت.

ورود به حساب عمداً یک کار دستی و آگاهانه است. ورود مکرر خودش برای تلگرام سیگنال منفی
است، پس این دستور نباید در راه‌اندازی خودکار قرار بگیرد.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import sys
from pathlib import Path

import structlog
from sqlalchemy import select
from telethon import TelegramClient
from telethon.sessions import StringSession

from mentorai.config import get_settings
from mentorai.db.crypto import encrypt_session
from mentorai.db.models import AuditLog, ExcludedChat, KnowledgeDocument, MentorAccount
from mentorai.db.session import session_scope
from mentorai.knowledge.embeddings import HashingEmbedder
from mentorai.knowledge.evaluate import EvalCase, evaluate
from mentorai.knowledge.ingest import ingest_csv
from mentorai.telegram.gateway import AccountGateway

log = structlog.get_logger(__name__)


async def cmd_add_account(args: argparse.Namespace) -> int:
    async with session_scope() as session:
        session.add(
            MentorAccount(
                slug=args.slug,
                mentor_name=args.mentor_name,
                phone=args.phone,
                device_model=args.device_model,
                system_version=args.system_version,
                app_version=args.app_version,
            )
        )
        session.add(AuditLog(actor="cli", action="add_account", target=args.slug))
    print(f"حساب {args.slug} ساخته شد. حالا دستور login را برای همین slug اجرا کنید.")
    return 0


async def cmd_login(args: argparse.Namespace) -> int:
    """ورود تعاملی و ذخیره‌ی نشست رمزنگاری‌شده."""
    settings = get_settings()
    async with session_scope() as session:
        account = (
            await session.execute(select(MentorAccount).where(MentorAccount.slug == args.slug))
        ).scalar_one_or_none()
        if account is None:
            print(f"حسابی با slug={args.slug} پیدا نشد", file=sys.stderr)
            return 1

        client = TelegramClient(
            StringSession(),
            settings.telegram_api_id,
            settings.telegram_api_hash.get_secret_value(),
            device_model=account.device_model,
            system_version=account.system_version,
            app_version=account.app_version,
        )
        await client.start(phone=account.phone)
        me = await client.get_me()

        account.session_encrypted = encrypt_session(client.session.save())
        account.telegram_user_id = int(me.id)
        session.add(AuditLog(actor="cli", action="login", target=account.slug))
        await client.disconnect()

    print(f"ورود حساب {args.slug} انجام شد. نشست رمزنگاری‌شده ذخیره شد.")
    return 0


async def cmd_exclude(args: argparse.Namespace) -> int:
    async with session_scope() as session:
        account = (
            await session.execute(select(MentorAccount).where(MentorAccount.slug == args.slug))
        ).scalar_one_or_none()
        if account is None:
            print(f"حسابی با slug={args.slug} پیدا نشد", file=sys.stderr)
            return 1
        session.add(
            ExcludedChat(account_id=account.id, telegram_peer_id=args.peer_id, reason=args.reason)
        )
        session.add(
            AuditLog(actor="cli", action="exclude_chat", target=f"{args.slug}:{args.peer_id}")
        )
    print(f"گفتگوی {args.peer_id} روی حساب {args.slug} استثنا شد.")
    return 0


async def cmd_pause(args: argparse.Namespace) -> int:
    """کلید قطع. یک حساب را از مدار خارج می‌کند بدون توقف بقیه."""
    async with session_scope() as session:
        account = (
            await session.execute(select(MentorAccount).where(MentorAccount.slug == args.slug))
        ).scalar_one_or_none()
        if account is None:
            print(f"حسابی با slug={args.slug} پیدا نشد", file=sys.stderr)
            return 1
        account.send_paused = not args.resume
        account.paused_reason = None if args.resume else args.reason
        session.add(
            AuditLog(
                actor="cli",
                action="resume_account" if args.resume else "pause_account",
                target=args.slug,
                detail=args.reason,
            )
        )
    print(f"حساب {args.slug} {'فعال' if args.resume else 'متوقف'} شد.")
    return 0


def _embedder() -> HashingEmbedder:
    """ارائه‌دهنده‌ی بردار.

    فعلاً فقط بردارساز آزمایشی موجود است. مدل واقعی هنوز انتخاب نشده و انتخابش باید با
    اندازه‌گیری روی همان مجموعه‌ی ارزیابی انجام شود، نه پیش از آن.
    """
    return HashingEmbedder()


async def cmd_kb_import(args: argparse.Namespace) -> int:
    path = Path(args.file)
    if not path.exists():
        print(f"فایل پیدا نشد: {path}", file=sys.stderr)
        return 1

    async with session_scope() as session:
        report = await ingest_csv(session, path, embedder=_embedder())
        session.add(AuditLog(actor="cli", action="kb_import", target=str(path)))

    print(f"ساخته شد: {report.created} | به‌روز شد: {report.updated}")
    if report.skipped:
        print(f"\nکنار گذاشته شد ({len(report.skipped)}):", file=sys.stderr)
        for line in report.skipped:
            print(f"  {line}", file=sys.stderr)
    return 0


async def cmd_kb_eval(args: argparse.Namespace) -> int:
    """کیفیت بازیابی را روی مجموعه‌ی ارزیابی اندازه بگیر.

    قالب فایل: دو ستون question و expected_question. ستون دوم باید دقیقاً عنوان سندی
    باشد که انتظار داریم پیدا شود.
    """
    path = Path(args.cases)
    if not path.exists():
        print(f"فایل پیدا نشد: {path}", file=sys.stderr)
        return 1

    async with session_scope() as session:
        titles = {
            title: doc_id
            for doc_id, title in (
                await session.execute(select(KnowledgeDocument.id, KnowledgeDocument.title))
            ).all()
        }

        cases: list[EvalCase] = []
        unknown: list[str] = []
        with path.open(encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                expected = (row.get("expected_question") or "").strip()
                question = (row.get("question") or "").strip()
                if not question:
                    continue
                if expected not in titles:
                    unknown.append(expected)
                    continue
                cases.append(
                    EvalCase(question=question, expected_document_ids=frozenset({titles[expected]}))
                )

        if unknown:
            print(f"این عنوان‌ها در پایگاه دانش نیستند: {unknown}", file=sys.stderr)
        if not cases:
            print("هیچ مورد قابل ارزیابی‌ای پیدا نشد", file=sys.stderr)
            return 1

        metrics = await evaluate(session, cases, embedder=_embedder(), k=args.k)

    print(metrics.summary())
    if metrics.misses:
        print("\nپرسش‌هایی که سند درست را پیدا نکردند:")
        for miss in metrics.misses:
            print(f"  {miss}")
    return 0


async def _load_accounts() -> list[MentorAccount]:
    async with session_scope() as session:
        return list(
            (
                await session.execute(
                    select(MentorAccount).where(
                        MentorAccount.enabled.is_(True),
                        MentorAccount.session_encrypted.isnot(None),
                    )
                )
            ).scalars()
        )


async def cmd_run_worker(_: argparse.Namespace) -> int:
    """کارگر و ربات کنترل را با هم اجرا کن.

    کارگر برای ارسال به حساب هر منتور وصل می‌شود، ولی هیچ گوش‌دهنده‌ای ثبت نمی‌کند؛
    دریافت کار دروازه است.
    """
    from mentorai.ai.client import AnthropicClient
    from mentorai.control.bot import ControlBot
    from mentorai.knowledge.embeddings import HashingEmbedder
    from mentorai.telegram.channel import TelethonChannel
    from mentorai.telegram.safety import AccountGate, TokenBucket
    from mentorai.worker import run_forever

    settings = get_settings()
    accounts = await _load_accounts()
    if not accounts:
        print("هیچ حساب فعال و واردشده‌ای وجود ندارد", file=sys.stderr)
        return 1

    gateways = [AccountGateway(a) for a in accounts]
    for gateway in gateways:
        await gateway.start()

    channels = {g.slug: TelethonChannel(g.client) for g in gateways}
    gates = {
        account.slug: AccountGate(
            slug=account.slug,
            bucket=TokenBucket(
                rate_per_minute=settings.send_rate_per_minute, burst=settings.send_burst
            ),
            quiet_start=settings.quiet_hours_start,
            quiet_end=settings.quiet_hours_end,
            send_paused=account.send_paused,
        )
        for account in accounts
    }

    bot: ControlBot | None = None
    if settings.control_bot_token is not None:
        bot = ControlBot(channels=channels, gates=gates)
        await bot.start()
    else:
        print("هشدار: CONTROL_BOT_TOKEN تنظیم نشده؛ پیش‌نویس‌ها فقط ذخیره می‌شوند", file=sys.stderr)

    tasks = [
        run_forever(
            worker_id="worker-1",
            model_client=AnthropicClient(),
            embedder=HashingEmbedder(),
            channels=channels,
            gates=gates,
            notifier=bot,
        )
    ]
    if bot is not None:
        tasks.append(bot.run_until_disconnected())

    try:
        await asyncio.gather(*tasks)
    finally:
        for gateway in gateways:
            await gateway.stop()
    return 0


async def cmd_run_gateway(_: argparse.Namespace) -> int:
    async with session_scope() as session:
        accounts = list(
            (
                await session.execute(
                    select(MentorAccount).where(
                        MentorAccount.enabled.is_(True),
                        MentorAccount.session_encrypted.isnot(None),
                    )
                )
            ).scalars()
        )

    if not accounts:
        print("هیچ حساب فعال و واردشده‌ای وجود ندارد", file=sys.stderr)
        return 1

    gateways = [AccountGateway(a) for a in accounts]
    for gateway in gateways:
        await gateway.start()

    try:
        await asyncio.gather(*(g.run_until_disconnected() for g in gateways))
    finally:
        for gateway in gateways:
            await gateway.stop()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="mentorai")
    sub = parser.add_subparsers(dest="command", required=True)

    add = sub.add_parser("add-account", help="ثبت یک حساب جدید")
    add.add_argument("--slug", required=True)
    add.add_argument("--mentor-name", required=True)
    add.add_argument("--phone", required=True)
    add.add_argument("--device-model", default="Desktop")
    add.add_argument("--system-version", default="Linux")
    add.add_argument("--app-version", default="1.0")
    add.set_defaults(func=cmd_add_account)

    login = sub.add_parser("login", help="ورود تعاملی و ذخیره نشست")
    login.add_argument("--slug", required=True)
    login.set_defaults(func=cmd_login)

    exclude = sub.add_parser("exclude-chat", help="استثنا کردن یک گفتگو")
    exclude.add_argument("--slug", required=True)
    exclude.add_argument("--peer-id", type=int, required=True)
    exclude.add_argument("--reason", default=None)
    exclude.set_defaults(func=cmd_exclude)

    pause = sub.add_parser("pause", help="کلید قطع یک حساب")
    pause.add_argument("--slug", required=True)
    pause.add_argument("--reason", default=None)
    pause.add_argument("--resume", action="store_true")
    pause.set_defaults(func=cmd_pause)

    kb_import = sub.add_parser("kb-import", help="وارد کردن پایگاه دانش از فایل CSV")
    kb_import.add_argument("--file", required=True)
    kb_import.set_defaults(func=cmd_kb_import)

    kb_eval = sub.add_parser("kb-eval", help="اندازه‌گیری کیفیت بازیابی")
    kb_eval.add_argument("--cases", required=True)
    kb_eval.add_argument("--k", type=int, default=5)
    kb_eval.set_defaults(func=cmd_kb_eval)

    run = sub.add_parser("run-gateway", help="اجرای دروازه برای همه حساب‌های فعال")
    run.set_defaults(func=cmd_run_gateway)

    worker = sub.add_parser("run-worker", help="اجرای کارگر و ربات کنترل")
    worker.set_defaults(func=cmd_run_worker)

    args = parser.parse_args()
    exit_code: int = asyncio.run(args.func(args))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
