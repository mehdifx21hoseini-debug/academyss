"""پیکربندی: مقادیری که اگر بی‌صدا پذیرفته شوند، در محیط تولید اشتباه می‌شوند."""

from __future__ import annotations

import pytest
from cryptography.fernet import Fernet
from pydantic import ValidationError

from mentorai.config import KNOWN_EMBEDDING_MODELS, Settings
from mentorai.knowledge.embeddings import HashingEmbedder

# کلید در لحظه ساخته می‌شود، نه نوشته. هیچ رشته‌ای که شبیه کلید باشد نباید در مخزن
# بماند، حتی وقتی فقط تستی است.
_REQUIRED = {
    "database_url": "postgresql+asyncpg://u:p@localhost:5432/x",
    "session_encryption_key": Fernet.generate_key().decode(),
    "telegram_api_id": 1,
    "telegram_api_hash": "h",
}


def test_embedding_model_is_empty_by_default() -> None:
    """پیش‌فرض یعنی بازیابی فقط متنی.

    بردارساز آزمایشی نباید با سکوت روشن شود؛ روشن بودنش نتیجه را بدتر می‌کند
    (ADR-019).
    """
    assert Settings(**_REQUIRED).embedding_model == ""


def test_unknown_embedding_model_is_a_startup_error_not_a_silent_fallback() -> None:
    with pytest.raises(ValidationError):
        Settings(**_REQUIRED, embedding_model="text-embedding-3-large")


def test_the_test_embedder_name_matches_what_config_accepts() -> None:
    """اگر نام بردارساز آزمایشی عوض شود، پیکربندی باید همان لحظه بشکند.

    وگرنه مقداری که در `.env` نوشته شده بی‌صدا رد می‌شود و کسی نمی‌فهمد مسیر برداری
    اصلاً روشن نشده است.
    """
    assert HashingEmbedder.model in KNOWN_EMBEDDING_MODELS
    assert Settings(**_REQUIRED, embedding_model=HashingEmbedder.model).embedding_model == (
        HashingEmbedder.model
    )
