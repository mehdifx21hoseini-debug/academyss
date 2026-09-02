"""پنل مدیریت.

تأکید اینجا روی سه چیز است: کسی که وارد نشده هیچ داده‌ای نمی‌بیند، منتور از راه پنل
هم به دانشجوی منتور دیگر نمی‌رسد، و هیچ تغییری بدون توکن فرم انجام نمی‌شود.

آزمون‌های منفی مهم‌ترند: اینکه صفحه برای کاربر مجاز باز می‌شود چیزی درباره‌ی امنیت
ثابت نمی‌کند.
"""

from __future__ import annotations

import re
from collections.abc import AsyncIterator
from datetime import UTC, date, datetime
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import jalali
from mentorai.config import get_settings
from mentorai.db.models import (
    AiRun,
    Conversation,
    ConversationStatus,
    Escalation,
    KnowledgeDocument,
    MentorAccount,
    Message,
    Outcome,
    PanelSession,
    PanelUser,
    Sender,
)
from mentorai.telegram.normalize import build_inbound
from mentorai.telegram.store import record_inbound
from mentorai.web import fmt, security
from mentorai.web.app import create_app

PASSWORD = "correct-horse-battery"
OTHER_PASSWORD = "another-long-password"


def _msg(chat_id: int, message_id: int = 1):  # type: ignore[no-untyped-def]
    return build_inbound(
        account_slug="x",
        chat_id=chat_id,
        message_id=message_id,
        sender_user_id=chat_id,
        username=None,
        first_name="دانشجو",
        last_name=None,
        raw_text="سلام",
        media_type=None,
        reply_to_message_id=None,
        sent_at=datetime(2026, 9, 2, 12, 0, tzinfo=UTC),
        is_private=True,
        is_outgoing=False,
    )


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    """کلاینت روی همان حلقه‌ی رویداد تست.

    عمداً از TestClient استفاده نمی‌شود: آن حلقه‌ی خودش را می‌سازد و موتور پایگاه داده
    که در سطح جلسه ساخته شده به حلقه‌ی دیگری چسبیده می‌ماند.

    نشانی پایه https است چون کوکی نشست با علامت secure می‌رود و روی http ذخیره نمی‌شود.
    """
    transport = ASGITransport(app=create_app())
    async with AsyncClient(transport=transport, base_url="https://panel.test") as c:
        yield c


@pytest.fixture
async def world(session: AsyncSession, account: MentorAccount):  # type: ignore[no-untyped-def]
    """دو منتور، هرکدام یک دانشجو، و یک کاربر پنل به‌ازای هر منتور به‌علاوه‌ی یک مدیر."""
    other = MentorAccount(
        slug="mentor-b",
        mentor_name="منتور ب",
        phone="+989000000002",
        device_model="Desktop",
        system_version="Linux",
        app_version="1.0",
    )
    session.add(other)
    await session.flush()

    a = await record_inbound(session, account, _msg(chat_id=111), sender=Sender.student)
    b = await record_inbound(session, other, _msg(chat_id=222), sender=Sender.student)

    session.add_all(
        [
            PanelUser(
                username="mentor_a",
                display_name="منتور الف",
                password_hash=security.hash_password(PASSWORD),
                role="mentor",
                account_id=account.id,
            ),
            PanelUser(
                username="mentor_b",
                display_name="منتور ب",
                password_hash=security.hash_password(OTHER_PASSWORD),
                role="mentor",
                account_id=other.id,
            ),
            PanelUser(
                username="boss",
                display_name="مدیر",
                password_hash=security.hash_password(PASSWORD),
                role="admin",
            ),
            PanelUser(
                username="retired",
                display_name="منتور سابق",
                password_hash=security.hash_password(PASSWORD),
                role="mentor",
                account_id=account.id,
                active=False,
            ),
        ]
    )
    await session.commit()

    return {
        "conv_a": a.conversation_id,
        "conv_b": b.conversation_id,
        "account_a": account.id,
        "account_b": other.id,
    }


async def _login(client: AsyncClient, username: str, password: str) -> None:
    response = await client.post("/login", data={"username": username, "password": password})
    assert response.status_code == 303, response.text
    assert security.SESSION_COOKIE in client.cookies


def _csrf(html: str) -> str:
    match = re.search(r'name="csrf_token" value="([0-9a-f]+)"', html)
    assert match is not None, "توکن فرم در صفحه نیست"
    return match.group(1)


# ── بدون ورود ────────────────────────────────────────────────────────────────


@pytest.mark.parametrize("path", ["/", "/conversations", "/escalations", "/knowledge"])
async def test_anonymous_is_sent_to_login(client: AsyncClient, world, path: str) -> None:  # type: ignore[no-untyped-def]
    response = await client.get(path)
    assert response.status_code == 303
    assert response.headers["location"] == "/login"


