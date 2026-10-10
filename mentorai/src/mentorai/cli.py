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
from sqlalchemy import select, text
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


async def cmd_retrieval_shadow_run(args: argparse.Namespace) -> int:
    """سایه‌ی بازیابی: فهم v2 را به بازیابی فعلی وصل کن و فقط گزارش بده (RO-3).

    فقط‌خواندنی است و به پاسخ‌دهی زنده کاری ندارد: به پایگاه داده نمی‌نویسد، چیزی نمی‌فرستد، و
    بازیابی فعلی را بی‌تغییر صدا می‌زند. هزینه‌اش فقط فراخوانی مدلِ فهم است (`--dry-run` ندارد).
    """
    from pathlib import Path

    from mentorai import model_compare as mc
    from mentorai.ai import retrieval_shadow as rs
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
            print(f"{len(cases)} پرسش برای فهم و بازیابی")
            data = await rs.run_retrieval_shadow(
                session,
                cases,
                client,
                embedder=_embedder(),
                max_cost_usd=args.max_cost_usd,
                dry_run=args.dry_run,
                progress=lambda line: print(line, flush=True),
            )
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1

    if args.dry_run:
        print(rs.summarise(data))
        print("هیچ فایلی نوشته نشد.")
        return 0
    if not data.messages:
        print("هیچ پرسشی به مدل نرسید؛ چیزی نوشته نشد", file=sys.stderr)
        return 1

    paths = rs.write_shadow(data, Path(args.out))
    print("خلاصه (بی‌متن):")
    print(rs.summarise(data))
    print(f"\nخلاصه:           {paths['summary']}")
    print(f"خروجی کامل (خصوصی): {paths['json']}")
    print("⚠️ retrieval_shadow.json پیام واقعی دانشجو دارد. در مخزن نگذارید و جای امن نگه دارید.")
    return 0


async def cmd_decision_shadow_run(args: argparse.Namespace) -> int:
    """سایه‌ی شواهد و تصمیم: از خروجی RO-3 برای هر بخش تصمیم بگیر؛ پاسخ نساز (RO-4).

    فقط یک فایل را می‌خواند (`retrieval_shadow.json`): مدل صدا زده نمی‌شود، به پایگاه داده و
    بازیابی و تلگرام کاری ندارد و هیچ هزینه‌ای ندارد.
    """
    from pathlib import Path

    from mentorai.ai import decision_shadow as ds

    try:
        data = ds.load_and_decide(Path(args.from_shadow))
    except ds.DecisionError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1

    paths = ds.write_decision(data, Path(args.out))
    print("خلاصه (بی‌متن):")
    print(ds.summarise(data))
    print(f"\nخلاصه:           {paths['summary']}")
    print(f"خروجی کامل (خصوصی): {paths['json']}")
    print("⚠️ decision_shadow.json متن پوشانده‌ی پیام دانشجو دارد. در مخزن نگذارید.")
    return 0


async def cmd_ro5a_shadow_run(args: argparse.Namespace) -> int:
    """ارزیابی سایه‌ی واقعی (RO-5A): نمونه ← فهم ← بازیابی ← تصمیم ← گزارش. فقط‌خواندنی.

    به پایگاه داده نمی‌نویسد و چیزی نمی‌فرستد. فراخوانی مدل فقط برای فهم است و سقفش
    `--max-cost-usd` (اجباری) است. بدون کلید/پیکربندی مدل، اجرا متوقف نمی‌شود و وضعیت
    `model_unavailable` ثبت می‌شود.
    """
    from pathlib import Path

    from mentorai import model_compare as mc
    from mentorai.ai import ro5a_shadow as ro5a
    from mentorai.ai.providers import build_client

    async with session_scope() as session:
        cases = await mc.sample_from_database(session, limit=args.from_db, seed=args.seed)
        if not cases:
            print("هیچ پیامی برای نمونه پیدا نشد", file=sys.stderr)
            return 1
        print(f"{len(cases)} پیام انتخاب شد (درخواستی: {args.from_db}، seed={args.seed})")
        print(f"سقف هزینه: {args.max_cost_usd:.2f} دلار")
        print("هزینه‌ی هر پیام فرض نمی‌شود؛ پس از نخستین فراخوانی اندازه‌گیری می‌شود.")
        if args.dry_run:
            print("--dry-run بود: مدل صدا زده نشد و فایلی نوشته نشد.")
            return 0

        client = None
        try:
            client = build_client()
        except Exception as exc:  # noqa: BLE001 - هر کمبود پیکربندی یعنی مدل در دسترس نیست
            print(
                f"⚠️ مدل در دسترس نیست ({type(exc).__name__}). ارزیابی مدل انجام نمی‌شود "
                "و فقط نمونه با وضعیت model_unavailable ثبت می‌شود.",
                file=sys.stderr,
            )

        try:
            evaluation = await ro5a.run_ro5a(
                session,
                cases,
                client,
                embedder=_embedder(),
                seed=args.seed,
                requested=args.from_db,
                max_cost_usd=args.max_cost_usd,
                progress=lambda line: print(line, flush=True),
            )
        except mc.CompareError as exc:
            print(f"انجام نشد: {exc}", file=sys.stderr)
            return 1

    paths = ro5a.write_outputs(evaluation, Path(args.out))
    print(ro5a.render_summary(evaluation))
    print(f"\nJSON (خصوصی):     {paths['json']}")
    print(f"خلاصه (بی‌متن):   {paths['summary']}")
    print(f"CSV بازبینی:      {paths['csv']}")
    print("⚠️ JSON و CSV پیام (پوشانده‌شده)ی دانشجو دارند. در مخزن نگذارید.")
    return 0


