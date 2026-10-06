#!/usr/bin/env bash
# پشتیبان پایگاه داده، یک فایل برای هر روز، چهارده روز آخر نگه داشته می‌شود.
#
# روی سرور با cron اجرا می‌شود (docs/SERVER_SETUP.md). فایل پشتیبان پیام‌های واقعی
# دانشجوها را دارد، پس فقط برای صاحبش خواندنی است. نشست‌های تلگرام داخلش رمزنگاری
# شده‌اند و کلیدشان در `.env` است، نه اینجا.
#
# بازگردانی: docs/SERVER_SETUP.md، بخش پشتیبان.
set -euo pipefail

cd "$(dirname "$0")/.."

dest="${BACKUP_DIR:-/root/backups}"
umask 077
mkdir -p "$dest"

out="$dest/mentorai-$(date +%F).dump"
# اول در فایل موقت: پشتیبانِ نیمه‌کاره هرگز اسم پشتیبان سالم را نمی‌گیرد.
trap 'rm -f "$out.tmp"' EXIT
docker compose exec -T db pg_dump -U mentorai -Fc mentorai > "$out.tmp"
mv "$out.tmp" "$out"

find "$dest" -name 'mentorai-*.dump' -mtime +14 -delete
echo "پشتیبان: $out"
