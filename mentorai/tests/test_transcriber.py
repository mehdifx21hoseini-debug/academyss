"""سرویس رونویسی ویس، و قرارداد میان آن و فرستنده.

مدل واقعی اینجا بار نمی‌شود — چهار گیگ است و ده ثانیه. موتور جعلی همان رابط را
دارد و این تست‌ها چیزی را می‌سنجند که به مدل بستگی ندارد: مرزها، صف، رازداری، و
اینکه فرستنده و سرویس درباره‌ی نام فیلدها با هم توافق دارند.
"""

from __future__ import annotations

import asyncio
import csv
import logging
import re
from collections.abc import AsyncIterator
from pathlib import Path

import httpx
import httpx2
import pytest
from transcriber.app import MAX_AUDIO_BYTES, AudioUnreadable, create_app, measure_duration

from mentorai.media import voice

SECRET_SPEECH = "متن محرمانه‌ی ویس دانشجو درباره‌ی حسابش"


class FakeEngine:
    name = "large-v3"

    def __init__(self, *, seconds: float = 5.0, text: str = SECRET_SPEECH, broken: bool = False):
        self.seconds = seconds
        self.text = text
        self.broken = broken
        self.calls: list[dict[str, object]] = []
        self.running = 0
        self.max_running = 0

    def duration(self, audio: bytes, *, stop_after: float) -> float:
        self.stop_after = stop_after
        if self.broken:
            raise AudioUnreadable("InvalidDataError")
        return self.seconds

    def transcribe(self, audio: bytes, *, language: str, prompt: str | None) -> str:
        self.running += 1
        self.max_running = max(self.max_running, self.running)
        try:
            import time

            time.sleep(0.05)
            self.calls.append({"language": language, "prompt": prompt, "bytes": len(audio)})
            return self.text
        finally:
            self.running -= 1


@pytest.fixture
def engine() -> FakeEngine:
    return FakeEngine()


@pytest.fixture
async def service(engine: FakeEngine) -> AsyncIterator[httpx.AsyncClient]:
    app = create_app(lambda: engine, max_audio_seconds=180)
    # ASGITransport رویدادهای شروع را اجرا نمی‌کند؛ مدل در شروع بار می‌شود، پس
    # اینجا دستی اجرا می‌شود.
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://transcriber") as c:
            yield c


def _post(client: httpx.AsyncClient, *, audio: bytes = b"OggS-fake", **data: str):  # type: ignore[no-untyped-def]
    fields = {"model": "large-v3", "language": "fa", "response_format": "json"} | data
    return client.post(
        "/v1/audio/transcriptions",
        files={"file": ("voice.ogg", audio, "audio/ogg")},
        data=fields,
    )


# ---------------------------------------------------------------------------
# سرویس
# ---------------------------------------------------------------------------


async def test_a_voice_comes_back_as_text(service: httpx.AsyncClient, engine: FakeEngine) -> None:
    response = await _post(service, prompt="حد ضرر، پین بار")

    assert response.status_code == 200
    assert response.json() == {"text": SECRET_SPEECH}
    assert engine.calls == [{"language": "fa", "prompt": "حد ضرر، پین بار", "bytes": 9}]


async def test_a_voice_too_long_is_refused_before_transcription(
    service: httpx.AsyncClient, engine: FakeEngine
) -> None:
    """شکستی که می‌بندد: یک ویس ده‌دقیقه‌ای چند دقیقه پردازنده را بگیرد و ویس بقیه پشتش بماند.

    مدت پیش از رونویسی سنجیده می‌شود. ویس بلند به منتور می‌رود؛ منتور هم ویس بلند را
    خودش گوش می‌دهد.
    """
    engine.seconds = 600
    response = await _post(service)

    assert response.status_code == 413
    assert engine.calls == [], "ویس بلند رونویسی شد"
    assert engine.stop_after == 180, "سقف به سنجش مدت نرسید؛ فایل تا آخر رمزگشایی می‌شود"


