"""رمزنگاری نشست تلگرام در حالت سکون.

نشست MTProto اختیار کامل حساب را دارد. اگر نسخه پشتیبان پایگاه داده جایی برود، نشست
رمزنگاری‌نشده یعنی حساب رفته است.
"""

from __future__ import annotations

from cryptography.fernet import Fernet, InvalidToken

from mentorai.config import get_settings


class SessionDecryptionError(RuntimeError):
    """کلید عوض شده یا داده خراب است. ادامه دادن با نشست ناسالم بی‌معنی است."""


def _cipher() -> Fernet:
    return Fernet(get_settings().session_encryption_key.get_secret_value().encode())


def encrypt_session(session_string: str) -> bytes:
    return _cipher().encrypt(session_string.encode())


def decrypt_session(blob: bytes) -> str:
    try:
        return _cipher().decrypt(blob).decode()
    except InvalidToken as exc:
        raise SessionDecryptionError(
            "رمزگشایی نشست شکست خورد؛ کلید رمزنگاری با آنچه نشست با آن ساخته شده یکی نیست"
        ) from exc
