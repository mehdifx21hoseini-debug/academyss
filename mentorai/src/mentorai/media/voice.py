"""متن‌کردن ویس دانشجو.

بعد از این مرحله، ویس دیگر ویس نیست: یک متن فارسی است که وارد همان مسیر آزموده‌شده‌ی
متنی می‌شود. برای همین این گام کم‌ریسک‌ترین گام خواندن فایل است — رونویسی بد هم به
پاسخ غلط ختم نمی‌شود، چون بازیابی سندی پیدا نمی‌کند و سیستم ساکت می‌ماند.

**ارائه‌دهنده انتخاب نشده و در کد هم نوشته نمی‌شود.** این ماژول با هر سرویسی کار
می‌کند که رابط استاندارد `POST /audio/transcriptions` را داشته باشد — سرویس ابری،
یا سروری که خود آکادمی بالا می‌آورد. تا وقتی نشانی در پیکربندی نباشد، هیچ صدایی جایی
نمی‌رود.

⚠️ صدای دانشجو داده‌ی شخصی است. رونویسی ذخیره می‌شود، خود فایل صوتی نه.
"""

from __future__ import annotations

import json
from typing import Protocol

from mentorai.config import get_settings
from mentorai.text import normalize_for_storage

# تلگرام ویس را ogg/opus می‌فرستد؛ بقیه برای فایل‌های صوتی‌اند که به‌عنوان سند می‌آیند.
ALLOWED_TYPES = frozenset(
    {
        "audio/ogg",
        "audio/opus",
        "audio/mpeg",
        "audio/mp4",
        "audio/x-m4a",
        "audio/wav",
        "audio/x-wav",
        "audio/webm",
        "video/mp4",
    }
)
MAX_AUDIO_BYTES = 20 * 1024 * 1024
MAX_TRANSCRIPT_CHARS = 4_000
# رونویسی کوتاه‌تر از این معمولاً سکوت یا نویز است، نه سؤال.
MIN_TRANSCRIPT_CHARS = 3
REQUEST_TIMEOUT_SECONDS = 60.0


class Transcriber(Protocol):
    """هر چیزی که صدا را به متن تبدیل کند. هرگز استثنا پرتاب نمی‌کند."""

    model: str

    async def transcribe(
        self, *, audio: bytes, filename: str, media_type: str
    ) -> tuple[str | None, str | None]: ...


class HttpTranscriber:
    """سرویس رونویسی با رابط استاندارد `POST /audio/transcriptions`.

    عمداً به هیچ ارائه‌دهنده‌ی خاصی گره نخورده: نشانی از پیکربندی می‌آید، پس همین کد
    هم با یک سرویس ابری کار می‌کند و هم با سروری که خود آکادمی بالا می‌آورد.
    """

    def __init__(self, *, base_url: str, model: str, api_key: str | None = None) -> None:
        self._url = base_url.rstrip("/") + "/audio/transcriptions"
        self._api_key = api_key
        self.model = model

    async def transcribe(
        self, *, audio: bytes, filename: str, media_type: str
    ) -> tuple[str | None, str | None]:
        import httpx2

        headers = {"Authorization": f"Bearer {self._api_key}"} if self._api_key else {}
        try:
            async with httpx2.AsyncClient(timeout=REQUEST_TIMEOUT_SECONDS) as client:
                response = await client.post(
                    self._url,
                    headers=headers,
                    files={"file": (filename, audio, media_type)},
                    # زبان صریح داده می‌شود: تشخیص خودکار روی ویس کوتاه فارسی
                    # گاهی زبان دیگری حدس می‌زند و رونویسی بی‌معنی می‌شود.
                    data={"model": self.model, "language": "fa", "response_format": "json"},
                )
        except Exception as exc:  # noqa: BLE001 - هر شکستی به ارجاع ختم می‌شود
            return None, f"{type(exc).__name__}: {exc}"

        if response.status_code != 200:
            # متن پاسخ لاگ نمی‌شود؛ ممکن است بخشی از صدای دانشجو را بازتاب دهد.
            return None, f"سرویس رونویسی کد {response.status_code} برگرداند"
        try:
            body = json.loads(response.content)
        except json.JSONDecodeError:
            return None, "پاسخ سرویس رونویسی JSON نبود"
        text = body.get("text") if isinstance(body, dict) else None
        if not isinstance(text, str):
            return None, "پاسخ سرویس رونویسی متنی نداشت"
        return text, None


def build_transcriber() -> Transcriber | None:
    """رونویس فعال، یا None اگر هیچ سرویسی پیکربندی نشده باشد.

    None پیش‌فرض است و عمدی: تا وقتی مالک آکادمی سرویسی انتخاب نکرده، هیچ صدایی از
    این سیستم بیرون نمی‌رود و ویس مثل قبل به منتور می‌رسد.
    """
    settings = get_settings()
    if not settings.transcriber_url or not settings.transcriber_model:
        return None
    key = settings.transcriber_api_key
    return HttpTranscriber(
        base_url=settings.transcriber_url,
        model=settings.transcriber_model,
        api_key=key.get_secret_value() if key is not None else None,
    )


def is_supported(media_type: str | None, size_bytes: int | None) -> bool:
    """آیا این فایل صوتی اصلاً فرستاده می‌شود — پیش از هر تماسی با سرویس."""
    if media_type not in ALLOWED_TYPES:
        return False
    return size_bytes is None or size_bytes <= MAX_AUDIO_BYTES


async def transcribe(
    transcriber: Transcriber, *, audio: bytes, media_type: str, filename: str = "voice.ogg"
) -> tuple[str | None, str | None]:
    """(متن، خطا). متن None یعنی رونویسی نشد و پرونده به منتور می‌رود."""
    if not is_supported(media_type, len(audio)):
        return None, "قالب یا حجم فایل صوتی پشتیبانی نمی‌شود"

    text, error = await transcriber.transcribe(
        audio=audio, filename=filename, media_type=media_type
    )
    if text is None:
        return None, error or "سرویس رونویسی متنی برنگرداند"

    # همان نرمال‌سازی‌ای که روی متن تایپ‌شده اجرا می‌شود، وگرنه رونویسی و پایگاه دانش
    # با دو نگارش مختلف از یک واژه روبه‌رو می‌شوند و همدیگر را پیدا نمی‌کنند.
    cleaned = normalize_for_storage(text).strip()
    if len(cleaned) < MIN_TRANSCRIPT_CHARS:
        return None, "رونویسی خالی یا بسیار کوتاه بود"
    return cleaned[:MAX_TRANSCRIPT_CHARS], None