async def test_anonymous_cannot_read_a_conversation(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    response = await client.get(f"/conversations/{world['conv_a']}")
    assert response.status_code == 303
    assert response.headers["location"] == "/login"


# ── ورود ─────────────────────────────────────────────────────────────────────


async def test_wrong_password_gives_no_session(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    response = await client.post("/login", data={"username": "mentor_a", "password": "wrong"})
    assert response.status_code == 200
    assert security.SESSION_COOKIE not in client.cookies


async def test_unknown_and_wrong_password_look_the_same(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    """پیام خطا نباید بگوید کدام نام کاربری وجود دارد."""
    missing = await client.post("/login", data={"username": "ghost", "password": "wrong"})
    wrong = await client.post("/login", data={"username": "mentor_a", "password": "wrong"})
    assert missing.text == wrong.text


async def test_deactivated_user_cannot_log_in(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    response = await client.post("/login", data={"username": "retired", "password": PASSWORD})
    assert response.status_code == 200
    assert security.SESSION_COOKIE not in client.cookies


async def test_session_token_is_not_stored_raw(
    client: AsyncClient, session: AsyncSession, world
) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    token = client.cookies[security.SESSION_COOKIE]

    stored = list((await session.execute(select(PanelSession.token_hash))).scalars())
    assert stored, "نشستی ساخته نشد"
    assert token not in stored


# ── محدودسازی دسترسی از راه پنل ──────────────────────────────────────────────


async def test_mentor_list_shows_only_their_own_conversations(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    html = (await client.get("/conversations")).text
    assert f'/conversations/{world["conv_a"]}"' in html
    assert f'/conversations/{world["conv_b"]}"' not in html


async def test_mentor_cannot_open_another_mentors_conversation(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    response = await client.get(f"/conversations/{world['conv_b']}")
    assert response.status_code == 404


async def test_missing_and_forbidden_give_the_same_answer(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    """۴۰۴ برای «مال منتور دیگر» و «اصلاً وجود ندارد» یکی است.

    اگر این دو فرق داشتند، می‌شد با آزمون شناسه‌ها فهمید منتور دیگر چند مکالمه دارد.
    """
    await _login(client, "mentor_a", PASSWORD)
    forbidden = await client.get(f"/conversations/{world['conv_b']}")
    missing = await client.get("/conversations/999999")
    assert forbidden.status_code == missing.status_code == 404
    assert forbidden.text == missing.text


async def test_mentor_cannot_change_another_mentors_conversation(
    client: AsyncClient, session: AsyncSession, world
) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    token = _csrf((await client.get(f"/conversations/{world['conv_a']}")).text)

    response = await client.post(
        f"/conversations/{world['conv_b']}/assistant",
        data={"enabled": "off", "csrf_token": token},
    )
    assert response.status_code == 404

    other = await session.get(Conversation, world["conv_b"])
    assert other is not None
    await session.refresh(other)
    assert other.assistant_enabled is True


async def test_admin_sees_every_mentors_conversations(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "boss", PASSWORD)
    html = (await client.get("/conversations")).text
    assert f'/conversations/{world["conv_a"]}"' in html
    assert f'/conversations/{world["conv_b"]}"' in html


async def test_kpis_are_scoped_to_the_mentor(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    mentor_html = (await client.get("/")).text
    await client.post("/logout", data={"csrf_token": _csrf(mentor_html)})

    await _login(client, "boss", PASSWORD)
    admin_html = (await client.get("/")).text

    assert re.search(r'<span class="num">۱</span>\s*<span class="lbl">مکالمه</span>', mentor_html)
    assert re.search(r'<span class="num">۲</span>\s*<span class="lbl">مکالمه</span>', admin_html)


# ── توکن فرم ─────────────────────────────────────────────────────────────────


async def test_post_without_csrf_token_is_refused(
    client: AsyncClient, session: AsyncSession, world
) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    response = await client.post(
        f"/conversations/{world['conv_a']}/assistant", data={"enabled": "off"}
    )
    assert response.status_code == 403

    conversation = await session.get(Conversation, world["conv_a"])
    assert conversation is not None
    await session.refresh(conversation)
    assert conversation.assistant_enabled is True


async def test_csrf_token_of_another_session_is_refused(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    """توکن فرم به نشست گره خورده است، پس توکن یکی برای دیگری کار نمی‌کند."""
    await _login(client, "mentor_a", PASSWORD)
    stolen = _csrf((await client.get("/")).text)
    await client.post("/logout", data={"csrf_token": stolen})

    await _login(client, "mentor_b", OTHER_PASSWORD)
    response = await client.post(
        f"/conversations/{world['conv_b']}/assistant",
        data={"enabled": "off", "csrf_token": stolen},
    )
    assert response.status_code == 403


async def test_cross_origin_post_is_refused(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    token = _csrf((await client.get("/")).text)
    response = await client.post(
        f"/conversations/{world['conv_a']}/assistant",
        data={"enabled": "off", "csrf_token": token},
        headers={"origin": "https://evil.example"},
    )
    assert response.status_code == 403


async def test_valid_post_changes_the_conversation(
    client: AsyncClient, session: AsyncSession, world
) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    token = _csrf((await client.get(f"/conversations/{world['conv_a']}")).text)

    response = await client.post(
        f"/conversations/{world['conv_a']}/assistant",
        data={"enabled": "off", "csrf_token": token},
    )
    assert response.status_code == 303

    conversation = await session.get(Conversation, world["conv_a"])
    assert conversation is not None
    await session.refresh(conversation)
    assert conversation.assistant_enabled is False


# ── خروج ─────────────────────────────────────────────────────────────────────


async def test_logout_kills_the_session(client: AsyncClient, world) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    token = client.cookies[security.SESSION_COOKIE]
    await client.post("/logout", data={"csrf_token": _csrf((await client.get("/")).text)})

    # حتی با برگرداندن دستی کوکی هم دیگر کار نمی‌کند: نشست در پایگاه داده باطل شده.
    client.cookies.set(security.SESSION_COOKIE, token, domain="panel.test")
    response = await client.get("/")
    assert response.status_code == 303
    assert response.headers["location"] == "/login"


async def test_expired_session_is_rejected(
    client: AsyncClient, session: AsyncSession, world
) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    panel_session = (await session.execute(select(PanelSession))).scalars().one()
    panel_session.expires_at = datetime.now(UTC) - security.SESSION_LIFETIME
    await session.commit()

    response = await client.get("/")
    assert response.status_code == 303
    assert response.headers["location"] == "/login"


# ── رندر صفحه‌ها با داده‌ی واقعی ──────────────────────────────────────────────


@pytest.fixture
async def with_activity(session: AsyncSession, world):  # type: ignore[no-untyped-def]
    """یک پیام سکوت‌شده با ارجاع باز، و یک سند پایگاه دانش."""
    message = (
        (await session.execute(select(Message).where(Message.conversation_id == world["conv_a"])))
        .scalars()
        .one()
    )

    run = AiRun(
        conversation_id=world["conv_a"],
        message_id=message.id,
        outcome=Outcome.silence.value,
        reason="rule_money",
        prompt_version="v1",
    )
    session.add(run)
    await session.flush()
    session.add(
        Escalation(
            conversation_id=world["conv_a"],
            message_id=message.id,
            ai_run_id=run.id,
            reason="rule_money",
        )
    )
    # موضوع مالی کل مکالمه را می‌سپارد، نه فقط همان یک پیام را؛ پس وضعیت هم عوض
    # می‌شود و بستن ارجاع باید آن را برگرداند.
    conversation = await session.get(Conversation, world["conv_a"])
    assert conversation is not None
    conversation.status = ConversationStatus.awaiting_mentor.value
    session.add(
        KnowledgeDocument(
            external_key="price-2026",
            source_class="official",
            authority="fact",
            category="شهریه",
            title="شهریه دوره‌ی مقدماتی",
            body="مبلغ دوره ...",
            valid_until=date(2020, 1, 1),
        )
    )
    await session.commit()
    return world


async def test_silence_reason_is_shown_in_plain_persian(client: AsyncClient, with_activity) -> None:  # type: ignore[no-untyped-def]
    """منتور باید بفهمد چرا دستیار جواب نداد، بدون دیدن کد داخلی."""
    await _login(client, "mentor_a", PASSWORD)
    html = (await client.get(f"/conversations/{with_activity['conv_a']}")).text
    assert "موضوع مالی بود" in html
    assert "rule_money" not in html


async def test_open_escalation_is_listed(client: AsyncClient, with_activity) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    html = (await client.get("/escalations")).text
    assert "موضوع مالی بود" in html
    assert f"/conversations/{with_activity['conv_a']}" in html


async def test_other_mentor_does_not_see_the_escalation(client: AsyncClient, with_activity) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_b", OTHER_PASSWORD)
    html = (await client.get("/escalations")).text
    assert "چیزی در انتظار نیست" in html


async def test_resolving_closes_the_escalation_and_returns_the_assistant(
    client: AsyncClient, session: AsyncSession, with_activity
) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    token = _csrf((await client.get("/escalations")).text)

    response = await client.post(
        f"/conversations/{with_activity['conv_a']}/resolve", data={"csrf_token": token}
    )
    assert response.status_code == 303

    escalation_row = (await session.execute(select(Escalation))).scalars().one()
    await session.refresh(escalation_row)
    assert escalation_row.resolved_at is not None
    assert escalation_row.resolved_by == "panel:mentor_a"

    conversation = await session.get(Conversation, with_activity["conv_a"])
    assert conversation is not None
    await session.refresh(conversation)
    assert conversation.status == ConversationStatus.active.value


async def test_expired_knowledge_document_is_marked(client: AsyncClient, with_activity) -> None:  # type: ignore[no-untyped-def]
    """سند منقضی باید در پنل دیده شود، وگرنه تا وقتی کسی جواب غلط نگیرد کشف نمی‌شود."""
    await _login(client, "mentor_a", PASSWORD)
    html = (await client.get("/knowledge")).text
    assert "شهریه دوره‌ی مقدماتی" in html
    assert "منقضی" in html


# ── نمایش ────────────────────────────────────────────────────────────────────


async def test_numbers_are_written_in_persian_digits(client: AsyncClient, with_activity) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    html = (await client.get("/")).text
    assert '<span class="num">۱</span>' in html


async def test_ratio_bar_width_comes_from_a_class_not_an_inline_style(
    client: AsyncClient, with_activity
) -> None:  # type: ignore[no-untyped-def]
    """سیاست محتوا سبک درون‌خطی را مسدود می‌کند.

    اگر عرض نوار با ویژگی style بیاید، مرورگر بی‌صدا نادیده‌اش می‌گیرد و نوار همیشه
    خالی می‌ماند — چیزی که هیچ آزمونی جز همین یکی نمی‌گیردش.
    """
    await _login(client, "mentor_a", PASSWORD)
    html = (await client.get("/")).text
    assert re.search(r'<div class="track"><span class="p\d+"></span></div>', html)
    assert "style=" not in html


async def test_times_are_shown_in_tehran_time_and_the_persian_calendar(
    client: AsyncClient, session: AsyncSession, with_activity
) -> None:  # type: ignore[no-untyped-def]
    """پیام‌ها میلادی و UTC ذخیره می‌شوند ولی منتور در تهران است و تقویمش شمسی."""
    message = (
        (
            await session.execute(
                select(Message).where(Message.conversation_id == with_activity["conv_a"])
            )
        )
        .scalars()
        .one()
    )
    await _login(client, "mentor_a", PASSWORD)
    html = (await client.get(f"/conversations/{with_activity['conv_a']}")).text

    at = message.sent_at.astimezone(get_settings().tz)
    assert fmt.digits(f"{jalali.format_date(at.date())} {at:%H:%M}") in html
    # نه ساعت UTC و نه تاریخ میلادی نباید جایی دیده شود.
    assert fmt.digits(message.sent_at.strftime("%H:%M")) not in html
    assert fmt.digits(at.strftime("%Y-%m-%d")) not in html


async def test_document_expiry_is_shown_in_the_persian_calendar(
    client: AsyncClient, with_activity
) -> None:  # type: ignore[no-untyped-def]
    await _login(client, "mentor_a", PASSWORD)
    html = (await client.get("/knowledge")).text
    # ۱۳۹۸/۱۰/۱۱ برابر با ۲۰۲۰-۰۱-۰۱ است.
    assert "۱۱ دی ۱۳۹۸" in html
    assert "2020-01-01" not in html


def test_the_meter_track_class_is_not_reused_elsewhere() -> None:
    """کلاس نوار نسبت نباید نام مشترک با چیز دیگری داشته باشد.

    یک‌بار همین اتفاق افتاد: نوار بالای صفحه هم کلاس bar داشت، قاعده‌های چیدمانش روی
    نوار نسبت هم می‌نشست و پرشدگی با ارتفاع صفر نامرئی می‌شد. مقدارِ درست در HTML بود
    و هیچ آزمونی متوجه نمی‌شد. این آزمون همان برخورد نام را می‌گیرد.
    """
    web = Path(security.__file__).parent
    used_elsewhere = [
        path.name
        for path in sorted((web / "templates").glob("*.html"))
        if path.name != "dashboard.html" and 'class="track"' in path.read_text(encoding="utf-8")
    ]
    assert used_elsewhere == []

    css = (web / "static" / "panel.css").read_text(encoding="utf-8")
    assert ".meter .track {" in css
    # قاعده‌ی سراسری یعنی قاعده‌ای که با همین کلاس شروع می‌شود؛ چنین قاعده‌ای روی هر
    # عنصر دیگری با این نام هم می‌نشیند و همان برخورد را برمی‌گرداند.
    assert not re.search(r"^\.track[\s,{]", css, re.MULTILINE)
