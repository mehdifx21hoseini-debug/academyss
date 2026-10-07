# راه‌اندازی سرور، قدم‌به‌قدم

از لحظه‌ی خرید سرور تا اولین پیش‌نویس در ربات کنترل. هر دستور این صفحه روی همان
تصویرهای داکری که روی سرور ساخته می‌شوند آزموده شده است، و CI در هر تغییر بخش
پایگاه داده و دانش و پنل را دوباره اجرا می‌کند (گام «Day-one setup» در
`.github/workflows/ci.yml`).

سیستم در **حالت پیش‌نویس** بالا می‌آید: هیچ پیامی بدون تأیید منتور به دانشجو نمی‌رسد.

⚠️ **قانون اول:** رمز سرور، کد ورود تلگرام، رمز دومرحله‌ای و محتوای فایل `.env` را
برای هیچ‌کس نفرستید — از جمله برای من. هر جا لازم است، خودتان روی سرور تایپ می‌کنید.

---

## ۰. پیش از شروع، این‌ها را آماده کنید

| # | چه چیزی | از کجا |
|---|---|---|
| ۱ | IP سرور و رمز root | ایمیل شرکت میزبان |
| ۲ | `api_id` و `api_hash` | my.telegram.org ← ورود با شماره ← API development tools ← ساخت یک app (نام دلخواه، Platform: Desktop). اگر خطا داد، با VPN یا مرورگر دیگری دوباره امتحان کنید |
| ۳ | توکن ربات کنترل | در تلگرام: @BotFather ← `/newbot` ← یک نام و یک نام کاربری که به `bot` ختم شود |
| ۴ | شناسه‌ی عددی منتور و خودتان | هر کدام در تلگرام به @userinfobot پیام بدهند؛ عدد جلوی `Id` |
| ۵ | کلید Anthropic | console.anthropic.com (همان نکته‌ی قبلی درباره‌ی کشورهای پشتیبانی‌شده پابرجاست) |
| ۶ | حضور منتور | برای گام ۱۰ کد ورود به اپ تلگرام منتور می‌آید |
| ۷ | یک حساب تلگرام دیگر برای آزمایش | نه حساب یک دانشجوی واقعی |

همه‌ی دستورهای زیر را در **PowerShell** ویندوز (گام ۱ و ۲) یا روی **سرور** (بقیه)
اجرا کنید. هر بلوک را کامل کپی کنید.

---

## ۱. وصل شدن به سرور

در ویندوز، PowerShell را باز کنید (`IP` را با IP سرور عوض کنید):

```powershell
ssh root@IP
```

بار اول می‌پرسد `Are you sure you want to continue connecting` — بنویسید `yes`. بعد رمز
root را بزنید؛ موقع تایپ چیزی دیده نمی‌شود و طبیعی است.

رمز را عوض کنید:

```bash
passwd
```

## ۲. ورود با کلید به‌جای رمز (پیشنهادی)

رمزی که به هر سرور اینترنتی وصل است، روزی هزاران بار حدس زده می‌شود. کلید این خطر را
از بین می‌برد.

یک **پنجره‌ی جدید** PowerShell باز کنید (روی کامپیوتر خودتان، نه سرور):

```powershell
ssh-keygen -t ed25519
```

سه بار Enter. بعد کلید را روی سرور بگذارید:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@IP "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

آزمایش کنید: `ssh root@IP` باید **بدون رمز** وارد شود. اگر شد، روی سرور ورود با رمز را
خاموش کنید:

```bash
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/00-mentorai.conf
sshd -t && systemctl restart ssh
```

⚠️ پنجره‌ی فعلی را **نبندید**. در یک پنجره‌ی تازه دوباره `ssh root@IP` بزنید. اگر وارد
نشد، در همان پنجره‌ی قبلی برگردانید:

```bash
rm /etc/ssh/sshd_config.d/00-mentorai.conf && systemctl restart ssh
```

💡 این فایل با شماره‌ی `00` عمداً پیش از تنظیم شرکت میزبان (`50-cloud-init.conf`) خوانده
می‌شود؛ روی Ubuntu 24.04 آزموده شد که «رمز روشن» میزبان را کنار می‌زند.

## ۳. به‌روزرسانی و دیوار آتش

```bash
apt update && apt upgrade -y
ufw allow OpenSSH
ufw --force enable
ufw status
```

