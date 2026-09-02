"""احراز هویت پنل.

سه چیز اینجا عمدی است و هر سه پاسخ ایرادهایی هستند که در سامانه‌ی دیگر آکادمی دیده شد:

۱. هش رمز با الگوریتم حافظه‌سنگین است، نه یک دور هش سریع. آن سیستم از پیش‌فرض یک نود
   استفاده می‌کرد که MD5 است؛ با حداقل طول رمز شش کاراکتر، شکستنش بی‌معنی آسان است.
۲. ستون رمز متن ساده وجود ندارد. آنجا مسیر ورود اصلاح شده بود ولی مسیر تغییر رمز هنوز
   رمز متن ساده را می‌پذیرفت، چون دو کپی از یک منطق وجود داشت.
۳. توکن نشست ذخیره نمی‌شود، فقط هشش. آنجا توکن متن ساده در جدول بود و هر کسی که به
   داده دسترسی می‌خواند، می‌توانست جای هر مدیری جا بزند.
"""

from __future__ import annotations

import hashlib
import secrets
from datetime import UTC, datetime, timedelta

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai.access import Principal, Role
from mentorai.db.models import PanelSession, PanelUser

SESSION_COOKIE = "mentorai_session"
SESSION_LIFETIME = timedelta(hours=12)
TOKEN_BYTES = 32
MIN_PASSWORD_LENGTH = 12

_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    if len(password) < MIN_PASSWORD_LENGTH:
        raise ValueError(f"رمز باید حداقل {MIN_PASSWORD_LENGTH} کاراکتر باشد")
    return _hasher.hash(password)


def verify_password(stored_hash: str, password: str) -> bool:
    """بررسی رمز. هرگز استثنا پرتاب نمی‌کند؛ هر شکستی یعنی نه."""
    try:
        return _hasher.verify(stored_hash, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def needs_rehash(stored_hash: str) -> bool:
    try:
        return _hasher.check_needs_rehash(stored_hash)
    except InvalidHashError:
        return True


def _token_hash(token: str) -> str:
    """هش توکن نشست.

    اینجا عمداً هش سریع است، برخلاف رمز: توکن ۳۲ بایت تصادفی است و آنتروپی‌اش آن‌قدر
    بالاست که حمله‌ی فرهنگ‌لغتی معنی ندارد. هش کند فقط هر درخواست را کند می‌کرد.
    """
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


async def authenticate(session: AsyncSession, *, username: str, password: str) -> PanelUser | None:
    user = (
        await session.execute(select(PanelUser).where(PanelUser.username == username.strip()))
    ).scalar_one_or_none()

    if user is None:
        # زمان پاسخ برای کاربر ناموجود و رمز غلط باید نزدیک بماند، وگرنه می‌شود با آن
        # فهمید کدام نام کاربری وجود دارد.
        _hasher.hash("dummy-password-for-constant-time")
        return None
    if not user.active or not verify_password(user.password_hash, password):
        return None

    if needs_rehash(user.password_hash):
        user.password_hash = _hasher.hash(password)
    user.last_login_at = datetime.now(UTC)
    return user


async def create_session(
    session: AsyncSession, user: PanelUser, *, source_ip: str | None = None
) -> str:
    """نشست تازه بساز و توکن خام را برگردان.

    توکن خام فقط همین یک بار وجود دارد و در پایگاه داده نمی‌ماند.
    """
    token = secrets.token_urlsafe(TOKEN_BYTES)
    session.add(
        PanelSession(
            token_hash=_token_hash(token),
            user_id=user.id,
            expires_at=datetime.now(UTC) + SESSION_LIFETIME,
            source_ip=source_ip,
        )
    )
    return token


async def resolve_session(session: AsyncSession, token: str | None) -> PanelUser | None:
    if not token:
        return None
    row = (
        await session.execute(
            select(PanelUser)
            .join(PanelSession, PanelSession.user_id == PanelUser.id)
            .where(
                PanelSession.token_hash == _token_hash(token),
                PanelSession.revoked_at.is_(None),
                PanelSession.expires_at > datetime.now(UTC),
                PanelUser.active.is_(True),
            )
        )
    ).scalar_one_or_none()
    return row


async def revoke_session(session: AsyncSession, token: str | None) -> None:
    if not token:
        return
    await session.execute(
        update(PanelSession)
        .where(PanelSession.token_hash == _token_hash(token), PanelSession.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )


def principal_for(user: PanelUser) -> Principal:
    """کاربر پنل به همان درخواست‌دهنده‌ای که لایه‌ی دسترسی می‌فهمد.

    پنل مسیر خصوصی خودش به پایگاه داده ندارد؛ از همان لایه‌ای می‌گذرد که بقیه‌ی سیستم.
    """
    role = Role(user.role)
    return Principal(role=role, account_id=user.account_id, label=f"panel:{user.username}")
