"""محافظت در برابر درخواست جعلی بین‌سایتی.

توکن از خود توکن نشست ساخته می‌شود، نه از یک جدول یا حافظه‌ی جداگانه: هیچ حالتی برای
نگهداری نیست، و نشست که باطل شود توکنش هم خودبه‌خود بی‌اعتبار می‌شود.

مهاجم می‌تواند مرورگر قربانی را وادار به فرستادن درخواست کند، ولی نمی‌تواند محتوای
کوکی را بخواند؛ پس نمی‌تواند این مقدار را در فرم بگذارد.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets

from mentorai.config import get_settings

FIELD = "csrf_token"


def _key() -> bytes:
    """کلید امضا از همان کلید رمزنگاری برنامه مشتق می‌شود.

    مشتق‌سازی با یک برچسب انجام می‌شود تا این کلید و کلید رمزگذاری نشست‌های تلگرام
    هرگز یک مقدار نباشند، حتی اگر منبعشان یکی است.
    """
    root = get_settings().session_encryption_key.get_secret_value().encode("utf-8")
    return hashlib.sha256(b"mentorai-csrf-v1:" + root).digest()


def token_for(session_token: str) -> str:
    return hmac.new(_key(), session_token.encode("utf-8"), hashlib.sha256).hexdigest()


def valid(session_token: str | None, submitted: str | None) -> bool:
    if not session_token or not submitted:
        return False
    return secrets.compare_digest(token_for(session_token), submitted)