async def cmd_ro5b_evidence_shadow_run(args: argparse.Namespace) -> int:
    """سایه‌ی ربط شواهد (RO-5B): خروجی موجود بازیابی ← ارزیابی ربط هر قطعه ← گزارش.

    به پایگاه داده فقط می‌خواند (متن کامل قطعه‌ها، تراکنش `READ ONLY`) و چیزی نمی‌فرستد و
    تصمیمی را تغییر نمی‌دهد. مدل فقط ارزیاب است و سقف هزینه‌اش `--max-cost-usd` (اجباری) است.
    """
    from pathlib import Path

    from mentorai import model_compare as mc
    from mentorai.ai import ro5b_evidence_shadow as ro5b
    from mentorai.ai.providers import build_client

    path = Path(args.from_shadow)
    try:
        loaded = ro5b.load_input(path)
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1
    plan = ro5b.plan_run(loaded, max_parts=args.max_parts, seed=args.seed)
    print(
        f"{plan.parts_in_file} بخش در فایل ({plan.messages} پیام) | قابل‌ارزیابی: {plan.eligible} | "
        f"انتخاب‌شده: {plan.selected}"
    )
    print(f"قطعه‌ی برنامه‌ریزی‌شده (حداکثر {ro5b.TOP_K} برای هر بخش): {plan.chunks}")
    print(f"سقف هزینه: {args.max_cost_usd:.2f} دلار")
    print("هزینه‌ی هر بخش فرض نمی‌شود؛ پس از نخستین فراخوانی اندازه‌گیری می‌شود.")
    if plan.selected == 0:
        print("هیچ بخشی برای ارزیابی نیست (بازیابی‌شده و دارای قطعه).", file=sys.stderr)
        return 1

    needed = ro5b.required_chunk_ids(plan)
    async with session_scope() as session:
        contents = await ro5b.load_chunk_contents(session, needed)
    print(f"متن کامل قطعه در پایگاه داده: {len(contents)} از {len(needed)} (فقط خواندن)")
    if args.dry_run:
        print("--dry-run بود: مدل صدا زده نشد و فایلی نوشته نشد.")
        return 0

    client = None
    try:
        client = build_client()
    except Exception as exc:  # noqa: BLE001 - هر کمبود پیکربندی یعنی مدل در دسترس نیست
        print(
            f"⚠️ مدل در دسترس نیست ({type(exc).__name__}). ارزیابی انجام نمی‌شود و بخش‌ها با "
            "وضعیت model_unavailable ثبت می‌شوند.",
            file=sys.stderr,
        )

    try:
        evaluation = await ro5b.run_ro5b(
            loaded,
            contents,
            client,
            input_name=path.name,
            seed=args.seed,
            max_parts=args.max_parts,
            max_cost_usd=args.max_cost_usd,
            progress=lambda line: print(line, flush=True),
        )
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1

    paths = ro5b.write_outputs(evaluation, Path(args.out))
    print(ro5b.render_summary(evaluation))
    print(f"\nJSON (خصوصی):     {paths['json']}")
    print(f"خلاصه (بی‌متن):   {paths['summary']}")
    print(f"CSV بازبینی:      {paths['csv']}")
    print("⚠️ JSON و CSV پرسش (پوشانده‌شده)ی دانشجو دارند. در مخزن نگذارید.")
    return 0


