"""خط فرمان مدیریت.

ورود به حساب عمداً یک کار دستی و آگاهانه است. ورود مکرر خودش برای تلگرام سیگنال منفی
است، پس این دستور نباید در راه‌اندازی خودکار قرار بگیرد.
"""

from __future__ import annotations

import argparse
import asyncio
import sys

import structlog
from sqlalchemy import select
from telethon import TelegramClient
from telethon.sessions import StringSession

from mentorai.config import get_settings
from mentorai.db.crypto import encrypt_session
from mentorai.db.models import AuditLog, ExcludedChat, MentorAccount
from mentorai.db.session import session_scope
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

    run = sub.add_parser("run-gateway", help="اجرای دروازه برای همه حساب‌های فعال")
    run.set_defaults(func=cmd_run_gateway)

    args = parser.parse_args()
    exit_code: int = asyncio.run(args.func(args))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
