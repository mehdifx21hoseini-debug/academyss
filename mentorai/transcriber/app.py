"""سرویس رونویسی ویس، داخل خودِ استقرار آکادمی.

**چرا اینجا و نه یک سرویس ابری.** صدای دانشجو داده‌ی شخصی است. سرویس ابری یعنی
صدای هزاران دانشجو از سرور آکادمی بیرون می‌رود، به شرکتی دیگر، و طبق مدل امنیتی
پروژه این خودش تصمیمی است که تأیید مالک و یک ADR می‌خواهد. این سرویس همان رابط
استاندارد `POST /v1/audio/transcriptions` را دارد که `media/voice.py` از روز اول
انتظارش را داشت (`ADR-023`)، ولی کنار بقیه‌ی سرویس‌ها روی همان سرور اجرا می‌شود:
**هیچ صدایی از سرور بیرون نمی‌رود** و هزینه‌ای به‌ازای هر دقیقه ندارد (`ADR-033`).

سه قاعده که هر کدام یک شکست مشخص را می‌بندد:

۱. **یک رونویسی در هر لحظه.** Whisper روی پردازنده همه‌ی هسته‌ها را می‌گیرد و
   حدود چهار گیگ حافظه. دو رونویسی هم‌زمان یعنی دو برابر حافظه و هیچ‌کدام سریع‌تر
   نمی‌شوند؛ پس صف می‌شوند.

۲. **ویس بلند، رد می‌شود پیش از رونویسی.** یک ویس ده‌دقیقه‌ای روی پردازنده چند
   دقیقه کار است و پشتش بقیه‌ی ویس‌ها می‌مانند. سقف را می‌شکنیم و آن ویس به منتور
   می‌رود — منتور هم ویس بلند را خودش گوش می‌دهد.

۳. **متن رونویسی هرگز لاگ نمی‌شود.** فقط اندازه، مدت و زمان. متن، حرف دانشجوست.

`faster_whisper` فقط داخل `WhisperEngine` ایمپورت می‌شود تا تست‌های این سرویس —
که در مجموعه‌ی تست اصلی اجرا می‌شوند — بدون مدل چهارگیگی و بدون این وابستگی سنگین
اجرا شوند.
"""

from __future__ import annotations

import asyncio
import io
import logging
import os
import time
from collections.abc import Callable, Iterable
from contextlib import asynccontextmanager
from typing import Annotated, Any, Protocol

from fastapi import FastAPI, File, Form, HTTPException, UploadFile

log = logging.getLogger("transcriber")

# همان سقف سمت فرستنده (`media/voice.py`). دو جا یک عدد، چون اگر سرویس کمتر بپذیرد،
# فرستنده فایلی می‌فرستد که همیشه رد می‌شود.
MAX_AUDIO_BYTES = 20 * 1024 * 1024
# ویس بلندتر از این رونویسی نمی‌شود و به منتور می‌رود.
DEFAULT_MAX_AUDIO_SECONDS = 180
# Whisper پیش‌متن را حداکثر ۲۲۴ توکن می‌پذیرد؛ بیشترش بی‌صدا بریده می‌شود.
MAX_PROMPT_CHARS = 600

# نسخه‌ی دقیق وزن‌های مدل. بدون پین، یک بارگذاری مجدد سرور می‌تواند بی‌صدا وزن‌های
# دیگری بیاورد — همان مسئله‌ای که ADR-025 برای بسته‌های پایتون بست.
PINNED_REVISIONS: dict[str, str] = {
    "large-v3": "edaa852ec7e145841d8ffdb056a99866b5f0a478",
    "large-v3-turbo": "0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf",
}


class AudioUnreadable(Exception):
    """فایل صوتی باز نشد. به ۴۰۰ تبدیل می‌شود، نه خطای سرور."""