async def cmd_e2e_shadow_run(args: argparse.Namespace) -> int:
    """سایه‌ی سرتاسری پاسخ‌دهی: فهم ← بازیابی ← ربط شواهد ← تصمیم ← نوشتن. فقط‌خواندنی.

    هیچ پیامی به تلگرام نمی‌رود و کل کار در یک تراکنش `READ ONLY` است (نوشتن رد می‌شود).
    فقط شمارش چاپ می‌شود؛ پاسخ‌ها در `e2e_shadow.json` و `e2e_review.csv` (خصوصی) می‌مانند.
    """
    import json
    from pathlib import Path

    from mentorai import model_compare as mc
    from mentorai.ai import e2e_shadow as e2e
    from mentorai.ai.providers import build_client

    selection = None
    categories = None
    if args.select_from:
        try:
            raw = Path(args.select_from).read_text(encoding="utf-8")
            categories = e2e.categorize_ro5a(json.loads(raw))
        except (OSError, json.JSONDecodeError):
            print("انجام نشد: فایل انتخاب نمونه باز یا خوانده نشد", file=sys.stderr)
            return 1
        except mc.CompareError as exc:
            print(f"انجام نشد: {exc}", file=sys.stderr)
            return 1

    async with session_scope() as session:
        # کل مسیر، حتی خواندنِ زمینه و بازیابی، در یک تراکنش فقط‌خواندنی؛ نوشتن رد می‌شود.
        await session.execute(text("SET TRANSACTION READ ONLY"))
        missing = 0
        if categories is not None:
            eligible = await mc.sample_from_database(session, limit=mc.DB_POOL, seed=args.seed)
            selection = e2e.select_messages(categories, limit=args.limit, seed=args.seed)
            cases, missing = e2e.cases_for(selection, eligible)
        else:
            cases = await mc.sample_from_database(session, limit=args.limit, seed=args.seed)
        if not cases:
            print("هیچ پیامی برای نمونه پیدا نشد", file=sys.stderr)
            return 1
        print(f"{len(cases)} پیام انتخاب شد (درخواستی: {args.limit}، seed={args.seed})")
        if selection is not None:
            coverage = "، ".join(f"{k}: {v}" for k, v in selection.coverage.items())
            print(f"پوشش نمونه (از خروجی مدل): {coverage}")
            if selection.shortfall:
                lacking = "، ".join(f"{k}: {v}" for k, v in selection.shortfall.items())
                print(f"⚠️ کمبود پوشش (کمتر از حداقل): {lacking}")
            if missing:
                print(f"⚠️ {missing} پیام انتخاب‌شده دیگر در نمونه‌ی قابل‌استفاده نبود")
        print(f"سقف هزینه: {args.max_cost_usd:.2f} دلار (بین چهار مرحله مشترک)")
        print("هزینه‌ی هر پیام فرض نمی‌شود؛ هر مرحله پس از نخستین فراخوانی اندازه‌گیری می‌شود.")
        if args.dry_run:
            print("--dry-run بود: مدل صدا زده نشد و فایلی نوشته نشد.")
            return 0

        try:
            client = build_client()
        except Exception as exc:  # noqa: BLE001 - هر کمبود پیکربندی یعنی مدل در دسترس نیست
            print(f"مدل در دسترس نیست ({type(exc).__name__}); اجرا انجام نشد.", file=sys.stderr)
            return 1

        try:
            data = await e2e.run_e2e(
                session,
                cases,
                client,
                embedder=_embedder(),
                seed=args.seed,
                requested=args.limit,
                max_cost_usd=args.max_cost_usd,
                selection=selection,
                missing_selected=missing,
                progress=lambda line: print(line, flush=True),
            )
        except mc.CompareError as exc:
            print(f"انجام نشد: {exc}", file=sys.stderr)
            return 1

    paths = e2e.write_outputs(data, Path(args.out))
    print(e2e.render_summary(data))
    print(f"\nJSON (خصوصی):  {paths['json']}")
    print(f"CSV بازبینی:   {paths['csv']}")
    print(f"دستورها (هش‌دار): {paths['prompts']}")
    print("⚠️ هر دو فایل پیام و پاسخ (پوشانده‌شده) دارند. در مخزن نگذارید.")
    return 0


