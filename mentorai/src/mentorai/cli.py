"""خط فرمان مدیریت.

ورود به حساب عمداً یک کار دستی و آگاهانه است. ورود مکرر خودش برای تلگرام سیگنال منفی
است، پس این دستور نباید در راه‌اندازی خودکار قرار بگیرد.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import getpass
import sys
from pathlib import Path

import structlog
from sqlalchemy import select
from telethon import TelegramClient
from telethon.sessions import StringSession

from mentorai.config import get_settings
from mentorai.db.crypto import encrypt_session
from mentorai.db.models import (
    AuditLog,
    ExcludedChat,
    KnowledgeDocument,
    MentorAccount,
    PanelUser,
)
from mentorai.db.session import session_scope
from mentorai.knowledge.embeddings import EmbeddingProvider, HashingEmbedder
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


async def cmd_panel_user(args: argparse.Namespace) -> int:
    """ساخت کاربر پنل.

    رمز از ورودی تعاملی گرفته می‌شود و نه از آرگومان خط فرمان: آرگومان در تاریخچه‌ی
    پوسته و در فهرست فرایندهای در حال اجرا دیده می‌شود.
    """
    from mentorai.web.security import hash_password

    role = args.role
    async with session_scope() as session:
        account_id: int | None = None
        if role == "mentor":
            if not args.slug:
                print("نقش منتور به --slug نیاز دارد", file=sys.stderr)
                return 1
            account = (
                await session.execute(select(MentorAccount).where(MentorAccount.slug == args.slug))
            ).scalar_one_or_none()
            if account is None:
                print(f"حسابی با slug={args.slug} پیدا نشد", file=sys.stderr)
                return 1
            account_id = account.id
        elif args.slug:
            print("نقش مدیر حساب ندارد؛ --slug را بردارید", file=sys.stderr)
            return 1

        password = getpass.getpass("رمز: ")
        if password != getpass.getpass("تکرار رمز: "):
            print("دو رمز یکی نیستند", file=sys.stderr)
            return 1
        try:
            password_hash = hash_password(password)
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1

        session.add(
            PanelUser(
                username=args.username,
                display_name=args.display_name,
                password_hash=password_hash,
                role=role,
                account_id=account_id,
            )
        )
        session.add(AuditLog(actor="cli", action="create_panel_user", target=args.username))

    print(f"کاربر پنل {args.username} ساخته شد.")
    return 0


def _embedder() -> EmbeddingProvider | None:
    """بردارساز فعال، یا None اگر بازیابی فقط متنی باشد.

    بردارساز آزمایشی عمداً پیش‌فرض نیست. روی همین مجموعه‌ی ارزیابی اندازه گرفته شد و
    ترکیب رتبه با بردار بی‌معنی از جستجوی متنیِ تنها **بدتر** درآمد. دلیلش در خود RRF
    است: نامزدهای تصادفی مسیر برداری هم امتیاز می‌گیرند و سند درستِ مسیر متنی را پایین
    می‌برند. اعداد و تصمیم در ADR-019.
    """
    if not get_settings().embedding_model:
        return None
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
    """کل سیستم را اجرا کن: دریافت، پردازش صف، ربات کنترل، و ارسال.

    این دستور دروازه‌ی هر حساب را هم بالا می‌آورد، پس **در کنارش `run-gateway` را
    اجرا نکنید**. دو فرایند یعنی دو اتصال هم‌زمان با یک نشست: هم ترافیک اضافه و هم
    سیگنال برای تلگرام روی حسابی که کل ارزشش به محدود نشدنش است (ADR-020).

    `run-gateway` برای وقتی است که بخواهید فقط دریافت و ذخیره را داشته باشید، بدون
    اینکه هیچ پاسخی تولید شود.
    """
    from mentorai.ai.providers import build_client
    from mentorai.control.bot import ControlBot
    from mentorai.telegram.channel import TelethonChannel
    from mentorai.telegram.chat_draft import choose_notifier
    from mentorai.telegram.safety import AccountGate, TokenBucket
    from mentorai.worker import DraftNotifier, run_forever

    settings = get_settings()
    accounts = await _load_accounts()
    if not accounts:
        print("هیچ حساب فعال و واردشده‌ای وجود ندارد", file=sys.stderr)
        return 1

    # همان کلاینت هم برای پاسخ و هم برای خواندن تصویر. سرویس تازه‌ای در کار نیست.
    try:
        model_client = build_client()
    except ValueError as exc:
        # پیش از وصل شدن به تلگرام. پیکربندی ناقص هوش مصنوعی نباید حساب را وصل کند و
        # بعد سیستمی بسازد که جواب نمی‌دهد.
        print(f"پیکربندی هوش مصنوعی ناقص است: {exc}", file=sys.stderr)
        return 1
    gateways = [AccountGateway(a, vision_client=model_client) for a in accounts]
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
            tz=settings.tz,
            send_paused=account.send_paused,
        )
        for account in accounts
    }

    bot: ControlBot | None = None
    if settings.control_bot_token is not None:
        bot = ControlBot(channels=channels, gates=gates, model_client=model_client)
        await bot.start()
    elif settings.draft_delivery == "control_bot":
        print("هشدار: CONTROL_BOT_TOKEN تنظیم نشده؛ پیش‌نویس‌ها فقط ذخیره می‌شوند", file=sys.stderr)

    # محل تحویل پیش‌نویس (ADR-036). در حالت `chat` ربات کنترل برای پیش‌نویس‌ها به کار
    # نمی‌آید و هر پیش‌نویس در کادر نوشتن گفتگوی خودش گذاشته می‌شود.
    notifier: DraftNotifier | None = choose_notifier(
        settings.draft_delivery, bot, {g.slug: g.client for g in gateways}
    )

    tasks = [
        run_forever(
            worker_id="worker-1",
            model_client=model_client,
            embedder=_embedder(),
            channels=channels,
            gates=gates,
            notifier=notifier,
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


async def cmd_model_check(args: argparse.Namespace) -> int:
    """بررسی زنده‌ی ارائه‌دهنده‌ی هوش مصنوعی: هر مسیر مدل، یک بار، با ورودی ساختگی."""
    from pathlib import Path

    from mentorai.ai.providers import build_client
    from mentorai.model_check import render, run_checks

    try:
        client = build_client()
    except ValueError as exc:
        print(f"پیکربندی هوش مصنوعی ناقص است: {exc}", file=sys.stderr)
        return 1
    steps = await run_checks(client, image_path=Path(args.image) if args.image else None)
    print(render(client, steps))
    return 0 if all(s.ok for s in steps) else 1


async def cmd_compare_run(args: argparse.Namespace) -> int:
    """اجرای مقایسه‌ی کور: هر پرسش را به همه‌ی نامزدها بده و برگه‌ی داور را بساز."""
    from pathlib import Path

    from mentorai import model_compare as mc

    settings = get_settings()
    try:
        candidates = mc.parse_candidates(args.candidate)
        make_client = mc.default_client_factory(settings)
        async with session_scope() as session:
            if args.cases:
                cases = mc.load_cases(Path(args.cases), limit=args.limit, seed=args.seed)
            else:
                cases = await mc.sample_from_database(session, limit=args.from_db, seed=args.seed)
            if not cases:
                print("هیچ پرسشی پیدا نشد", file=sys.stderr)
                return 1
            print(f"{len(cases)} پرسش، {len(candidates)} نامزد:")
            for c in candidates:
                assert c.price is not None
                print(f"  {c.id}: {c.name} ({c.price.input_usd}/{c.price.output_usd} دلار)")
            run = await mc.run_comparison(
                session,
                cases,
                candidates,
                make_client=make_client,
                embedder=_embedder(),
                seed=args.seed,
                max_cost_usd=args.max_cost_usd,
                dry_run=args.dry_run,
                progress=lambda line: print(line, flush=True),
            )
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1

    excluded = ", ".join(f"{k}: {v}" for k, v in sorted(run.excluded.items())) or "هیچ"
    print(f"به نامزدها رسید: {len(run.cases)} پرسش | کنار گذاشته (مدل نمی‌دیدشان): {excluded}")
    if args.dry_run:
        print("--dry-run بود: هیچ فراخوانی مدلی انجام نشد و فایلی نوشته نشد.")
        return 0
    if not run.cases:
        print("هیچ پرسشی به مدل‌ها نرسید؛ چیزی نوشته نشد", file=sys.stderr)
        return 1
    paths = mc.write_run(run, Path(args.out))
    print(
        f"هزینه‌ی واقعی: {run.spent_usd:.3f} دلار" + (" (به سقف خورد)" if run.stopped_early else "")
    )
    print(f"برگه‌ی داور:   {paths['sheet']}")
    print(f"راهنمای داور:  {paths['guide']}")
    print(f"کلید (خصوصی):  {paths['key']}  ← تا پایان داوری به داور ندهید")
    print("⚠️ این فایل‌ها پیام واقعی دانشجو دارند. در مخزن نگذارید و جای امن نگه دارید.")
    return 0


async def cmd_compare_report(args: argparse.Namespace) -> int:
    """گزارش پس از داوری: کلید و برگه‌ی پرشده را یکی کن."""
    from pathlib import Path

    from mentorai import model_compare as mc

    key_path = Path(args.key)
    try:
        report = mc.make_report(key_path, Path(args.graded))
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1
    print(report)
    try:
        saved = mc.write_report(report, key_path.parent)
        print(f"\nذخیره شد: {saved}")
    except OSError:
        pass  # پوشه‌ی کلید فقط‌خواندنی است؛ گزارش همین‌جا چاپ شد
    return 0


async def cmd_understand_run(args: argparse.Namespace) -> int:
    """بازپخش مرحله‌ی فهم روی پیام‌های واقعی (RO-2، حالت سایه).

    فقط‌خواندنی است و به پاسخ‌دهی زنده کاری ندارد: به پایگاه داده نمی‌نویسد، چیزی نمی‌فرستد
    و فقط وقتی هزینه دارد که شما این دستور را بزنید (`--dry-run` هزینه ندارد).
    """
    from pathlib import Path

    from mentorai import model_compare as mc
    from mentorai import understanding_replay as ur
    from mentorai.ai.providers import build_client

    client = None
    if not args.dry_run:
        try:
            client = build_client()
        except ValueError as exc:
            print(f"پیکربندی هوش مصنوعی ناقص است: {exc}", file=sys.stderr)
            return 1

    try:
        async with session_scope() as session:
            if args.cases:
                cases = mc.load_cases(Path(args.cases), limit=args.limit, seed=args.seed)
            else:
                cases = await mc.sample_from_database(session, limit=args.from_db, seed=args.seed)
            if not cases:
                print("هیچ پرسشی پیدا نشد", file=sys.stderr)
                return 1
            print(f"{len(cases)} پرسش برای فهم")
            data = await ur.run_replay(
                session,
                cases,
                client,
                max_cost_usd=args.max_cost_usd,
                dry_run=args.dry_run,
                progress=lambda line: print(line, flush=True),
            )
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1

    if args.dry_run:
        print(ur.summarise(data))
        print("هیچ فایلی نوشته نشد.")
        return 0
    if not data.cases:
        print("هیچ پرسشی به مدل نرسید؛ چیزی نوشته نشد", file=sys.stderr)
        return 1

    paths = ur.write_replay(data, Path(args.out))
    print("خلاصه (بی‌متن):")
    print(ur.summarise(data))
    print(f"\nخلاصه:           {paths['summary']}")
    print(f"خروجی کامل (خصوصی): {paths['replay']}")
    print("⚠️ replay.json پیام واقعی دانشجو دارد. در مخزن نگذارید و جای امن نگه دارید.")
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

    panel_user = sub.add_parser("panel-user", help="ساخت کاربر پنل مدیریت")
    panel_user.add_argument("--username", required=True)
    panel_user.add_argument("--display-name", required=True)
    panel_user.add_argument("--role", choices=("mentor", "admin"), required=True)
    panel_user.add_argument("--slug", default=None, help="حساب منتور؛ فقط برای نقش منتور")
    panel_user.set_defaults(func=cmd_panel_user)

    check = sub.add_parser(
        "model-check", help="بررسی زنده‌ی مدل هوش مصنوعی (چند سنت هزینه، بدون داده‌ی دانشجو)"
    )
    check.add_argument("--image", default=None, help="تصویر دلخواه برای آزمون خواندن تصویر")
    check.set_defaults(func=cmd_model_check)

    import os as _os

    crun = sub.add_parser(
        "compare-run",
        help="مقایسه‌ی کور مدل‌ها: اجرا و ساخت برگه‌ی داور (هزینه‌ی واقعی دارد)",
    )
    crun.add_argument(
        "--candidate",
        action="append",
        required=True,
        help="provider:model[:effort][@ورودی/خروجی]؛ دست‌کم دو بار",
    )
    source = crun.add_mutually_exclusive_group(required=True)
    source.add_argument("--cases", help="CSV با ستون question")
    source.add_argument("--from-db", type=int, help="چند پیام واقعی دانشجو از پایگاه داده")
    crun.add_argument("--limit", type=int, default=60, help="سقف پرسش برای --cases")
    crun.add_argument("--seed", type=int, default=7)
    crun.add_argument("--max-cost-usd", type=float, default=5.0)
    crun.add_argument("--out", default="/out" if _os.path.isdir("/out") else "model-compare")
    crun.add_argument("--dry-run", action="store_true", help="فقط پرسش‌ها را بشمار؛ مدل صدا نزن")
    crun.set_defaults(func=cmd_compare_run)

    crep = sub.add_parser("compare-report", help="گزارش مقایسه‌ی کور از برگه‌ی پرشده")
    crep.add_argument("--key", required=True, help="key.json که compare-run ساخت")
    crep.add_argument("--graded", required=True, help="برگه‌ی پرشده (csv یا xlsx)")
    crep.set_defaults(func=cmd_compare_report)

    urun = sub.add_parser(
        "understand-run",
        help="بازپخش مرحله‌ی فهم روی پیام‌های واقعی (فقط‌خواندنی، بدون اثر روی پاسخ‌دهی؛ "
        "هزینه‌ی مدل دارد)",
    )
    usource = urun.add_mutually_exclusive_group(required=True)
    usource.add_argument("--cases", help="CSV با ستون question")
    usource.add_argument("--from-db", type=int, help="چند پیام واقعی دانشجو از پایگاه داده")
    urun.add_argument("--limit", type=int, default=60, help="سقف پرسش برای --cases")
    urun.add_argument("--seed", type=int, default=7)
    urun.add_argument("--max-cost-usd", type=float, default=1.0)
    urun.add_argument(
        "--out",
        default="/out/understanding-replay" if _os.path.isdir("/out") else "understanding-replay",
    )
    urun.add_argument("--dry-run", action="store_true", help="فقط پرسش‌ها را بشمار؛ مدل صدا نزن")
    urun.set_defaults(func=cmd_understand_run)

    run = sub.add_parser("run-gateway", help="اجرای دروازه برای همه حساب‌های فعال")
    run.set_defaults(func=cmd_run_gateway)

    worker = sub.add_parser("run-worker", help="اجرای کارگر و ربات کنترل")
    worker.set_defaults(func=cmd_run_worker)

    args = parser.parse_args()
    exit_code: int = asyncio.run(args.func(args))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
