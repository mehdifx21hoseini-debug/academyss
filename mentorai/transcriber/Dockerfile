# سرویس رونویسی ویس (ADR-033).
#
# همان قاعده‌ی تصویر اصلی (ADR-025): نصب از قفل با هش، نه از بازه‌ی نسخه. اینجا
# اهمیتش دیده هم شد: faster-whisper می‌گوید av>=11 بی سقف، و av 19 آن را می‌شکند —
# نصب بی‌قفل همین امروز سرویسی می‌ساخت که هیچ ویسی را باز نمی‌کند.
#
# وزن‌های مدل (حدود سه گیگ) داخل تصویر نیستند. بار اول روی volume دانلود می‌شوند،
# با نسخه‌ی پین‌شده در `app.py`، و از آن به بعد از همان‌جا خوانده می‌شوند.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    WHISPER_MODEL_DIR=/models HF_HUB_DISABLE_TELEMETRY=1
WORKDIR /app

COPY requirements.lock ./
RUN pip install --no-cache-dir --require-hashes -r requirements.lock

COPY __init__.py app.py ./transcriber/

RUN useradd --create-home --uid 10002 transcriber \
    && mkdir -p /models && chown transcriber:transcriber /models
USER transcriber

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=600s --retries=3 \
    CMD python -c "import json,urllib.request as u; r=json.load(u.urlopen('http://127.0.0.1:8000/healthz')); raise SystemExit(r['status']!='ok')"

CMD ["python", "-m", "transcriber.app"]