async def test_a_file_over_the_size_cap_is_refused(
    service: httpx.AsyncClient, engine: FakeEngine
) -> None:
    response = await _post(service, audio=b"x" * (MAX_AUDIO_BYTES + 1))

    assert response.status_code == 413
    assert engine.calls == []


async def test_an_unreadable_file_is_a_client_error_not_a_crash(
    service: httpx.AsyncClient, engine: FakeEngine
) -> None:
    engine.broken = True
    response = await _post(service)

    assert response.status_code == 400


async def test_a_different_model_name_is_refused(service: httpx.AsyncClient) -> None:
    """پذیرفتن بی‌صدای نام دیگر یعنی `ai_runs` مدلی را ثبت کند که اجرا نشده."""
    response = await _post(service, model="large-v3-turbo")

    assert response.status_code == 400


async def test_two_voices_are_transcribed_one_after_the_other(
    service: httpx.AsyncClient, engine: FakeEngine
) -> None:
    """دو رونویسی هم‌زمان یعنی دو برابر حافظه، و هیچ‌کدام سریع‌تر نمی‌شود."""
    first, second = await asyncio.gather(_post(service), _post(service))

    assert first.status_code == second.status_code == 200
    assert engine.max_running == 1, "دو رونویسی هم‌زمان اجرا شدند"


async def test_the_transcript_is_never_logged(
    service: httpx.AsyncClient, caplog: pytest.LogCaptureFixture
) -> None:
    """متن رونویسی حرف دانشجوست. لاگ فقط اندازه و زمان دارد."""
    caplog.set_level(logging.DEBUG, logger="transcriber")
    await _post(service)

    assert caplog.records, "هیچ لاگی ثبت نشد؛ این تست چیزی را نمی‌سنجد"
    assert SECRET_SPEECH not in caplog.text


async def test_health_reports_the_loaded_model(service: httpx.AsyncClient) -> None:
    response = await service.get("/healthz")

    assert response.json() == {"status": "ok", "model": "large-v3"}


# ---------------------------------------------------------------------------
# قرارداد: کد واقعی فرستنده در برابر کد واقعی سرویس
# ---------------------------------------------------------------------------


@pytest.fixture
def wired(engine: FakeEngine, monkeypatch: pytest.MonkeyPatch):  # type: ignore[no-untyped-def]
    """`HttpTranscriber` واقعی، که درخواستش به جای شبکه به همین سرویس می‌رسد."""
    app = create_app(lambda: engine, max_audio_seconds=180)
    real = httpx2.AsyncClient

    def _client(**kwargs: object) -> httpx2.AsyncClient:
        return real(transport=httpx2.ASGITransport(app=app), **kwargs)  # type: ignore[arg-type]

    monkeypatch.setattr(httpx2, "AsyncClient", _client)
    return app


async def test_the_sender_and_the_service_agree_on_the_contract(
    wired, engine: FakeEngine
) -> None:  # type: ignore[no-untyped-def]
    """شکستی که می‌بندد: دو نیمه‌ای که جدا تست شده‌اند و با هم کار نمی‌کنند.

    اگر فرستنده `audio` بفرستد و سرویس `file` بخواهد، هر دو تست‌هایشان را پاس
    می‌کنند و در تولید هیچ ویسی رونویسی نمی‌شود.
    """
    transcriber = voice.HttpTranscriber(base_url="http://transcriber:8000/v1", model="large-v3")
    async with wired.router.lifespan_context(wired):
        text, error = await voice.transcribe(
            transcriber, audio=b"OggS-fake", media_type="audio/ogg"
        )

    assert error is None
    assert text == SECRET_SPEECH
    sent = engine.calls[0]
    assert sent["language"] == "fa"
    assert sent["prompt"] == voice.VOCABULARY_PROMPT, "واژه‌نامه به سرویس نرسید"


