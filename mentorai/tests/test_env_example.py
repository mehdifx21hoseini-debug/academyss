"""`.env.example` همان چیزی است که هر مالک کپی می‌کند؛ باید یک پیکربندی معتبر باشد.

این آزمون پس از آن نوشته شد که فیلدهای خالیِ عددی (`AI_PRICE_INPUT_USD=`) اضافه شدند و
معلوم شد pydantic رشته‌ی خالی را «عدد نامعتبر» می‌داند: هر استقرار تازه با فایل نمونه
روشن نمی‌شد. هیچ آزمون دیگری فایل نمونه را نمی‌خواند، پس هیچ‌کدام نمی‌گرفتش.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from mentorai.config import Settings

EXAMPLE = Path(__file__).resolve().parent.parent / ".env.example"

# آنچه مالک باید خودش پر کند. بقیه‌ی خطوط باید همان‌طور که هستند معتبر باشند.
_OWNER_FILLS = {
    "DATABASE_URL": "postgresql+asyncpg://u:p@db:5432/d",
    "SESSION_ENCRYPTION_KEY": "TfB5m6h0nsGGmZ2Zt2sD1u9wY9NClsMkVQ8mXvJqZ7A=",
    "TELEGRAM_API_ID": "1",
    "TELEGRAM_API_HASH": "hash",
}


def _filled(tmp_path: Path, **extra: str) -> Path:
    values = {**_OWNER_FILLS, **extra}
    lines = []
    for line in EXAMPLE.read_text(encoding="utf-8").splitlines():
        key = line.split("=", 1)[0]
        lines.append(f"{key}={values[key]}" if key in values else line)
    path = tmp_path / ".env"
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


@pytest.fixture(autouse=True)
def _clean_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    """متغیرهای محیط بر فایل مقدم‌اند؛ برای سنجیدن خود فایل باید نباشند."""
    for field in Settings.model_fields:
        monkeypatch.delenv(field.upper(), raising=False)


def test_the_example_copied_as_is_is_a_valid_configuration(tmp_path: Path) -> None:
    settings = Settings(_env_file=_filled(tmp_path))  # type: ignore[call-arg]

    assert settings.ai_provider == "anthropic"
    assert settings.ai_model == "", "خالی یعنی پیش‌فرض ارائه‌دهنده"
    assert settings.ai_price_input_usd is None and settings.ai_price_output_usd is None
    assert settings.ai_max_tokens == 8000


def test_a_required_value_left_empty_is_an_error_not_an_empty_secret(tmp_path: Path) -> None:
    """پیش از این، «DATABASE_URL=» خالی بی‌صدا به‌عنوان رمز خالی پذیرفته می‌شد."""
    from pydantic import ValidationError

    with pytest.raises(ValidationError, match="database_url"):
        Settings(_env_file=_filled(tmp_path, DATABASE_URL=""))  # type: ignore[call-arg]


def test_the_example_lists_every_setting_the_ai_layer_reads() -> None:
    text = EXAMPLE.read_text(encoding="utf-8")
    for name in (
        "AI_PROVIDER",
        "AI_MODEL",
        "AI_EFFORT",
        "AI_MAX_TOKENS",
        "AI_TIMEOUT_SECONDS",
        "AI_PRICE_INPUT_USD",
        "AI_PRICE_OUTPUT_USD",
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
    ):
        assert f"\n{name}=" in text, f"{name} در .env.example نیست"