def measure_duration(frames: Iterable[tuple[int, int]], *, stop_after: float) -> float:
    """مدت صدا، از روی قاب‌های رمزگشایی‌شده — و توقف به‌محض گذشتن از سقف.

    هر قاب `(تعداد نمونه، نرخ نمونه)` است. هیچ نمونه‌ای نگه داشته نمی‌شود؛ فقط
    شمرده می‌شود. پس حافظه ثابت است و کار پردازنده حداکثر به اندازه‌ی رمزگشایی
    `stop_after` ثانیه صدا، هرقدر هم فایل بلند باشد.

    چرا نه فراداده‌ی فایل: مدتی که فایل درباره‌ی خودش می‌گوید جعل‌شدنی است. شمارش
    قاب‌ها همان چیزی است که رونویسی واقعاً با آن روبه‌رو می‌شود.
    """
    seconds = 0.0
    for samples, rate in frames:
        if rate > 0:
            seconds += samples / rate
        if seconds > stop_after:
            return seconds
    return seconds


class Engine(Protocol):
    name: str

    def duration(self, audio: bytes, *, stop_after: float) -> float: ...

    def transcribe(self, audio: bytes, *, language: str, prompt: str | None) -> str: ...


class WhisperEngine:
    """Whisper روی پردازنده، با وزن‌های int8."""

    def __init__(
        self,
        name: str,
        *,
        revision: str | None,
        download_root: str,
        cpu_threads: int,
    ) -> None:
        from faster_whisper import WhisperModel, download_model

        self.name = name
        path = download_model(name, cache_dir=download_root, revision=revision)
        self._model = WhisperModel(
            path, device="cpu", compute_type="int8", cpu_threads=cpu_threads
        )

    def duration(self, audio: bytes, *, stop_after: float) -> float:
        """مدت، بدون رمزگشایی کامل.

        نسخه‌ی پیشین کل فایل را به نمونه‌های ۱۶ کیلوهرتزی باز می‌کرد و **بعد** مدت را
        با سقف می‌سنجید. یک فایل اپوس دو مگابایتی با کمترین نرخ، ۹۰ دقیقه صدا دارد:
        ۹۰۰ مگ حافظه و ۹ ثانیه پردازنده فقط برای فهمیدن اینکه بلند است. در سقف ۲۰
        مگابایتی یعنی حدود ۱۵ ساعت صدا و چند گیگ حافظه — کنار مدلی که خودش چهار گیگ
        است، سرویس می‌میرد.
        """
        import av

        try:
            with av.open(io.BytesIO(audio), mode="r") as container:
                frames = (
                    (frame.samples, frame.sample_rate)
                    for frame in container.decode(audio=0)
                )
                return measure_duration(frames, stop_after=stop_after)
        except Exception as exc:  # noqa: BLE001 - هر خطای رمزگشایی یعنی فایل خراب
            raise AudioUnreadable(type(exc).__name__) from exc

    def transcribe(self, audio: bytes, *, language: str, prompt: str | None) -> str:
        try:
            segments, _ = self._model.transcribe(
                io.BytesIO(audio),
                language=language,
                beam_size=5,
                # سکوت حذف می‌شود: هم سریع‌تر، هم جلوی متن‌سازی Whisper روی سکوت را
                # می‌گیرد — عبارت‌هایی مثل «زیرنویس» که روی صدای خالی تولید می‌کند.
                vad_filter=True,
                # بدون این، Whisper گاهی یک جمله را در حلقه تکرار می‌کند.
                condition_on_previous_text=False,
                initial_prompt=prompt,
            )
            return " ".join(s.text.strip() for s in segments).strip()
        except Exception as exc:  # noqa: BLE001
            raise AudioUnreadable(type(exc).__name__) from exc