async def test_a_refused_voice_reaches_the_sender_as_a_failure(
    wired, engine: FakeEngine
) -> None:  # type: ignore[no-untyped-def]
    """ویس بلند → ۴۱۳ → فرستنده «نشد» می‌گیرد → پیام به منتور می‌رود."""
    engine.seconds = 600
    transcriber = voice.HttpTranscriber(base_url="http://transcriber:8000/v1", model="large-v3")
    async with wired.router.lifespan_context(wired):
        text, error = await voice.transcribe(
            transcriber, audio=b"OggS-fake", media_type="audio/ogg"
        )

    assert text is None
    assert error is not None and "413" in error


# ---------------------------------------------------------------------------
# واژه‌نامه
# ---------------------------------------------------------------------------


def test_every_vocabulary_term_exists_in_the_knowledge_base() -> None:
    """فهرست با حدس پر نمی‌شود: هر واژه باید جایی در دانش آکادمی آمده باشد."""
    export = Path(__file__).resolve().parents[2] / "exports" / "core" / "mentorai_kb_latest.csv"
    with export.open(encoding="utf-8-sig") as handle:
        blob = " ".join(r["question"] + " " + r["answer"] for r in csv.DictReader(handle))
    blob = re.sub(r"[‌\s]+", " ", blob)

    missing = [t for t in voice.VOCABULARY if re.sub(r"[‌\s]+", " ", t) not in blob]
    assert missing == [], f"این واژه‌ها در پایگاه دانش نیستند: {missing}"


def test_the_vocabulary_fits_whisper_prompt_window() -> None:
    """Whisper بیش از حدود ۲۲۴ توکن پیش‌متن را بی‌صدا می‌بُرد."""
    from transcriber.app import MAX_PROMPT_CHARS

    assert len(voice.VOCABULARY_PROMPT) <= MAX_PROMPT_CHARS


# ---------------------------------------------------------------------------
# سنجش مدت، بدون رمزگشایی کامل
# ---------------------------------------------------------------------------


def test_measuring_stops_as_soon_as_the_cap_is_passed() -> None:
    """شکستی که می‌بندد: فایل کوچکی که ساعت‌ها صدا دارد، حافظه‌ی سرویس را تمام کند.

    اندازه‌گیری شد: یک فایل اپوس **دو مگابایتی** با کمترین نرخ، ۹۰ دقیقه صدا داشت و
    رمزگشایی کامل آن ۹۰۰ مگ حافظه و ۹ ثانیه پردازنده گرفت — فقط برای فهمیدن اینکه
    بلند است. سقف حجم ۲۰ مگابایت است، یعنی حدود ۱۵ ساعت صدا.

    این تست یک جریان **پانزده‌ساعته** از قاب می‌دهد — همان چیزی که در سقف ۲۰ مگابایت
    جا می‌شود. اگر سنجش سر سقف بایستد، فقط سه دقیقه‌اش را می‌خواند. جریان عمداً
    بی‌پایان نیست: اگر روزی سنجش دوباره تا آخر برود، این تست باید با پیام روشن
    شکست بخورد، نه اینکه گیر کند و کار CI را تا مهلتش بخوابانند.
    """
    read = 0
    fifteen_hours = int(15 * 3600 / 0.02)

    def endless():  # type: ignore[no-untyped-def]
        nonlocal read
        for _ in range(fifteen_hours):
            read += 1
            yield (960, 48_000)  # قاب ۲۰ میلی‌ثانیه‌ای اپوس

    seconds = measure_duration(endless(), stop_after=180)

    assert seconds > 180
    assert read <= 180 / 0.02 + 1, f"{read} قاب خوانده شد؛ سنجش سر سقف نایستاد"


def test_a_short_voice_is_measured_whole() -> None:
    frames = [(960, 48_000)] * 250  # ۵ ثانیه
    assert measure_duration(frames, stop_after=180) == pytest.approx(5.0)