async def cmd_conversation_eval_prepare(args: argparse.Namespace) -> int:
    """آماده‌سازی ارزیابی مکالمه: نمونه‌ی ناشناس با زمینه‌ی کامل. **هیچ مدلی صدا زده نمی‌شود.**

    فقط روی نشست پایگاه داده‌ی فقط‌خواندنی اجرا می‌شود. با `--check` فقط شمارش چاپ می‌شود و
    هیچ فایلی نوشته نمی‌شود.
    """
    from mentorai import model_compare as mc
    from mentorai.ai import conversation_eval as ce

    try:
        variant = ce.load_variant(Path(args.variant)) if args.variant else None
        async with ce.readonly_session() as session:
            document = await ce.prepare(
                session,
                limit=args.limit,
                seed=args.seed,
                min_history=args.min_history,
                embedder=_embedder(),
                variant=variant,
                max_output_tokens=args.max_output_tokens,
                progress=lambda line: print(line, flush=True),
            )
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1

    if not document["cases"]:
        print("هیچ نمونه‌ای پیدا نشد", file=sys.stderr)
        return 1
    print(ce.render_prepare_summary(document))
    if args.check:
        print("--check بود: هیچ فایلی نوشته نشد و هیچ مدلی صدا زده نشد.")
        return 0
    path = ce.write_prepared(document, Path(args.out))
    print(f"\nفایل آماده‌سازی (خصوصی): {path}")
    print(f"کد تأیید برای اجرا: {document['manifest_sha256'][:8]}")
    print("⚠️ این فایل پیام واقعی (پوشانده‌شده) دارد. در مخزن نگذارید.")
    return 0


async def cmd_conversation_eval_run(args: argparse.Namespace) -> int:
    """اجرای ارزیابی مکالمه با مدل. به پایگاه داده و تلگرام وصل نمی‌شود.

    بدون `--approve` با کد درست، فقط خلاصه و بدترین هزینه چاپ می‌شود و هیچ کلاینتی ساخته
    نمی‌شود.
    """
    from mentorai import model_compare as mc
    from mentorai.ai import conversation_eval as ce
    from mentorai.ai.providers import build_client

    try:
        document = ce.load_prepared(Path(args.prepared))
        arms = ce.parse_arms(args.arms, document)
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1

    print(ce.render_plan(document, arms, args.max_cost_usd, args.cost_guard))
    if args.approve != document["manifest_sha256"][:8]:
        print(
            "\nمدل صدا زده نشد. برای اجرا کد تأیید را بدهید: "
            f"--approve {document['manifest_sha256'][:8]}",
            file=sys.stderr,
        )
        return 2

    try:
        client = build_client()
    except Exception as exc:  # noqa: BLE001 - هر کمبود پیکربندی یعنی مدل در دسترس نیست
        print(f"مدل در دسترس نیست ({type(exc).__name__}); اجرا انجام نشد.", file=sys.stderr)
        return 1
    retries_off = ce.disable_retries(client)
    try:
        run = await ce.run_eval(
            document,
            client,
            arms=arms,
            max_cost_usd=args.max_cost_usd,
            guard=args.cost_guard,
            attempts_factor=1 if retries_off else ce.UNCONTROLLED_ATTEMPTS,
            progress=lambda line: print(line, flush=True),
        )
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1

    print(ce.render_run_summary(run))
    if not run.results:
        print("هیچ نمونه‌ای اجرا نشد؛ چیزی نوشته نشد", file=sys.stderr)
        return 1
    out_dir = Path(args.out) if args.out else Path(args.prepared).parent
    paths = ce.write_outputs(document, run, out_dir)
    print(f"برگه‌ی داور:   {paths['sheet']}")
    print(f"راهنمای داور:  {paths['guide']}")
    print(f"کلید (خصوصی):  {paths['key']}  ← تا پایان داوری به داور ندهید")
    print("⚠️ این فایل‌ها پیام واقعی (پوشانده‌شده) دارند. در مخزن نگذارید.")
    return 0


