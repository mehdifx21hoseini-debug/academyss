# تصویر تولید.
#
# وابستگی‌ها از فایل قفل با هش نصب می‌شوند، نه از بازه‌ی نسخه در pyproject. دلیلش
# در ADR-025 است: تا پیش از این، تصویری که سه ماه بعد ساخته می‌شد همان تصویری
# نبود که تست شده بود. `--require-hashes` یعنی pip هر بسته را در برابر هش خودش
# بررسی می‌کند و اگر فایل روی PyPI عوض شده باشد، ساخت شکست می‌خورد.
#
# uv فقط ابزار تولید قفل است و داخل تصویر نمی‌آید؛ نصب با همان pip استاندارد
# انجام می‌شود.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app

# وابستگی‌ها در لایه‌ی خودشان. تا وقتی قفل عوض نشده، تغییر کد این لایه را دوباره
# نمی‌سازد.
COPY requirements.lock ./
RUN pip install --no-cache-dir --require-hashes -r requirements.lock

# خود بسته، بدون وابستگی: هرچه لازم بود از قفل نصب شد. اگر --no-deps نباشد، pip
# می‌تواند نسخه‌ای بیرون از قفل بیاورد و کل تضمین بازتولیدپذیری از بین برود.
COPY pyproject.toml ./
COPY src ./src
RUN pip install --no-cache-dir --no-deps .

# غیر روت. اگر فرایند به خطر بیفتد، دسترسی ریشه نداشته باشد.
RUN useradd --create-home --uid 10001 mentorai
USER mentorai

CMD ["mentorai", "run-worker"]