def engine_from_environment() -> Engine:
    name = os.environ.get("WHISPER_MODEL", "large-v3")
    revision = os.environ.get("WHISPER_MODEL_REVISION") or PINNED_REVISIONS.get(name)
    if revision is None:
        log.warning("whisper_model_unpinned model=%s", name)
    return WhisperEngine(
        name,
        revision=revision,
        download_root=os.environ.get("WHISPER_MODEL_DIR", "/models"),
        cpu_threads=int(os.environ.get("WHISPER_CPU_THREADS", "0")) or (os.cpu_count() or 4),
    )


def create_app(
    engine_factory: Callable[[], Engine] = engine_from_environment,
    *,
    max_audio_seconds: float | None = None,
) -> FastAPI:
    limit = max_audio_seconds or float(
        os.environ.get("MAX_AUDIO_SECONDS", DEFAULT_MAX_AUDIO_SECONDS)
    )
    state: dict[str, Any] = {"engine": None}
    one_at_a_time = asyncio.Lock()

    @asynccontextmanager
    async def lifespan(_: FastAPI):  # type: ignore[no-untyped-def]
        # مدل هنگام شروع بار می‌شود، نه با اولین ویس: بارگذاری ده ثانیه است و دفعه‌ی
        # اول دانلود چند گیگ. سلامت سرویس تا آن موقع «آماده نیست» گزارش می‌شود.
        state["engine"] = await asyncio.to_thread(engine_factory)
        log.info("whisper_ready model=%s", state["engine"].name)
        yield

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    @app.get("/healthz")
    async def healthz() -> dict[str, object]:
        engine = state["engine"]
        return {"status": "ok" if engine else "loading", "model": engine and engine.name}

    @app.post("/v1/audio/transcriptions")
    async def transcriptions(
        file: Annotated[UploadFile, File()],
        model: Annotated[str, Form()],
        language: Annotated[str, Form()] = "fa",
        prompt: Annotated[str | None, Form()] = None,
        response_format: Annotated[str, Form()] = "json",
    ) -> dict[str, str]:
        engine: Engine | None = state["engine"]
        if engine is None:
            raise HTTPException(503, "model is still loading")
        # نام مدل باید همانی باشد که بار شده. پذیرفتن بی‌صدای نام دیگر یعنی
        # `ai_runs` ثبت می‌کند رونویسی با مدلی انجام شده که انجام نشده.
        if model != engine.name:
            raise HTTPException(400, f"this server serves {engine.name!r}, not {model!r}")
        if response_format != "json":
            raise HTTPException(400, "only response_format=json is supported")

        audio = await file.read(MAX_AUDIO_BYTES + 1)
        if len(audio) > MAX_AUDIO_BYTES:
            raise HTTPException(413, "audio file too large")
        if not audio:
            raise HTTPException(400, "empty audio file")

        started = time.monotonic()
        async with one_at_a_time:
            try:
                seconds = await asyncio.to_thread(engine.duration, audio, stop_after=limit)
                if seconds > limit:
                    log.info("audio_too_long seconds=%.0f limit=%.0f", seconds, limit)
                    raise HTTPException(413, "audio too long")
                text = await asyncio.to_thread(
                    engine.transcribe,
                    audio,
                    language=language,
                    prompt=(prompt or None) and prompt[:MAX_PROMPT_CHARS],
                )
            except AudioUnreadable as exc:
                log.info("audio_unreadable error=%s bytes=%d", exc, len(audio))
                raise HTTPException(400, "audio could not be decoded") from exc

        # فقط اندازه و زمان. متن رونویسی حرف دانشجوست و لاگ نمی‌شود.
        log.info(
            "transcribed bytes=%d seconds=%.1f took_ms=%d chars=%d",
            len(audio),
            seconds,
            int((time.monotonic() - started) * 1000),
            len(text),
        )
        return {"text": text}

    return app


def main() -> None:  # pragma: no cover - نقطه‌ی ورود تصویر
    import uvicorn

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    uvicorn.run(create_app(), host="0.0.0.0", port=8000, log_level="warning")


if __name__ == "__main__":  # pragma: no cover
    main()