اگر وسط به‌روزرسانی صفحه‌ای رنگی چیزی پرسید، گزینه‌ی پیش‌فرض را با Enter بپذیرید
(«keep the local version»). اگر آخرش گفت `System restart required`:

```bash
reboot
```

یک دقیقه بعد دوباره `ssh root@IP`.

💡 فقط SSH باز است. پایگاه داده و پنل فقط روی `127.0.0.1` گوش می‌دهند و از بیرون
دیده نمی‌شوند؛ سرویس ویس هیچ درگاهی بیرون ندارد.

## ۴. حافظه‌ی کمکی — فقط روی پلن ۴ گیگ

```bash
swapon --show
```

اگر چیزی چاپ نکرد:

```bash
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
free -h
```

در خروجی `free -h` باید ردیف `Swap` حدود `4.0Gi` باشد.

## ۵. نصب داکر

```bash
curl -fsSL https://get.docker.com | sh
```

سقف حجم لاگ‌ها، وگرنه بعد از چند ماه دیسک پر می‌شود:

```bash
cat > /etc/docker/daemon.json <<'EOF'
{"log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "5"}}
EOF
systemctl restart docker
docker compose version
```

## ۶. گرفتن کد

یک کلید فقط-خواندنی برای همین مخزن می‌سازیم. اگر مخزن را خصوصی کنید (پیشنهاد می‌شود —
پایین را ببینید) همین کلید کار می‌کند و چیزی عوض نمی‌شود.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/academyss -N ""
cat ~/.ssh/academyss.pub
```

خطی که چاپ شد را کپی کنید. در GitHub: مخزن academyss ← **Settings** ← **Deploy keys** ←
**Add deploy key**. عنوان: `server`. متن را بچسبانید. تیک **Allow write access** را
**نزنید**. Add key.

```bash
cat >> ~/.ssh/config <<'EOF'
Host github-academyss
    HostName github.com
    User git
    IdentityFile ~/.ssh/academyss
    IdentitiesOnly yes
