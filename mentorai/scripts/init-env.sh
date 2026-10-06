#!/usr/bin/env bash
# ساخت `.env` از روی `.env.example`، با رمز پایگاه داده و کلید رمزنگاری تازه.
#
# چرا اسکریپت: رمز پایگاه داده باید در دو جا یکی باشد (POSTGRES_PASSWORD و داخل
# DATABASE_URL). دستی نوشتنش رایج‌ترین خطای روز اول است و پیامش هم گمراه‌کننده است:
# «password authentication failed». اینجا هر دو از یک مقدار ساخته می‌شوند.
#
# هیچ رازی چاپ نمی‌شود. فایل فقط برای صاحبش خواندنی است. اگر `.env` از قبل باشد،
# دست نمی‌خورد: بازنویسی کلید رمزنگاری یعنی نشست‌های تلگرامِ ذخیره‌شده دیگر باز
# نمی‌شوند و هر حساب باید دوباره وارد شود.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -e .env ]; then
    echo ".env از قبل وجود دارد و دست نخورد." >&2
    exit 1
fi

# هگز: داخل آدرس پایگاه داده هیچ نویسه‌ای نیاز به رمزگذاری ندارد.
db_password=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
# همان چیزی که Fernet.generate_key() می‌سازد: ۳۲ بایت تصادفی، base64 نشانی‌امن.
fernet_key=$(python3 -c 'import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')

umask 077
sed -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${db_password}|" \
    -e "s|^DATABASE_URL=.*|DATABASE_URL=postgresql+asyncpg://mentorai:${db_password}@db:5432/mentorai|" \
    -e "s|^SESSION_ENCRYPTION_KEY=.*|SESSION_ENCRYPTION_KEY=${fernet_key}|" \
    .env.example > .env

echo "ساخته شد: .env"
echo "رمز پایگاه داده و کلید رمزنگاری پر شدند. بقیه را با «nano .env» پر کنید."
