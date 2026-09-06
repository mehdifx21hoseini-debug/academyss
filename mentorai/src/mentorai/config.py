"""پیکربندی، فقط از محیط.

هیچ مقدار پیش‌فرضی برای راز وجود ندارد. نبودن یک تنظیم لازم، خطای راه‌اندازی است،
نه بازگشت بی‌صدا به مقداری که در محیط تولید اشتباه خواهد بود.
"""

from __future__ import annotations

from functools import lru_cache
from zoneinfo import ZoneInfo

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# مقادیر مجاز `embedding_model`. رشته‌ی خالی یعنی مسیر برداری اصلاً اجرا نشود.
# «hashing-test-only» همان نامی است که `HashingEmbedder` اعلام می‌کند؛ تستی نگه
# می‌دارد که این دو از هم جدا نیفتند.
KNOWN_EMBEDDING_MODELS = frozenset({"", "hashing-test-only"})


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: SecretStr
    session_encryption_key: SecretStr

    telegram_api_id: int
    telegram_api_hash: SecretStr

    # ربات کنترل منتورها. جدا از حساب‌های کاربری و بدون ریسک مسدودی.
    control_bot_token: SecretStr | None = None
    # شناسه‌ی تلگرام کسانی که اجازه‌ی کار با ربات کنترل را دارند، با کاما جدا شده.
    # خالی یعنی هیچ‌کس. فهرست سفید است، نه سیاه: ناشناخته یعنی بدون دسترسی.
    control_operator_ids: str = ""

    quiet_hours_start: int = Field(default=23, ge=0, le=23)
    quiet_hours_end: int = Field(default=8, ge=0, le=23)
    timezone: str = "Asia/Tehran"

    send_rate_per_minute: float = Field(default=6.0, gt=0, le=20)
    send_burst: int = Field(default=2, ge=1, le=5)

    # مدل تعبیه‌سازی برای بازیابی برداری. خالی یعنی بازیابی فقط متنی، و این پیش‌فرض
    # عمدی است: تا وقتی مدل واقعی انتخاب نشده، بردار بی‌معنی نتیجه را بدتر می‌کند نه
    # بهتر (ADR-019). تنها مقدار شناخته‌شده‌ی دیگر، بردارساز آزمایشی است.
    embedding_model: str = ""

    @field_validator("embedding_model")
    @classmethod
    def _known_embedding_model(cls, v: str) -> str:
        if v not in KNOWN_EMBEDDING_MODELS:
            known = ", ".join(sorted(x or "«خالی»" for x in KNOWN_EMBEDDING_MODELS))
            raise ValueError(f"مدل تعبیه‌سازی ناشناخته: {v!r}. مقادیر مجاز: {known}")
        return v

    # آیا دستیار از روی توصیف تصویر پاسخ بسازد یا نه. پیش‌فرض خاموش است: تصویر
    # خوانده و ذخیره می‌شود تا منتور کیفیتش را ببیند، ولی تا تأیید مالک، پاسخی از
    # آن ساخته نمی‌شود (ADR-022).
    answer_from_images: bool = False

    log_level: str = "INFO"

    @field_validator("timezone")
    @classmethod
    def _known_timezone(cls, v: str) -> str:
        ZoneInfo(v)  # ZoneInfoNotFoundError اگر ناشناخته باشد
        return v

    @property
    def tz(self) -> ZoneInfo:
        return ZoneInfo(self.timezone)

    @property
    def operator_ids(self) -> frozenset[int]:
        return frozenset(
            int(part) for part in self.control_operator_ids.replace(" ", "").split(",") if part
        )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