EOF
git clone git@github-academyss:mehdifx21hoseini-debug/academyss.git ~/academyss
```

بار اول `yes` بزنید.

⚠️ مخزن الان **عمومی** است: پایگاه دانش (۶۴۳ پرسش و پاسخ روش آکادمی) برای همه
دیده می‌شود. برای خصوصی کردن: Settings ← General ← پایین صفحه ← Change visibility ←
Private.

## ۷. ساختن `.env`

```bash
cd ~/academyss/mentorai
scripts/init-env.sh
```

این اسکریپت رمز پایگاه داده و کلید رمزنگاری نشست را خودش می‌سازد و جای درستش می‌گذارد.
هیچ رازی چاپ نمی‌کند و اگر `.env` از قبل باشد دست نمی‌زند.

حالا بقیه را پر کنید:

```bash
nano .env
```

| خط | چه بنویسید |
|---|---|
| `TELEGRAM_API_ID` | عدد از گام ۰، ردیف ۲ |
| `TELEGRAM_API_HASH` | رشته از همان‌جا |
| `CONTROL_BOT_TOKEN` | توکن BotFather |
| `CONTROL_OPERATOR_IDS` | شناسه‌ی منتور و خودتان، با کاما و بدون فاصله: `111111111,222222222` |
| `ANTHROPIC_API_KEY` | کلید Anthropic |

مدل گفتگو از قبل Anthropic و `claude-sonnet-5-5` است (ارزان و مناسب چت)؛ در `.env`
فقط `AI_MODEL` خالی می‌ماند. اگر خواستید قوی‌ترش را بسنجید، `AI_MODEL=claude-opus-5-5`.

**برای OpenAI** (اختیاری؛ ADR-035): `AI_PROVIDER=openai`، `OPENAI_API_KEY`، نام مدل در
`AI_MODEL`، و قیمت هر میلیون توکن در `AI_PRICE_INPUT_USD` و `AI_PRICE_OUTPUT_USD` از
صفحه‌ی قیمت OpenAI. بدون قیمت، سیستم روشن نمی‌شود: سقف هزینه بدون آن واقعی نیست.
⚠️ داده‌ی دانشجو در این حالت به OpenAI می‌رود، نه Anthropic.

**فقط روی پلن ۴ گیگ** این دو را هم عوض کنید — هر دو باید یکی باشند:

```
TRANSCRIBER_MODEL=large-v3-turbo
WHISPER_MODEL=large-v3-turbo
```

به `POSTGRES_PASSWORD`، `DATABASE_URL` و `SESSION_ENCRYPTION_KEY` دست نزنید. ذخیره:
`Ctrl+O` و Enter، خروج: `Ctrl+X`.

💡 از محتوای `.env` یک نسخه در یک جای امن (مدیر رمز) نگه دارید. اگر
`SESSION_ENCRYPTION_KEY` گم شود، داده‌ها می‌مانند ولی هر حساب باید دوباره وارد شود.

## ۸. پایگاه داده و دانش

```bash
docker compose up -d --wait db
docker compose run --rm cli python -m alembic upgrade head
docker compose run --rm cli mentorai kb-import --file /kb/mentorai_kb_latest.csv
```

بار اول تصویر برنامه ساخته می‌شود و چند دقیقه طول می‌کشد. انتظار در خط آخر:

```
ساخته شد: 643 | به‌روز شد: 0
```

## ۹. ویس

```bash
docker compose --profile voice up -d transcriber
docker compose --profile voice logs -f transcriber
```

بار اول مدل دانلود می‌شود (turbo حدود ۱٫۶ گیگ، large-v3 حدود ۳ گیگ). وقتی خط
`whisper_ready` آمد، با `Ctrl+C` از لاگ بیرون بیایید و بررسی کنید:

```bash
docker compose --profile voice ps transcriber
```

باید `(healthy)` باشد. تا وقتی آماده نشده، ویس‌ها مثل قبل به منتور می‌رسند و چیزی گم
نمی‌شود.

## ۹٫۵. بررسی زنده‌ی مدل هوش مصنوعی

تمام آزمون‌های پروژه با مدل ساختگی‌اند؛ هیچ‌کدام نمی‌گویند کلید و نام مدل درست است و
مدل خروجی را به شکل مورد انتظار برمی‌گرداند. این فرمان هر چهار مسیر را یک بار با ورودی
ساختگی (نه پیام دانشجو) اجرا می‌کند و چند سنت هزینه دارد:

```bash
docker compose run --rm cli mentorai model-check
```

انتظار: چهار ✅ و «همه‌چیز سالم است.» اگر ❌ دیدید، علتش همان‌جا نوشته شده (کلید، نام
مدل، پارامتر نامجاز، یا پاسخ بریده). **پیش از وصل کردن حساب** این را بزنید، و پس از هر
بار عوض کردن ارائه‌دهنده یا مدل دوباره.

## ۱۰. ثبت و ورود حساب منتور

`mentor-a` نامی است که خودتان برای این حساب انتخاب می‌کنید (حروف کوچک لاتین، بدون
فاصله). شماره را با کد کشور بنویسید — خودتان، روی سرور:

```bash
docker compose run --rm cli mentorai add-account --slug mentor-a --mentor-name "نام منتور" --phone "+98912XXXXXXX"
```

⚠️ پیش از ورود به منتور بگویید: بعد از این مرحله تلگرام در گوشی‌اش «ورود تازه» از
آلمان با دستگاه `Desktop` نشان می‌دهد. **آن را Terminate نکند**؛ آن همین سیستم است.

```bash
docker compose run --rm -it cli mentorai login --slug mentor-a
```

پرسش‌ها انگلیسی‌اند:

- `Please enter the code you received:` — کدی که در اپ تلگرام منتور از طرف «Telegram»
  آمده.
- `Please enter your password:` — فقط اگر رمز دومرحله‌ای دارد. موقع تایپ دیده نمی‌شود.

انتظار: `ورود حساب mentor-a انجام شد. نشست رمزنگاری‌شده ذخیره شد.`

⚠️ این دستور را بی‌دلیل تکرار نکنید. ورود مکرر برای تلگرام سیگنال منفی است.

**کسانی که دانشجو نیستند** (همکار، خانواده، پشتیبانی) را می‌شود کنار گذاشت تا برایشان
پیش‌نویس ساخته نشود. در حالت پیش‌نویس فوری نیست — منتور پیش‌نویسشان را رد می‌کند — و
می‌شود کم‌کم اضافه‌شان کرد. شناسه‌ی عددی را خود آن شخص از @userinfobot می‌گیرد:

```bash
docker compose run --rm cli mentorai exclude-chat --slug mentor-a --peer-id 123456789 --reason "همکار"
```

## ۱۱. روشن کردن سیستم

```bash
docker compose up -d app
docker compose logs --tail 30 app
```

⚠️ فقط همین سرویس `app`. هیچ دستور دیگری که به حساب وصل شود (مثل `login`) نباید هم‌زمان
با آن اجرا شود (ADR-020).

💡 سیستم فقط پیام‌هایی را می‌بیند که **بعد از** روشن شدنش می‌رسند. پیام‌های قدیمی
دست نمی‌خورند، و هر چه وقتی خاموش است برسد، مثل همیشه با خود منتور است.

## ۱۲. وصل کردن ربات کنترل

منتور در تلگرام ربات ساخته‌شده در گام ۰ را باز کند، **Start** بزند (ربات جوابی
نمی‌دهد؛ طبیعی است) و بنویسد:

```
/link mentor-a
```

جواب: `این گفتگو به حساب mentor-a وصل شد.` از این لحظه پیش‌نویس‌ها اینجا می‌آیند.

اگر جواب داد `انجام نشد.`، شناسه‌ی منتور در `CONTROL_OPERATOR_IDS` نیست یا اشتباه است
(ربات عمداً دلیل را به ناشناس نمی‌گوید). بعد از اصلاح `.env`:

```bash
docker compose up -d app
```

## ۱۳. آزمایش اول

⚠️ بین ۸ صبح تا ۱۱ شب به وقت تهران آزمایش کنید. در ساعات سکوت هیچ پیامی فرستاده
نمی‌شود، و تأییدی که آن موقع زده شود حدود ده دقیقه بعد رها می‌شود (پایین را ببینید).

از حساب آزمایشی به حساب منتور بفرستید:

| بفرستید | انتظار |
|---|---|
| «دوره مقدماتی چند جلسه است؟» | پیش‌نویس در ربات با ✅ و 🚫. ✅ را بزنید: پاسخ از حساب منتور به حساب آزمایشی می‌رسد |
| یک ویس کوتاه با همان سؤال | پیش‌نویس با برچسب «🎙 ویس دانشجو، رونویسی‌شده» |
| «ربات هستی؟» | **هیچ پیش‌نویسی نمی‌آید** و پیام خوانده‌نشده می‌ماند تا خود منتور جواب دهد |

روی پیش‌نویس سه کار می‌شود کرد:

- ✅ همان را بفرست؛ 🚫 رد.
- ریپلای با متن کامل: همان متن عیناً فرستاده می‌شود.
- ریپلای که با `+` شروع شود، مثلاً `+ بگو از ویدیو ۱۰ شروع کنه`: سیستم کاملش می‌کند و
  **دوباره برای تأیید** می‌فرستد.

## ۱۴. پنل

```bash
docker compose run --rm -it cli mentorai panel-user --username boss --display-name "مدیر" --role admin
docker compose up -d panel
```

رمز پنل حداقل ۱۲ نویسه. پنل فقط از داخل سرور در دسترس است؛ برای دیدنش در ویندوز یک
PowerShell تازه:

```powershell
ssh -L 8000:127.0.0.1:8000 root@IP
```

تا این پنجره باز است، در مرورگر: `http://localhost:8000`. دامنه و HTTPS لازم نیست —
مرورگرها `localhost` را امن حساب می‌کنند و ورود کار می‌کند (آزموده شد).

