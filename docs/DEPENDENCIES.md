# وابستگی‌ها

تصمیم و دلیلش در `ADR-025`. این فایل رویه‌ی عملی است.

## دو فایل قفل

| فایل | چه چیزی | کجا استفاده می‌شود |
|---|---|---|
| `mentorai/requirements.lock` | فقط زمان اجرا | `Dockerfile` — تصویر تولید |
| `mentorai/requirements-dev.lock` | زمان اجرا + ابزار تست | CI و محیط توسعه |

هر دو با هش SHA-256 پین شده‌اند. `pip install --require-hashes` اگر فایلی روی
PyPI با همان نام و نسخه اما محتوای متفاوت منتشر شده باشد، شکست می‌خورد.

## افزودن یا به‌روزرسانی یک وابستگی

```bash
cd mentorai

# ۱. نیاز را در pyproject.toml بنویس (همان‌جا، با بازه‌ی نسخه)

# ۲. هر دو قفل را دوباره بساز — هر دو، نه یکی
uv pip compile pyproject.toml --python-version 3.12 --generate-hashes \
  -o requirements.lock
uv pip compile pyproject.toml --python-version 3.12 --extra dev --generate-hashes \
  -o requirements-dev.lock

# ۳. در یک محیط تازه نصب کن — همان دو دستوری که Dockerfile اجرا می‌کند
python3.12 -m venv /tmp/verify
/tmp/verify/bin/pip install --require-hashes -r requirements.lock
/tmp/verify/bin/pip install --no-deps .

# ۴. تست‌ها را اجرا کن
pytest
```

`--python-version 3.12` اختیاری نیست: بدون آن، قفل با مفسر همان ماشین حل می‌شود
و ممکن است با `python:3.12-slim` که تصویر روی آن ساخته می‌شود یکی نباشد.

## چه چیزی جلوی فراموش کردن را می‌گیرد

`tests/test_dependencies.py` سه راه عبور از قفل را می‌بندد:

- وابستگی‌ای که به `pyproject.toml` اضافه شده ولی قفل نشده
- قفلی که سطر بدون هش دارد
- ناهمخوانی نسخه بین قفل تولید و قفل توسعه

هر سه در CI هم اجرا می‌شوند.

## به‌روزرسانی امنیتی

برای گرفتن آخرین نسخه‌ی یک بسته‌ی مشخص:

```bash
uv pip compile pyproject.toml --python-version 3.12 --generate-hashes \
  --upgrade-package cryptography -o requirements.lock
```

بدون `--upgrade-package`، بازسازی قفل نسخه‌های موجود را نگه می‌دارد و فقط چیزهای
گم‌شده را اضافه می‌کند.

## کار باز: پین کردن تصویر پایه با هضم

`Dockerfile` هنوز `FROM python:3.12-slim` دارد که یک برچسب متحرک است. برای
بازتولیدپذیری کامل باید با هضم پین شود:

```bash
docker pull python:3.12-slim
docker inspect --format='{{index .RepoDigests 0}}' python:3.12-slim
# سپس در Dockerfile:  FROM python:3.12-slim@sha256:<هضم>
```

در محیطی که این قفل ساخته شد، کشیدن تصویر از رجیستری مسدود بود و هضم قابل تأیید
نبود. پین کردن یک هضم تأییدنشده از برچسب هم بدتر است، پس عمداً انجام نشد.
**این کار باید روی سرور تولید، پیش از اولین استقرار، انجام شود** — و از آن پس
به‌روزرسانی تصویر پایه یک تغییر صریح و قابل بازبینی می‌شود، نه اتفاقی که بی‌صدا
در ساخت بعدی می‌افتد.