async def cmd_conversation_eval_report(args: argparse.Namespace) -> int:
    """گزارش پس از داوری: کلید و برگه‌ی پرشده را یکی کن. مدل صدا زده نمی‌شود."""
    from mentorai import model_compare as mc
    from mentorai.ai import conversation_eval as ce

    key_path = Path(args.key)
    try:
        report = ce.make_report(key_path, Path(args.graded))
    except mc.CompareError as exc:
        print(f"انجام نشد: {exc}", file=sys.stderr)
        return 1
    print(report)
    try:
        saved = ce.write_report(report, key_path.parent)
        print(f"\nذخیره شد: {saved}")
    except OSError:
        pass  # پوشه‌ی کلید فقط‌خواندنی است؛ گزارش همین‌جا چاپ شد
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

    rrun = sub.add_parser(
        "retrieval-shadow-run",
        help="سایه‌ی بازیابی: فهم v2 + بازیابی فعلی روی پیام‌های واقعی (فقط‌خواندنی، بدون اثر "
        "روی پاسخ‌دهی؛ هزینه‌ی مدل فهم دارد)",
    )
    rsource = rrun.add_mutually_exclusive_group(required=True)
    rsource.add_argument("--cases", help="CSV با ستون question")
    rsource.add_argument("--from-db", type=int, help="چند پیام واقعی دانشجو از پایگاه داده")
    rrun.add_argument("--limit", type=int, default=60, help="سقف پرسش برای --cases")
    rrun.add_argument("--seed", type=int, default=7)
    rrun.add_argument("--max-cost-usd", type=float, default=1.0)
    rrun.add_argument(
        "--out",
        default="/out/retrieval-shadow" if _os.path.isdir("/out") else "retrieval-shadow",
    )
    rrun.add_argument("--dry-run", action="store_true", help="فقط پرسش‌ها را بشمار؛ مدل صدا نزن")
    rrun.set_defaults(func=cmd_retrieval_shadow_run)

    drun = sub.add_parser(
        "decision-shadow-run",
        help="سایه‌ی شواهد و تصمیم از روی خروجی retrieval-shadow-run (بدون مدل، بدون هزینه، "
        "بدون پایگاه داده، بدون اثر روی پاسخ‌دهی)",
    )
    drun.add_argument(
        "--from-shadow", required=True, help="retrieval_shadow.json که retrieval-shadow-run ساخت"
    )
    drun.add_argument(
        "--out",
        default="/out/decision-shadow" if _os.path.isdir("/out") else "decision-shadow",
    )
    drun.set_defaults(func=cmd_decision_shadow_run)

    r5 = sub.add_parser(
        "ro5a-shadow-run",
        help="ارزیابی سایه‌ی واقعی RO-5A: نمونه‌ی پیام‌های ذخیره‌شده ← فهم ← بازیابی ← تصمیم "
        "← گزارش (فقط‌خواندنی؛ هزینه‌ی مدل فهم دارد)",
    )
    r5.add_argument("--from-db", type=int, required=True, help="چند پیام واقعی دانشجو")
    r5.add_argument("--seed", type=int, default=7)
    r5.add_argument(
        "--max-cost-usd", type=float, required=True, help="سقف هزینه؛ اجباری، بدون پیش‌فرض"
    )
    r5.add_argument("--out", default="/out/ro5a" if _os.path.isdir("/out") else "ro5a")
    r5.add_argument("--dry-run", action="store_true", help="فقط تعداد نمونه؛ مدل صدا نزن")
    r5.set_defaults(func=cmd_ro5a_shadow_run)

    r5b = sub.add_parser(
        "ro5b-evidence-shadow-run",
        help="سایه‌ی ربط شواهد RO-5B: ربط واقعی قطعه‌های بازیابی‌شده را ارزیابی می‌کند "
        "(فقط‌خواندنی؛ تصمیم را تغییر نمی‌دهد؛ هزینه‌ی مدل ارزیاب دارد)",
    )
    r5b.add_argument(
        "--from-shadow",
        required=True,
        help="retrieval_shadow.json (RO-3) یا ro5a_shadow_evaluation.json (RO-5A)",
    )
    r5b.add_argument(
        "--max-cost-usd", type=float, required=True, help="سقف هزینه؛ اجباری، بدون پیش‌فرض"
    )
    r5b.add_argument("--out", default="/out/ro5b" if _os.path.isdir("/out") else "ro5b")
    r5b.add_argument("--dry-run", action="store_true", help="فقط شمارش؛ مدل صدا نزن")
    r5b.add_argument("--seed", type=int, default=7, help="فقط برای نمونه‌گیری با --max-parts")
    r5b.add_argument(
        "--max-parts", type=int, default=None, help="حداکثر بخش (نمونه‌ی تصادفیِ دارای seed)"
    )
    r5b.set_defaults(func=cmd_ro5b_evidence_shadow_run)

    e2e = sub.add_parser(
        "e2e-shadow-run",
        help="سایه‌ی سرتاسری پاسخ‌دهی: فهم ← بازیابی ← ربط شواهد ← تصمیم ← نوشتن "
        "(فقط‌خواندنی؛ هیچ پیامی ارسال نمی‌شود؛ هزینه‌ی مدل دارد)",
    )
    e2e.add_argument(
        "--select-from",
        default=None,
        help="خروجی RO-5A (ro5a_shadow_evaluation.json) برای انتخاب نمونه با پوشش دسته‌ها",
    )
    e2e.add_argument("--limit", type=int, default=20, help="چند پیام (پیش‌فرض ۲۰)")
    e2e.add_argument("--seed", type=int, default=7)
    e2e.add_argument(
        "--max-cost-usd", type=float, required=True, help="سقف هزینه؛ اجباری، بدون پیش‌فرض"
    )
    e2e.add_argument("--out", default="/out/e2e" if _os.path.isdir("/out") else "e2e")
    e2e.add_argument("--dry-run", action="store_true", help="فقط نمونه؛ مدل صدا نزن")
    e2e.set_defaults(func=cmd_e2e_shadow_run)

    _eval_out = "/out/conv_eval" if _os.path.isdir("/out") else "conv_eval"
    cprep = sub.add_parser(
        "conversation-eval-prepare",
        help="ارزیابی مکالمه، گام ۱: نمونه‌ی ناشناس با زمینه‌ی کامل (فقط‌خواندنی؛ بدون مدل)",
    )
    cprep.add_argument("--limit", type=int, default=30, help="چند پیام (پیش‌فرض ۳۰)")
    cprep.add_argument("--seed", type=int, default=7)
    cprep.add_argument(
        "--min-history", type=int, default=1, help="حداقل پیام قبلی لازم برای هر نمونه"
    )
    cprep.add_argument(
        "--variant", default=None, help="فایل JSON نسخه‌ی لحن (بازوی C)؛ بدون آن فقط A"
    )
    cprep.add_argument(
        "--max-output-tokens",
        type=int,
        default=None,
        help="سقف خروجی برای محاسبه‌ی بدترین هزینه (پیش‌فرض: AI_MAX_TOKENS)",
    )
    cprep.add_argument("--out", default=_eval_out)
    cprep.add_argument("--check", action="store_true", help="فقط شمارش؛ هیچ فایلی ننویس")
    cprep.set_defaults(func=cmd_conversation_eval_prepare)

    crun2 = sub.add_parser(
        "conversation-eval-run",
        help="ارزیابی مکالمه، گام ۲: اجرای مدل (هزینه دارد؛ فقط با --approve؛ بدون پایگاه داده)",
    )
    crun2.add_argument("--prepared", required=True, help="prepared.json گام ۱")
    crun2.add_argument("--arms", default="A,C", help="بازوها، مثلاً A یا A,C")
    crun2.add_argument(
        "--max-cost-usd", type=float, required=True, help="سقف هزینه؛ اجباری، بدون پیش‌فرض"
    )
    crun2.add_argument(
        "--cost-guard",
        choices=("strict", "measured"),
        default="strict",
        help="strict: هرگز از سقف نمی‌گذرد. measured: ممکن است حداکثر یک نمونه از سقف بگذرد",
    )
    crun2.add_argument("--approve", default=None, help="کد تأیید ۸ نویسه‌ای که گام ۱ چاپ کرد")
    crun2.add_argument("--out", default=None, help="پیش‌فرض: کنار prepared.json")
    crun2.set_defaults(func=cmd_conversation_eval_run)

    crep2 = sub.add_parser(
        "conversation-eval-report", help="ارزیابی مکالمه، گام ۳: گزارش از برگه‌ی پرشده (بدون مدل)"
    )
    crep2.add_argument("--key", required=True, help="key.json که گام ۲ ساخت")
    crep2.add_argument("--graded", required=True, help="blind_sheet.csv پرشده")
    crep2.set_defaults(func=cmd_conversation_eval_report)

    run = sub.add_parser("run-gateway", help="اجرای دروازه برای همه حساب‌های فعال")
    run.set_defaults(func=cmd_run_gateway)

    worker = sub.add_parser("run-worker", help="اجرای کارگر و ربات کنترل")
    worker.set_defaults(func=cmd_run_worker)

    args = parser.parse_args()
    exit_code: int = asyncio.run(args.func(args))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