یک بررسی سریع سلامت، روی سرور:

```bash
curl -s http://127.0.0.1:8000/readyz
```

`{"status":"ok"}` یا `degraded` یعنی کار می‌کند. `down` یعنی کارگر بالا نیست — گام ۱۱.

## ۱۵. پشتیبان روزانه

```bash
(crontab -l 2>/dev/null; echo "30 3 * * * /root/academyss/mentorai/scripts/backup.sh >> /root/backup.log 2>&1") | crontab -
/root/academyss/mentorai/scripts/backup.sh
```

دستور دوم همین الان یک پشتیبان می‌گیرد تا ببینید کار می‌کند. هر شب ساعت ۷ صبح تهران
تکرار می‌شود؛ ۱۴ روز آخر در `/root/backups` می‌ماند.

⚠️ پشتیبان روی همان سرور، در برابر از دست رفتن سرور کمکی نمی‌کند. هفته‌ای یک بار در
PowerShell یک نسخه بیرون بیاورید:

```powershell
scp "root@IP:/root/backups/*.dump" .
```

این فایل پیام‌های واقعی دانشجوها را دارد؛ جای امن نگهش دارید.

بازگردانی (فقط وقتی لازم شد):

```bash
cd ~/academyss/mentorai
docker compose stop app panel
docker compose exec -T db pg_restore -U mentorai -d mentorai --clean --if-exists --no-owner < /root/backups/mentorai-YYYY-MM-DD.dump
docker compose up -d app panel
```

