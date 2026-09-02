"""پیکربندی، فقط از محیط.

هیچ مقدار پیش‌فرضی برای راز وجود ندارد. نبودن یک تنظیم لازم، خطای راه‌اندازی است،
نه بازگشت بی‌صدا به مقداری که در محیط تولید اشتباه خواهد بود.
"""

from __future__ import annotations

from functools import lru_cache
from zoneinfo import ZoneInfo

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: SecretStr
    session_encryption_key: SecretStr

    telegram_api_id: int
    telegram_api_hash: SecretStr

    # ربات کنترل منتورها. جدا از حساب‌های کاربری و بدون ریسک مسدودی.
    control_bot_token: SecretStr | None = None

    quiet_hours_start: int = Field(default=23, ge=0, le=23)
    quiet_hours_end: int = Field(default=8, ge=0, le=23)
    timezone: str = "Asia/Tehran"

    send_rate_per_minute: float = Field(default=6.0, gt=0, le=20)
    send_burst: int = Field(default=2, ge=1, le=5)

    log_level: str = "INFO"

    @field_validator("timezone")
    @classmethod
    def _known_timezone(cls, v: str) -> str:
        ZoneInfo(v)  # ZoneInfoNotFoundError اگر ناشناخته باشد
        return v

    @property
    def tz(self) -> ZoneInfo:
        return ZoneInfo(self.timezone)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
