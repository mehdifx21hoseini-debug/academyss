"""پیکربندی، فقط از محیط.

هیچ مقدار پیش‌فرضی برای راز وجود ندارد. نبودن یک تنظیم لازم، خطای راه‌اندازی است،
نه بازگشت بی‌صدا به مقداری که در محیط تولید اشتباه خواهد بود.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal
from zoneinfo import ZoneInfo

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# مقادیر مجاز `embedding_model`. رشته‌ی خالی یعنی مسیر برداری اصلاً اجرا نشود.
# «hashing-test-only» همان نامی است که `HashingEmbedder` اعلام می‌کند؛ تستی نگه
# می‌دارد که این دو از هم جدا نیفتند.
KNOWN_EMBEDDING_MODELS = frozenset({"", "hashing-test-only"})


class Settings(BaseSettings):
    # `env_ignore_empty`: «AI_PRICE_INPUT_USD=» در `.env.example` یعنی «نگذاشته‌ام». بدون آن،
    # pydantic رشته‌ی خالی را عدد حساب می‌کند و خطا می‌دهد؛ هر کسی `.env.example` را کپی
    # می‌کرد، سیستمش روشن نمی‌شد. برای فیلد اجباری هم بهتر است: «DATABASE_URL=» خالی
    # دیگر بی‌صدا پذیرفته نمی‌شود، «مقدار لازم است» می‌گوید.
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", env_ignore_empty=True)

    database_url: SecretStr
    session_encryption_key: SecretStr

    telegram_api_id: int
    telegram_api_hash: SecretStr

    # ربات کنترل منتورها. جدا از حساب‌های کاربری و بدون ریسک مسدودی.
    control_bot_token: SecretStr | None = None
    # شناسه‌ی تلگرام کسانی که اجازه‌ی کار با ربات کنترل را دارند، با کاما جدا شده.
    # خالی یعنی هیچ‌کس. فهرست سفید است، نه سیاه: ناشناخته یعنی بدون دسترسی.
    control_operator_ids: str = ""

    # پیش‌نویس به منتور کجا برسد (ADR-036). `control_bot`: کارت با دکمه‌ی تأیید در
    # ربات کنترل. `chat`: متن در کادر نوشتن خود گفتگوی دانشجو در حساب منتور گذاشته
    # می‌شود، چیزی ارسال نمی‌شود و منتور خودش می‌فرستد. فقط روی حساب‌هایی اثر دارد که
    # حالت پاسخشان «پیش‌نویس» است.
    draft_delivery: Literal["control_bot", "chat"] = "control_bot"

    # آیا پاسخ، پیام دانشجو را «ریپلای» (نقل) کند (ADR-040). `off`: هرگز. `smart`: فقط وقتی
    # دانشجو بعد از آن پیام، پیام تازه‌ای هم فرستاده و پاسخ می‌تواند مبهم باشد.
    # `always`: همیشه. فقط قطعه‌ی اولِ پاسخ نقل می‌گیرد؛ ادامه‌اش ساده می‌آید.
    reply_quote: Literal["off", "smart", "always"] = "always"

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

    # سرویس رونویسی ویس. تا وقتی نشانی و مدل هر دو پر نشده‌اند، هیچ صدایی جایی
    # نمی‌رود و ویس به منتور می‌رسد. ارائه‌دهنده عمداً در کد نوشته نشده (ADR-023).
    transcriber_url: str = ""
    transcriber_model: str = ""
    transcriber_api_key: SecretStr | None = None
    # رونویسی روی پردازنده کند است: ویس ۲۱ ثانیه‌ای با large-v3 حدود ۶۰ ثانیه طول
    # کشید. مهلت پیشین ۶۰ ثانیه بود و همین ویس را درست سر مرز قطع می‌کرد.
    transcriber_timeout_seconds: float = Field(default=180.0, gt=0, le=600)

    # سقف هزینه‌ی مدل. صفر یعنی «هیچ فراخوانی مجاز نیست»، نه «بی‌نهایت» — سقف
    # نداشتن اصلاً گزینه نیست (`ADR-026`).
    #
    # اندازه‌ی پیش‌فرض از روی تخمین هزینه‌ی یک پیام حساب شده، نه اندازه‌گیری: با پرسش
    # و تاریخچه و هشت قطعه‌ی بازیابی‌شده، حدود ۴٬۰۰۰ توکن ورودی و ۵۰۰ توکن خروجی
    # می‌شود. با قیمت claude-opus-5 حدود ۰٫۰۳۳ دلار بود، یعنی ۵ دلار در روز حدود ۱۵۰
    # پیام. مدل پیش‌فرض اکنون Sonnet 5.5 است و ارزان‌تر (`ADR-034`)، پس سقف همان
    # ۵ دلار جای بیشتری دارد؛ عدد واقعی را هفته‌ی آزمایش نشان می‌دهد.
    ai_daily_budget_usd: float = Field(default=5.0, ge=0)
    ai_monthly_budget_usd: float = Field(default=100.0, ge=0)
    # از چند درصد سقف، هشدار در لاگ نوشته شود.
    ai_budget_alert_fraction: float = Field(default=0.8, gt=0, le=1)

    # ارائه‌دهنده و مدل هوش مصنوعی. تنها جایی است که داده‌ی دانشجو از سرور بیرون می‌رود
    # (`ADR-034`، `ADR-035`). از `.env` می‌آید، نه از کد: انتخاب نهایی با سنجش روی پیام‌های
    # واقعی انجام می‌شود و باید یک خط تغییر باشد.
    #
    # مدل برای ارائه‌دهنده‌ی anthropic اختیاری است (پیش‌فرض: Sonnet 5.5)؛ برای openai
    # **اجباری** است، چون نام مدل OpenAI را در کد حدس نمی‌زنیم.
    ai_provider: Literal["anthropic", "openai"] = "anthropic"
    ai_model: str = ""
    # عمق فکر کردن. خالی یعنی پیش‌فرض ارائه‌دهنده: anthropic → medium، openai → چیزی
    # فرستاده نمی‌شود و خود مدل تصمیم می‌گیرد. مقدار مجاز به ارائه‌دهنده بستگی دارد و
    # هنگام روشن شدن سنجیده می‌شود.
    ai_effort: str = ""
    # سقف خروجی **شامل فکر کردن مدل**. ۲۰۴۸ پیشین برای مدلی که پیش‌فرضش فکر کردن
    # است کم بود: فکر بخشی از سقف را می‌خورد و پاسخ نصفه می‌ماند. پرداخت فقط برای
    # توکن‌های تولیدشده است، پس بالا بودن سقف هزینه‌ای ندارد.
    ai_max_tokens: int = Field(default=8000, ge=1024, le=64000)
    ai_timeout_seconds: float = Field(default=90.0, gt=0, le=600)
    # قیمت هر میلیون توکن، به دلار. برای مدلی که در `budget.PRICES` نیست **هر دو لازم‌اند**،
    # وگرنه سیستم روشن نمی‌شود: سقف هزینه بدون قیمت واقعی بی‌معناست. اگر مدل در جدول
    # باشد هم این مقدار مقدم است، تا تغییر قیمت ارائه‌دهنده نیاز به تغییر کد نداشته باشد.
    ai_price_input_usd: float | None = Field(default=None, ge=0)
    ai_price_output_usd: float | None = Field(default=None, ge=0)

    # فقط وقتی AI_PROVIDER=openai. نشانی پایه برای سرویس سازگار یا سرور خودی عوض
    # می‌شود؛ باید https باشد، مگر localhost.
    openai_api_key: SecretStr | None = None
    openai_base_url: str = "https://api.openai.com/v1"

    @model_validator(mode="after")
    def _prices_come_as_a_pair_for_a_named_model(self) -> Settings:
        """قیمت نیمه‌کاره یا بی‌نامِ مدل، بی‌صدا نادیده گرفته می‌شد و سقف را بی‌اعتبار می‌کرد."""
        given = (self.ai_price_input_usd is not None, self.ai_price_output_usd is not None)
        if any(given) and not all(given):
            raise ValueError("AI_PRICE_INPUT_USD و AI_PRICE_OUTPUT_USD باید با هم بیایند")
        if any(given) and not self.ai_model:
            raise ValueError("قیمت فقط برای مدلی معنی دارد که AI_MODEL آن را نام برده باشد")
        return self

    @field_validator("openai_base_url")
    @classmethod
    def _base_url_is_encrypted(cls, v: str) -> str:
        url = v.strip().rstrip("/")
        local = url.startswith(("http://localhost", "http://127.0.0.1"))
        if not (url.startswith("https://") or local):
            raise ValueError("OPENAI_BASE_URL باید https باشد (مگر localhost)")
        return url

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