## ۱۶. کارهای روزمره

همه از داخل `~/academyss/mentorai`:

| کار | دستور |
|---|---|
| وضعیت | `docker compose --profile voice ps` |
| لاگ | `docker compose logs --tail 100 app` |
| **قطع فوری ارسال** | `docker compose run --rm cli mentorai pause --slug mentor-a --reason "بررسی"` |
| ادامه‌ی ارسال | `docker compose run --rm cli mentorai pause --slug mentor-a --resume` |
| خاموش کردن کامل | `docker compose stop app` |
| مقایسه‌ی کور مدل‌ها | `docs/MODEL_COMPARISON.md` |
| حافظه | `free -h` و `docker stats --no-stream` |

`pause` بدون راه‌اندازی دوباره اثر می‌کند: ارسال بعدی همان لحظه متوقف می‌شود. دریافت و
ساخت پیش‌نویس ادامه دارد، فقط چیزی نمی‌رود.

اگر تلگرام هشدار محدودیت داد: فوراً `pause`، و تا روشن شدن علت ادامه ندهید.

**به‌روزرسانی کد:**

```bash
cd ~/academyss && git pull
cd mentorai
docker compose build
docker compose run --rm cli python -m alembic upgrade head
docker compose up -d app panel
```

اگر پایگاه دانش هم تغییر کرده:

```bash
docker compose run --rm cli mentorai kb-import --file /kb/mentorai_kb_latest.csv
```

اگر سرویس ویس تغییر کرده: `docker compose --profile voice up -d --build transcriber`.

**ارتقا به پلن ۸ گیگ** (با همان IP): در `.env` هر دو مدل را `large-v3` کنید، بعد:

```bash
docker compose --profile voice up -d transcriber
docker compose up -d app
```

## ۱۷. اگر چیزی کار نکرد

| نشانه | علت | چاره |
|---|---|---|
| لاگ `app` مدام: `هیچ حساب فعال و واردشده‌ای وجود ندارد` | گام ۱۰ انجام نشده | `login` |
| `password authentication failed` | `.env` بعد از ساخت پایگاه داده عوض شده؛ رمز فقط بار اول اعمال می‌شود | رمز قبلی را برگردانید |
| `The input device is not a TTY` | `-it` در جایی بدون ترمینال | همان دستور را مستقیم در SSH بزنید |
| پیش‌نویس نمی‌آید | `/link` زده نشده، یا شناسه در `CONTROL_OPERATOR_IDS` نیست | گام ۱۲؛ در لاگ دنبال `control_chat_not_linked` بگردید |
| ویس رونویسی نمی‌شود | سرویس ویس `healthy` نیست، یا دو نام مدل در `.env` یکی نیستند | گام ۹ |
| ربات می‌گوید «فعلاً ارسال ممکن نیست» | ساعات سکوت ۲۳ تا ۸، `pause`، یا سقف نرخ | صبر یا `--resume` |
| کندی یا خاموش شدن سرویس‌ها روی پلن ۴ گیگ | حافظه کم | `free -h`؛ گام ۴؛ یا ارتقا |

## محدودیتی که از قبل می‌دانیم

تأییدی که در ساعات سکوت (۲۳ تا ۸ تهران) زده شود پنج بار با فاصله‌ی دو دقیقه دوباره
امتحان می‌شود و بعد در وضعیت «شکست‌خورده» می‌ماند. چیزی فرستاده نمی‌شود — جهت امن — ولی
ربات به منتور گفته «دوباره تلاش می‌شود» و بعد از رها شدن خبرش نمی‌دهد. تعدادش در پنل
دیده می‌شود. تا اصلاح، در آن ساعت‌ها منتور خودش جواب بدهد.
