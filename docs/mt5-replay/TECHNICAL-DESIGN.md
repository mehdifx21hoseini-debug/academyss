# SS Replay — Technical Design Document

**پروژه:** ابزار Native Market Replay / Backtesting برای MetaTrader 5
**نسخه سند:** 0.1 (Pre-Implementation)
**وضعیت:** Architecture Review — هیچ کدی تولید نشده است
**تاریخ:** 2026-08-29

---

## ۰. خلاصه مدیریتی و حکم نهایی

**حکم: پروژه از نظر فنی امکان‌پذیر است و معماری‌ای که مطرح کردی در جهت درست است.**

MetaTrader 5 از build 1730 به بعد یک خانواده API به نام `Custom*` دارد
(`CustomSymbolCreate`، `CustomRatesUpdate`، `CustomTicksAdd`، ...) که دقیقاً برای
همین کار ساخته شده: ساختن یک Symbol مصنوعی که ترمینال آن را **مثل یک نماد واقعی**
می‌بیند. یعنی:

- چارت Native است، نه Object و نه Bitmap
- تغییر Timeframe کار می‌کند و توسط خود ترمینال انجام می‌شود
- Indicatorها، Objectها، Templateها، Zoom، Scroll، Crosshair — همه Native
- Future Data به‌صورت **ساختاری** غیرقابل دسترسی است، نه با مخفی‌سازی

این تنها معماری قابل‌قبول برای این پروژه است. هر رویکرد مبتنی بر رسم Object
از پایه شکست‌خورده است چون تغییر Timeframe و Indicatorهای Native را از دست می‌دهد.

### ۵ اصلاح مهم نسبت به طرح اولیه

| # | طرح اولیه | اصلاح پیشنهادی | دلیل |
|---|---|---|---|
| ۱ | Bar Engine حالا، Tick Engine در V2 | **Tick همیشه لایه انتقال است؛ منبع داده می‌تواند Bar یا Tick باشد** | اگر V1 با Bar-append ساخته شود، V2 یک بازنویسی کامل است نه یک افزودن |
| ۲ | همه‌چیز در یک EA | **Core = Service، Panel = Indicator** | EA با تغییر Timeframe عملاً `OnDeinit`/`OnInit` می‌شود و State موتور می‌میرد. Service زنده می‌ماند. Indicator بودن پنل، اسلات EA را برای «Strategy Mode» آینده آزاد می‌گذارد |
| ۳ | Previous Candle به‌عنوان قابلیت پایه و هم‌ارز Next | **Rewind با مدل Snapshot، نه Step-Back ساده** | برگشت به عقب یعنی حذف فیزیکی داده + محاسبه مجدد Indicatorها + Rollback معاملات مجازی. متقارن با Next نیست و باید انتظارات درست تنظیم شود |
| ۴ | Import CSV در «آینده» | **CSV Import در Phase 2، نه Phase 4** | اکثر بروکرها برای CFDها (مثل US30Cash) فقط چند ماه M1 و تقریباً هیچ Tick History ندارند. بدون Import، ابزار برای بک‌تست جدی کور است |
| ۵ | سرعت تا 50x با همان فیدلیتی | **Adaptive Fidelity: سرعت بالا = فیدلیتی پایین‌تر، به‌صورت شفاف و اعلام‌شده** | تزریق Tick واقعی در 50x یعنی ده‌ها هزار Tick بر ثانیه — ترمینال تحمل نمی‌کند. راه‌حل درست، افت کنترل‌شده و قابل‌مشاهده است نه Freeze |

### مهم‌ترین یافته فنی

مبنای ذخیره‌سازی تاریخچه در MT5 **همیشه M1** است و بقیه Timeframeها توسط ترمینال
از روی M1 ساخته می‌شوند. این یعنی:

> برای نمایش ۲۰۰ کندل D1 در چارت، باید حدود **۲۸۸٬۰۰۰ کندل M1** در Custom Symbol
> نوشته شده باشد. (۲۰۰ × ۱۴۴۰)

این تک‌جمله، سنگین‌ترین هزینه Performance پروژه را تعیین می‌کند و باید از روز اول
در طراحی دیده شود — نه بعداً کشف شود.

---

## ۱. بررسی امکان‌پذیری در MT5

### ۱.۱ آنچه قطعاً امکان‌پذیر است

| نیازمندی | مکانیزم Native | وضعیت |
|---|---|---|
| ساخت نماد مصنوعی با مشخصات نماد واقعی | `CustomSymbolCreate(name, path, origin)` | ✅ |
| نوشتن تاریخچه کندل | `CustomRatesUpdate` / `CustomRatesReplace` | ✅ |
| حذف تاریخچه (برای Rewind/Reset) | `CustomRatesDelete` / `CustomTicksDelete` | ✅ |
| تزریق Tick و ساخت طبیعی کندل | `CustomTicksAdd` | ✅ |
| پخش زنده Tick روی چارت | `CustomTicksAdd` (نماد باید در Market Watch باشد) | ✅ |
| خواندن تاریخچه بروکر | `CopyRates` / `CopyTicksRange` | ✅ |
| ساعت Replay | `SymbolInfoInteger(sym, SYMBOL_TIME)` | ✅ |
| کلیک روی کندل → Replay From Here | `OnChartEvent` + `ChartXYToTimePrice` | ✅ |
| تغییر Timeframe بدون خرابی | ترمینال خودش از M1 می‌سازد | ✅ |
| Multi-Chart همگام | همه چارت‌های همان Custom Symbol از یک منبع Tick تغذیه می‌شوند | ✅ رایگان |
| معامله مجازی بدون ارسال به بروکر | منطق داخلی — هیچ `OrderSend`ی وجود ندارد | ✅ |

### ۱.۲ آنچه امکان‌پذیر است اما هزینه دارد

| نیازمندی | واقعیت |
|---|---|
| Previous Candle | نیازمند حذف داده و بازمحاسبه است. کند و همراه با Flicker. |
| سرعت‌های بالا با Tick واقعی | محدود به توان ترمینال. نیازمند Adaptive Fidelity. |
| Tick History قدیمی | وابسته به بروکر. برای CFD/Index معمولاً کم یا ناموجود. |
| History عمیق برای HTF | هزینه دیسک و RAM بالا (بند ۰ را ببین). |

### ۱.۳ آنچه امکان‌پذیر **نیست** — و باید بپذیریم

1. **جلوگیری از دیدن نماد اصلی توسط کاربر.** اگر `US30Cash` در Market Watch یا
   چارت دیگری باز باشد، کاربر قیمت آینده را می‌بیند. این یک محدودیت ترمینال است،
   نه باگ ما. راه‌حل: یک **Profile اختصاصی Replay** که فقط Custom Symbol در آن است،
   به‌علاوه هشدار در پنل.
2. **کنترل Thread ترمینال.** MQL5 چندنخی نیست؛ نمی‌توانیم Prefetch را در پس‌زمینه
   موازی اجرا کنیم. باید در همان حلقه Service به‌صورت Chunk انجام شود.
3. **Rollback رایگان.** MT5 هیچ مکانیزم Snapshot داخلی برای تاریخچه نماد ندارد.
   Rewind را خودمان باید بسازیم.
4. **Tick واقعی برای گذشته دور.** ترمینال Tick را فقط از زمانی دارد که خودش
   دانلود کرده باشد. برای ۵ سال پیش روی یک CFD، عملاً وجود ندارد.

---

## ۲. معماری پیشنهادی

### ۲.۱ جریان اصلی

```
┌─────────────────────────────────────────────────────────┐
│  DATA SOURCES                                           │
│  Broker M1 History │ Broker Ticks │ CSV Import (P2)     │
└───────────────────────────┬─────────────────────────────┘
                            │
                  ┌─────────▼─────────┐
                  │   DATA MANAGER    │  Chunked window loader
                  │  (windowed cache) │  [T-lookback , T+prefetch]
                  └─────────┬─────────┘
                            │
                  ┌─────────▼─────────┐
                  │  TICK NORMALIZER  │  Bar→Tick synthesis  یا  Real ticks
                  │  (single format)  │  خروجی همیشه: MqlTick[]
                  └─────────┬─────────┘
                            │
   ┌────────────┐  ┌────────▼─────────┐
   │ REPLAY     │─▶│     FEEDER       │  Rate-limited, batched
   │ CLOCK      │  │ + Fidelity Policy│  CustomTicksAdd(...)
   │ (authority)│  └────────┬─────────┘
   └────────────┘           │
                  ┌─────────▼─────────┐
                  │  CUSTOM SYMBOL    │  US30Cash.SSR
                  │  (controlled hist)│  هیچ داده‌ای بعد از T ندارد
                  └─────────┬─────────┘
                            │
                  ┌─────────▼─────────┐
                  │  NATIVE MT5 CHART │  ← ترمینال از اینجا به بعد را خودش می‌سازد
                  │  TFs │ Indicators │
                  │  Objects │ Zoom   │
                  └───────────────────┘
```

### ۲.۲ اصلاح کلیدی: Tick به‌عنوان تنها لایه انتقال

طرح اولیه دو موتور جدا داشت (Bar Engine حالا / Tick Engine بعداً). این اشتباه است.

**معماری درست:**

```
منبع داده        →  نرمال‌ساز       →  انتقال
─────────────────────────────────────────────
Real Ticks       →  (بدون تغییر)    →  MqlTick[]  ─┐
M1 Bars          →  Tick Synthesis  →  MqlTick[]  ─┼─▶ CustomTicksAdd
CSV Ticks (P2)   →  Parser          →  MqlTick[]  ─┤
CSV Bars  (P2)   →  Tick Synthesis  →  MqlTick[]  ─┘
```

خروجی همه مسیرها یکی است: آرایه‌ای از `MqlTick`. Feeder فقط یک ورودی می‌شناسد.

**چرا این تصمیم حیاتی است:**

1. `CustomTicksAdd` تنها راهی است که ترمینال کندل را **به‌صورت طبیعی و زنده** بسازد
   و همه چارت‌های باز روی همه Timeframeها را همزمان به‌روز کند.
2. کندل نیمه‌کامل HTF رایگان به‌دست می‌آید. اگر ساعت Replay `10:37` باشد، کندل M15
   ساعت `10:30` باید فقط شامل `10:30–10:37` باشد — با تزریق Tick این خودبه‌خود درست است.
3. اضافه‌کردن Tick Replay واقعی در V2 فقط تعویض منبع داده است، نه تغییر معماری.
4. Indicatorها به‌صورت Native و در زمان درست `OnCalculate` می‌شوند.

**Tick Synthesis از کندل M1** — الگوی ترتیب (مطابق مدل OHLC استاندارد):

- کندل صعودی (`Close ≥ Open`): `Open → Low → High → Close`
- کندل نزولی (`Close < Open`): `Open → High → Low → Close`

این یک **فرض** است و باید صریحاً به کاربر اعلام شود، چون روی نتیجه SL/TP داخل کندل
اثر می‌گذارد. (بخش ۱۸ — تست‌های صداقت را ببین.)

### ۲.۳ اصلاح کلیدی: Service + Indicator به‌جای EA

| گزینه | مشکل |
|---|---|
| همه‌چیز در **Indicator** | نمی‌تواند `Sleep` کند؛ حلقه سنگین، ترمینال را قفل می‌کند |
| همه‌چیز در **EA** | با هر تغییر Timeframe یا Symbol، `OnDeinit`+`OnInit` می‌شود و State می‌میرد. ضمناً اسلات EA چارت را اشغال می‌کند |
| **Service + Indicator** ✅ | Service مستقل از چارت زنده می‌ماند، `Sleep` دارد، Thread خودش را دارد. Indicator فقط View است |

**تقسیم مسئولیت:**

| مؤلفه | جایگاه | مسئولیت |
|---|---|---|
| `SSReplayCore` | **Service** | Clock، Data Manager، Tick Normalizer، Feeder، Custom Symbol، Virtual Account، Stats. **مالک تمام State** |
| `SSReplayPanel` | **Indicator** | رسم پنل، دریافت کلیک، ارسال Command، نمایش State. **بدون State** |
| `SSReplayInstall` / `Cleanup` / `Diag` | **Script** | نصب، پاک‌سازی، تشخیص |

نتیجه مهم: چون تمام State در Service است، **تغییر Timeframe فقط View را ری‌استارت
می‌کند، نه موتور را.** این دقیقاً چیزی است که Requirement شماره «تغییر Timeframe
بدون خرابی Replay» می‌خواهد.

نکته: Service اجازه Trading ندارد — اما ما اصلاً `OrderSend` نداریم، معاملات مجازی‌اند.
پس این محدودیت برای ما بی‌اثر است.

### ۲.۴ کانال ارتباطی (IPC)

MQL5 مکانیزم IPC مستقیم ندارد. طرح پیشنهادی، دو کاناله:

**کانال فرمان و State داغ — Terminal Global Variables** (بدون DLL، سریع، اتمیک نسبی)

```
SSR.<slot>.cmd.seq      ← شماره ترتیب فرمان (آخرین چیزی که نوشته می‌شود)
SSR.<slot>.cmd.op       ← کد عملیات
SSR.<slot>.cmd.a1..a3   ← آرگومان‌ها (datetime و double هر دو در double جا می‌شوند)

SSR.<slot>.st.time      ← Replay Time فعلی
SSR.<slot>.st.state     ← Idle / Loading / Playing / Paused / Error
SSR.<slot>.st.speed
SSR.<slot>.st.progress
SSR.<slot>.st.fidelity
SSR.<slot>.st.health
```

قاعده ضد-Race: **همیشه آرگومان‌ها اول نوشته شوند، `seq` آخر.** خواننده فقط وقتی
`seq` تغییر کرد، آرگومان‌ها را می‌خواند.

**کانال داده سنگین — فایل JSON در Common Folder**

```
Files/Common/SSReplay/<slot>/session.json    پیکربندی جلسه
Files/Common/SSReplay/<slot>/journal.json    ژورنال معاملات
Files/Common/SSReplay/<slot>/stats.json      آمار
Files/Common/SSReplay/<slot>/log.txt
```

نوشتن اتمیک: نوشتن در `*.tmp` سپس Rename.

---

## ۳. Custom Symbol — بررسی و محدودیت‌ها

### ۳.۱ ساخت و پیکربندی

```
CustomSymbolCreate("US30Cash.SSR", "SSReplay\\", "US30Cash")
```

پارامتر سوم (`origin_symbol`) تمام مشخصات نماد واقعی را کپی می‌کند: `Digits`،
`Point`، `TickSize`، `TickValue`، `ContractSize`، `VolumeMin/Max/Step`،
`MarginInitial`، ... . این برای درست بودن محاسبه Lot و P/L در شبیه‌ساز معاملات
**ضروری** است و نباید دستی مقداردهی شود.

مواردی که بعد از ساخت باید صریحاً تنظیم شوند:

| Property | مقدار | چرا |
|---|---|---|
| `SYMBOL_SELECT` | `true` | `CustomTicksAdd` فقط برای نمادهای داخل Market Watch پخش زنده می‌کند |
| `SYMBOL_SPREAD_FLOAT` | `true` | اسپرد از `Ask-Bid` هر Tick محاسبه شود |
| `SYMBOL_TRADE_MODE` | `DISABLED` | جلوگیری از ارسال تصادفی سفارش واقعی |
| Session Quote / Trade | ۲۴/۷ | جلوگیری از حذف Tickهای خارج از سشن توسط ترمینال ⚠️ نیازمند Spike Test |
| `SYMBOL_PATH` | `SSReplay\` | گروه‌بندی و تمیز ماندن Market Watch |

### ۳.۲ محدودیت‌های واقعی Custom Symbol

| محدودیت | اثر | راهکار |
|---|---|---|
| طول نام نماد محدود (≈۳۱ کاراکتر) | نام‌های ترکیبی طولانی رد می‌شوند | قرارداد نام‌گذاری کوتاه: `<SRC>.SSR<slot>` با کوتاه‌سازی خودکار `<SRC>` |
| مبنای ذخیره‌سازی **فقط M1** | نمی‌توان HTF را مستقیم تزریق کرد | همه‌چیز از M1/Tick ساخته می‌شود؛ عمق Seed باید بر اساس بالاترین TF محاسبه شود |
| حذف نماد وقتی چارت باز است ناموفق است | خطای Cleanup | تخریب مرتب: بستن چارت‌ها → حذف از Market Watch → `CustomSymbolDelete` |
| تاریخچه روی دیسک می‌ماند (`bases\Custom\`) | رشد فضای دیسک | ابزار Cleanup + نمایش حجم مصرفی در پنل |
| نماد Custom در Strategy Tester رفتار متفاوتی دارد | خارج از Scope V1 | صراحتاً خارج از Scope اعلام شود |
| Tickهای تزریقی تاریخچه دائمی می‌سازند | Reset باید واقعاً پاک کند | `CustomTicksDelete` + `CustomRatesDelete` روی بازه |

### ۳.۳ استراتژی چند-جلسه‌ای

یک Custom Symbol به‌ازای هر **(نماد منبع، Slot)**. `slot` پیش‌فرض `1`.
این اجازه می‌دهد بعداً Multi-Symbol Replay و چند جلسه موازی بدون تغییر معماری
اضافه شود، بدون اینکه در V1 پیچیدگی اضافه کند.

---

## ۴. دریافت History از بروکر

### ۴.۱ مکانیزم

```
SymbolSelect("US30Cash", true)
CopyRates("US30Cash", PERIOD_M1, from, to, rates[])
```

### ۴.۲ نکته‌ای که اکثر پیاده‌سازی‌ها اشتباه می‌کنند

`CopyRates` **همگام نیست**. اولین فراخوانی معمولاً `-1` یا تعداد ناقص برمی‌گرداند
چون ترمینال هنوز در حال دانلود از سرور است. الگوی درست:

```
تا وقتی timeout نشده:
    اگر SeriesInfoInteger(sym, PERIOD_M1, SERIES_SYNCHRONIZED) درست بود
       و CopyRates تعداد کافی برگرداند → موفق
    وگرنه Sleep(200) و دوباره
```

`Sleep` فقط در Service/EA مجاز است — یکی دیگر از دلایل اینکه Core باید Service باشد.

### ۴.۳ Load More History

پنل باید بتواند بپرسد «بروکر برای این نماد چقدر داده دارد؟»:

- `SeriesInfoInteger(sym, PERIOD_M1, SERIES_FIRSTDATE)` → قدیمی‌ترین تاریخ موجود
- `SeriesInfoInteger(sym, PERIOD_M1, SERIES_SERVER_FIRSTDATE)` → قدیمی‌ترین تاریخ روی سرور

اگر `SERVER_FIRSTDATE < FIRSTDATE`، یعنی داده بیشتری قابل دانلود است.
دکمه `[ Load More History ]` باعث `CopyRates` روی بازه قدیمی‌تر می‌شود که ترمینال
را وادار به دانلود می‌کند.

**واقعیت تلخ:** برای CFDها و شاخص‌ها مثل `US30Cash`، اکثر بروکرها فقط چند ماه تا
چند سال M1 دارند. این تنها دلیلی است که CSV Import باید در Phase 2 باشد نه Phase 4.

### ۴.۴ محاسبه عمق Seed مورد نیاز

| بالاترین TF مورد نیاز | تعداد کندل هدف | M1 لازم | حجم تقریبی |
|---|---|---|---|
| M15 | 500 | 7,500 | ناچیز |
| H1  | 500 | 30,000 | کم |
| H4  | 500 | 120,000 | متوسط |
| D1  | 200 | 288,000 | سنگین |
| D1  | 500 | 720,000 | خیلی سنگین |

پنل باید این را به‌صورت یک انتخاب صریح به کاربر بدهد:
**«حداکثر Timeframe مورد نیاز»** → و عمق Seed را خودکار حساب کند و هزینه‌اش را
قبل از شروع نشان دهد. این از «چرا لود ۴ دقیقه طول کشید؟» جلوگیری می‌کند.

---

## ۵. دریافت Tick Data

### ۵.۱ مکانیزم

```
CopyTicksRange(symbol, ticks[], COPY_TICKS_ALL, from_msc, to_msc)
```

- `COPY_TICKS_INFO` — فقط تغییرات Bid/Ask
- `COPY_TICKS_TRADE` — فقط معاملات (Last/Volume)
- `COPY_TICKS_ALL` — همه

برای Replay قیمتی، `COPY_TICKS_INFO` کافی و سبک‌تر است. برای نمادهایی که
Volume واقعی دارند، `ALL`.

### ۵.۲ محدودیت‌ها

| موضوع | وضعیت |
|---|---|
| حجم برگشتی هر فراخوانی | محدود ⚠️ نیازمند Spike Test — باید صفحه‌بندی دفاعی نوشته شود |
| دسترسی تاریخی | فقط از زمانی که ترمینال Tick را دانلود کرده |
| CFD / Index | معمولاً Tick History بسیار محدود یا ناموجود |
| Forex Major | معمولاً بهتر، ولی همچنان محدود به بروکر |
| حجم داده | یک روز Tick برای یک نماد فعال می‌تواند صدها هزار رکورد باشد |

### ۵.۳ استراتژی سه‌سطحی فیدلیتی

به‌جای «یا Tick داریم یا نداریم»، سه سطح تعریف می‌کنیم — دقیقاً هم‌راستا با
مدل‌های شناخته‌شده Strategy Tester خود MT5:

| سطح | منبع | کاربرد |
|---|---|---|
| **F1 — Real Tick** | Tick واقعی بروکر | دقیق‌ترین. برای اسکالپ و تست SL/TP داخل کندل |
| **F2 — Synthetic Tick** | M1 → ۴ تا N تیک | پیش‌فرض. حس زنده دارد، OHLC دقیقاً واقعی است |
| **F3 — Bar Close** | یک تیک در بسته‌شدن هر کندل | سرعت‌های بالا و Fast-Forward |

موتور به‌صورت خودکار بر اساس سرعت انتخابی و در دسترس بودن داده بین این‌ها جابه‌جا
می‌شود، و **سطح فعلی همیشه روی پنل نمایش داده می‌شود.** کاربر هیچ‌وقت نباید ندانَد
که در حال دیدن داده تقریبی است.

---

## ۶. ساخت Replay Timeline

### ۶.۱ Replay Clock به‌عنوان تنها مرجع زمان

**قاعده سخت معماری:**

> هیچ ماژولی حق ندارد `TimeCurrent()` یا `TimeLocal()` را برای منطق Replay صدا بزند.
> تنها منبع زمان، `ReplayClock::Now()` است.

نقض این قاعده رایج‌ترین علت نشت Future Data در ابزارهای مشابه است.

### ۶.۲ مدل زمانی

```
wall_clock  ── زمان واقعی سیستم (فقط برای محاسبه گام)
replay_time ── زمان مجازی بازار (مرجع همه‌چیز)
speed       ── نسبت replay_time به wall_clock

هر iteration در Service:
    dt_wall   = now - last_iteration
    dt_replay = dt_wall × speed
    target    = replay_time + dt_replay
    ticks     = DataWindow.Fetch(replay_time , target)
    Feeder.Inject(ticks)          ← یک فراخوانی Batch
    replay_time = target
    Sleep(adaptive)
```

نکته: `replay_time` مستقل از تعداد Tick جلو می‌رود. یعنی در ساعات کم‌حجم بازار
(مثلاً نیمه‌شب) Replay سریع‌تر حس نمی‌شود و از نظر زمانی درست است — برخلاف
ابزارهایی که «کندل به کندل» می‌روند.

### ۶.۳ ساعت Replay از دید MQL5

بعد از تزریق Tick، `SymbolInfoInteger("US30Cash.SSR", SYMBOL_TIME)` برابر زمان
آخرین Tick تزریق‌شده است. یعنی **Indicatorها و EAهای کاربر به‌صورت Native زمان
درست را می‌بینند** بدون هیچ کد اضافه‌ای. این یک برد بزرگ برای «Strategy Mode» آینده است.

### ۶.۴ Jump / Fast-Forward

| عملیات | روش |
|---|---|
| **پرش رو به جلو** | حالت Bulk: نوشتن مستقیم بازه با `CustomRatesUpdate` (بدون رندر Tick)، سپس ادامه استریم عادی. بسیار سریع‌تر از تزریق Tick |
| **پرش رو به عقب** | حذف Tail: `CustomTicksDelete(sym, target, INF)` + `CustomRatesDelete` + بازنشانی Clock + Rollback حساب مجازی |
| **Reset** | بازسازی کامل Custom Symbol از صفر — امن‌ترین مسیر |

---

## ۷. جلوگیری از نمایش Future Data

این بخش، هسته «صداقت» ابزار است. رویکرد ما **ساختاری** است نه بصری:

> داده آینده نه مخفی می‌شود، بلکه **اصلاً وجود ندارد.**

### ۷.۱ بردارهای نشت و پوشش آن‌ها

| # | بردار نشت | پوشش | ضمانت |
|---|---|---|---|
| ۱ | تاریخچه Custom Symbol بعد از T | هرگز نوشته نمی‌شود؛ در Reset با `CustomRatesDelete(T, INF)` پاک می‌شود | ✅ ساختاری |
| ۲ | اسکرول به راست چارت | ترمینال کندلی که وجود ندارد نمی‌سازد | ✅ ساختاری |
| ۳ | تغییر Timeframe | همه TFها از همان M1 محدود ساخته می‌شوند | ✅ ساختاری |
| ۴ | `TimeCurrent()` در Indicator کاربر | `SYMBOL_TIME` نماد Replay درست است | ✅ ساختاری |
| ۵ | نماد اصلی در Market Watch | ❌ قابل جلوگیری نیست | ⚠️ Profile اختصاصی + هشدار پنل |
| ۶ | چارت باز روی نماد اصلی | ❌ قابل جلوگیری نیست | ⚠️ تشخیص و هشدار در پنل |
| ۷ | Indicator کاربر که مستقیم `CopyRates("US30Cash")` می‌زند | ❌ | ⚠️ مستندسازی؛ در Strategy Mode بررسی می‌شود |
| ۸ | Object/Template حاوی خطوط رسم‌شده روی داده آینده | ⚠️ | هشدار موقع بارگذاری Template |

### ۷.۲ Guard خودکار

پنل در هر بار شروع جلسه باید بررسی کند:

- آیا نماد منبع در Market Watch است؟ → پیشنهاد حذف
- آیا چارتی روی نماد منبع باز است؟ → هشدار قرمز
- آیا Profile فعلی «Replay» است؟ → پیشنهاد سوییچ

این‌ها اجباری نیستند، اما **باید دیده شوند.** یک ابزار بک‌تست که سکوت می‌کند،
به کاربرش دروغ می‌گوید.

---

## ۸. مدیریت Timeframeها

### ۸.۱ چرا این مسئله در معماری ما «حل‌شده» است

چون MT5 همه Timeframeها را از M1 می‌سازد و Custom Symbol ما فقط تا لحظه T داده
دارد، تغییر Timeframe **به‌صورت خودکار** درست کار می‌کند. هیچ کدی برای این لازم نیست.

### ۸.۲ کندل نیمه‌کامل HTF — نقطه‌ای که ابزارهای دیگر خراب می‌کنند

اگر `replay_time = 10:37` باشد:

| TF | کندل جاری | باید شامل باشد |
|---|---|---|
| M5 | 10:35 | 10:35 → 10:37 |
| M15 | 10:30 | 10:30 → 10:37 |
| H1 | 10:00 | 10:00 → 10:37 |
| H4 | 08:00 | 08:00 → 10:37 |

با تزریق Tick این خودبه‌خود درست است. با Bar-append هم درست است اما با
گرانولاریتی دقیقه. این تفاوت، دلیل دوم انتخاب Tick به‌عنوان لایه انتقال است.

### ۸.۳ آنچه باید مدیریت شود

| موضوع | راهکار |
|---|---|
| باز شدن چارت جدید روی TF بالاتر که Seed کافی ندارد | تشخیص و پیشنهاد `Load More History` |
| کاربر TF را به چیزی می‌برد که کاملاً خالی است | پیام واضح در پنل، نه چارت خالی و مبهم |
| `Max bars in chart` ترمینال کم تنظیم شده | تشخیص و راهنمایی در Install Script |
| Indicator سنگین که با هر Tick بازمحاسبه می‌شود | خارج از کنترل ما — مستندسازی |

---

## ۹. هماهنگی با Native Chart

### ۹.۱ چه چیزی رایگان کار می‌کند

Zoom، Scroll، Crosshair، Objects، Templates، Navigation، Indicators، Change Period،
Chart Shift، Data Window — **همه بدون یک خط کد**، چون چارت واقعاً Native است.

### ۹.۲ چه چیزی باید مدیریت شود

| موضوع | راهکار |
|---|---|
| Auto-Scroll هنگام Play | `CHART_AUTOSCROLL = true` به‌صورت پیش‌فرض |
| کاربر عقب اسکرول می‌کند و چارت می‌پرد جلو | تشخیص اسکرول دستی → خاموش‌کردن Auto-Scroll → دکمه `[Follow]` برای بازگشت |
| `ChartRedraw` در سرعت بالا | فقط در سطح Panel و با نرخ محدود (مثلاً ۱۰ بار در ثانیه)، نه به‌ازای هر Tick |
| کلیک روی کندل | `OnChartEvent(CHARTEVENT_CLICK)` → `ChartXYToTimePrice` → زمان کندل |
| Marker روی چارت | Object با نام رزرو‌شده `SSR_MARKER_*` + `CHARTEVENT_OBJECT_CLICK` |
| Multi-Chart | همه چارت‌های همان Custom Symbol خودکار همگام‌اند — رایگان |

### ۹.۳ قاعده طلایی

> Replay Engine هرگز نباید چارت را دستکاری کند، مگر برای Auto-Scroll.
> هیچ Object قیمتی، هیچ Bitmap، هیچ رسم دستی کندل.

---

## ۱۰. معماری Performance

### ۱۰.۱ سه گلوگاه واقعی

| گلوگاه | علت | راهکار |
|---|---|---|
| **G1 — نرخ تزریق Tick** | `CustomTicksAdd` باید به همه چارت‌های باز پخش شود | Batch کردن، Rate Limiting، Adaptive Fidelity |
| **G2 — Seed اولیه عمیق** | ۲۸۸ هزار کندل M1 برای ۲۰۰ کندل D1 | نوشتن Chunk-ای با Progress Bar؛ Seed یک‌بار و Cache شدن |
| **G3 — بازمحاسبه Indicator در Rewind** | حذف داده = بازمحاسبه کامل | Rewind را نادر و صریح نگه داریم؛ Batch کردن چند گام |

### ۱۰.۲ Adaptive Fidelity — قلب راهکار Performance

```
سرعت      فیدلیتی پیش‌فرض      تیک بر کندل M1
──────────────────────────────────────────────
0.25x–2x   F1 (Real) یا F2      همه / 4–20
5x–10x     F2                   4
25x        F3                   1
50x+       F3 + Bulk Write      1 (بدون رندر Tick)
```

قاعده: **هرگز Freeze نمی‌کنیم؛ به‌جایش فیدلیتی را پایین می‌آوریم و اعلام می‌کنیم.**

### ۱۰.۳ مدیریت حافظه

MQL5 چندنخی نیست، پس Prefetch باید داخل همان حلقه Service انجام شود:

```
پنجره داده در RAM:  [ T − lookback , T + prefetch ]
                       │                     │
                       │                     └─ وقتی cursor از watermark رد شد،
                       │                        chunk بعدی در همان iteration لود شود
                       └─ chunkهای قدیمی‌تر آزاد شوند
```

هیچ‌وقت کل تاریخچه در آرایه لود نمی‌شود.

### ۱۰.۴ بودجه Performance (اهداف قابل اندازه‌گیری)

این اعداد باید در Phase 0 اندازه‌گیری و به‌عنوان Regression Threshold ثبت شوند:

| متریک | هدف |
|---|---|
| زمان Seed برای ۱۰۰ هزار کندل M1 | < ۲۰ ثانیه |
| نرخ تزریق پایدار Tick | ≥ ۲۰۰۰ tick/s بدون افت UI |
| تأخیر پاسخ پنل به کلیک | < ۱۰۰ ms در هر سرعتی |
| مصرف RAM موتور | < ۳۰۰ MB در جلسه معمول |
| گام Step Forward | < ۵۰ ms |
| گام Step Back | < ۵۰۰ ms |
| CPU در سرعت 1x | < ۵٪ یک هسته |

---

## ۱۱. محدودیت‌های واقعی MQL5 / MT5

| # | محدودیت | اثر بر پروژه |
|---|---|---|
| ۱ | MQL5 چندنخی نیست | Prefetch و Seed باید Chunk-ای و درون حلقه باشند |
| ۲ | Indicator نمی‌تواند `Sleep` کند | Core نمی‌تواند Indicator باشد |
| ۳ | EA با تغییر TF ری‌استارت می‌شود | Core نمی‌تواند EA باشد |
| ۴ | Service به چارت و رویدادهای چارت دسترسی ندارد | نیاز به معماری دوتکه + IPC |
| ۵ | Service اجازه Trading ندارد | بی‌اثر — معاملات ما مجازی است |
| ۶ | مبنای تاریخچه فقط M1 است | عمق Seed برای HTF گران است |
| ۷ | `CustomTicksAdd` فقط برای نماد داخل Market Watch پخش می‌کند | نماد باید Select شود |
| ۸ | Global Variable فقط `double` است | فرمان‌های پیچیده از مسیر فایل |
| ۹ | طول نام نماد محدود است | قرارداد نام‌گذاری کوتاه |
| ۱۰ | `CopyRates` ناهمگام است | الگوی Retry با `SERIES_SYNCHRONIZED` |
| ۱۱ | Tick History وابسته به بروکر | نیاز به F2/F3 و CSV Import |
| ۱۲ | تغییر رفتار `Custom*` بین Buildها | تست سازگاری در CI دستی |
| ۱۳ | حذف نماد با چارت باز ناموفق است | تخریب مرتب |
| ۱۴ | `Max bars in chart` سقف نمایش دارد | تنظیم در Install |

---

## ۱۲. ریسک‌های فنی

| # | ریسک | احتمال | شدت | کاهش |
|---|---|---|---|---|
| R1 | نرخ پخش `CustomTicksAdd` کمتر از نیاز باشد | متوسط | **بحرانی** | **Spike Test اول Phase 0.** اگر شکست خورد، F3 + Bulk Write مسیر اصلی می‌شود |
| R2 | تنظیمات Session باعث حذف Tick شود | متوسط | بالا | Spike Test؛ تنظیم ۲۴/۷ |
| R3 | Tick History بروکر برای US30Cash تقریباً صفر باشد | **بالا** | متوسط | F2 پیش‌فرض؛ CSV Import در P2 |
| R4 | Seed عمیق ترمینال را چند دقیقه قفل کند | متوسط | بالا | Chunk + Progress + Cache |
| R5 | Rewind با Indicator سنگین غیرقابل استفاده شود | متوسط | متوسط | Batch کردن گام‌ها؛ محدودیت اعلام‌شده |
| R6 | Race در IPC → فرمان گم یا دوباره اجرا شود | متوسط | متوسط | الگوی seq-last + Idempotent commands |
| R7 | Build جدید MT5 رفتار `Custom*` را عوض کند | پایین | بالا | تست رگرسیون؛ نسخه MT5 پشتیبانی‌شده اعلام شود |
| R8 | رشد بی‌کنترل دیسک | متوسط | پایین | نمایش حجم + Cleanup |
| R9 | ناهماهنگی Timezone در Import CSV | بالا (در P2) | متوسط | تعیین صریح TZ و Offset در Import Wizard |
| R10 | کاربر نماد اصلی را باز بگذارد و بک‌تستش بی‌اعتبار شود | بالا | متوسط | Guard و هشدار فعال |
| R11 | ابهام SL/TP داخل کندل در F2/F3 | قطعی | **بالا** | فرض بدبینانه (SL اول) + برچسب صریح روی هر معامله |

**R11 توضیح بیشتر:** اگر یک کندل هم SL و هم TP را لمس کند، در حالت F2/F3
نمی‌دانیم کدام اول بوده. ابزارهای غیرصادق TP را حساب می‌کنند. ما باید:
۱) فرض بدبینانه بگیریم (SL اول)، ۲) آن معامله را در ژورنال با برچسب
`ambiguous` علامت بزنیم، ۳) در آمار، درصد معاملات مبهم را نشان دهیم.
این تفاوت بین یک ابزار آموزشی واقعی و یک اسباب‌بازی است.

---

## ۱۳. معماری نهایی پیشنهادی

### ۱۳.۱ لایه‌بندی با جهت وابستگی سخت

```
┌──────────────────────────────────────────────┐
│ L5  STRATEGY  (SS Strategy — plugin, V3)     │  ← هرگز داخل Core
├──────────────────────────────────────────────┤
│ L4  UI        Panel, Controls, Theme          │
├──────────────────────────────────────────────┤
│ L3  APP       Session, Commands, Orchestrator │
├──────────────────────────────────────────────┤
│ L2  DOMAIN    Clock, Feeder, VirtualAccount,  │
│               RiskEngine, StatsEngine          │
├──────────────────────────────────────────────┤
│ L1  DATA      HistoryLoader, TickSource,       │
│               Normalizer, DataWindow, CSV      │
├──────────────────────────────────────────────┤
│ L0  PLATFORM  CustomSymbol, ChartAdapter,      │
│               IPC, FileStore, Log, Time        │
└──────────────────────────────────────────────┘

قاعده: وابستگی فقط رو به پایین. L0 هیچ‌چیز بالاتر را نمی‌شناسد.
```

**دلیل این لایه‌بندی:** فهرست ماژول‌های اولیه‌ات (Replay Engine، Data Manager،
Chart Manager، ...) درست بود اما لایه‌ها را قاطی می‌کرد. با این تفکیک:

- تست‌پذیری: L1/L2 بدون ترمینال قابل تست‌اند
- `SS Strategy` در L5 است و هرگز به Core نفوذ نمی‌کند (خواسته صریح خودت)
- تعویض منبع داده (بروکر ↔ CSV) فقط L1 را عوض می‌کند
- تعویض UI هیچ اثری روی موتور ندارد

### ۱۳.۲ سطح API هسته (مفهومی، نه کد)

**فرمان‌ها:**
`CREATE_SESSION` · `SET_START(time)` · `PLAY` · `PAUSE` · `STEP_FWD(n)` ·
`STEP_BACK(n)` · `SET_SPEED(x)` · `SET_FIDELITY(f)` · `JUMP_TO(time)` ·
`RESET` · `LOAD_MORE_HISTORY(bars)` · `SAVE_SESSION` · `LOAD_SESSION(id)` ·
`SHUTDOWN`
*(V2+: `ORDER_OPEN` · `ORDER_MODIFY` · `ORDER_CLOSE` · `CLOSE_PARTIAL`)*

**State منتشرشده:**
`replay_time` · `state` · `speed` · `fidelity` · `cursor` · `total` ·
`symbol` · `warmup_from` · `data_health` · `disk_usage` · `last_error`

هر فرمان باید **Idempotent** باشد نسبت به `seq` تا Race باعث اجرای دوباره نشود.

---

## ۱۴. ساختار پوشه و ماژول

```
MQL5/
├── Services/SSReplay/
│   └── SSReplayCore.mq5              نقطه ورود موتور
│
├── Indicators/SSReplay/
│   └── SSReplayPanel.mq5             نقطه ورود پنل
│
├── Scripts/SSReplay/
│   ├── SSReplayInstall.mq5           بررسی محیط، تنظیمات ترمینال
│   ├── SSReplayCleanup.mq5           حذف نمادها و داده‌ها
│   └── SSReplayDiag.mq5              تشخیص و گزارش وضعیت
│
├── Include/SSReplay/
│   ├── Platform/                     L0
│   │   ├── CustomSymbolManager.mqh
│   │   ├── SymbolSpec.mqh
│   │   ├── ChartAdapter.mqh
│   │   ├── Ipc/  Channel.mqh · CommandQueue.mqh · StateBus.mqh
│   │   ├── FileStore.mqh · Json.mqh
│   │   └── Log.mqh · TimeUtil.mqh · Assert.mqh
│   │
│   ├── Data/                         L1
│   │   ├── HistoryLoader.mqh
│   │   ├── TickSource.mqh · BarSource.mqh
│   │   ├── TickNormalizer.mqh        Bar → Tick synthesis
│   │   ├── DataWindow.mqh            پنجره چرخشی + prefetch
│   │   └── Import/ CsvBarImporter.mqh · CsvTickImporter.mqh   (P2)
│   │
│   ├── Domain/                       L2
│   │   ├── ReplayClock.mqh           ★ تنها مرجع زمان
│   │   ├── Feeder.mqh
│   │   ├── FidelityPolicy.mqh
│   │   ├── RateLimiter.mqh
│   │   ├── Snapshot.mqh              برای Rewind
│   │   ├── Trading/  VirtualAccount.mqh · VirtualOrder.mqh
│   │   │             VirtualPosition.mqh · ExecutionModel.mqh
│   │   │             RiskEngine.mqh                            (P3)
│   │   └── Stats/    StatsEngine.mqh · Metrics.mqh · Exporter.mqh  (P3)
│   │
│   ├── App/                          L3
│   │   ├── Session.mqh · SessionStore.mqh
│   │   ├── Orchestrator.mqh
│   │   └── Commands.mqh
│   │
│   ├── Ui/                           L4
│   │   ├── Panel.mqh · Theme.mqh · Layout.mqh
│   │   └── Controls/ Button.mqh · Slider.mqh · Label.mqh
│   │                 DateTimePicker.mqh · ProgressBar.mqh
│   │
│   └── Strategy/                     L5  (V3 — plugin)
│       └── IStrategyHook.mqh
│
└── Files/SSReplay/
    ├── sessions/ · journals/ · exports/ · imports/ · logs/
```

---

## ۱۵. Roadmap

### Phase 0 — Spike Tests  ⚠️ اجباری، قبل از هر کد محصولی

هدف: تبدیل ۶ فرض ناشناخته به عدد اندازه‌گیری‌شده.
خروجی: گزارش امکان‌سنجی + اعداد Performance. **بدون کد محصولی.**

| # | Spike | سؤالی که باید جواب بگیرد |
|---|---|---|
| S1 | نرخ `CustomTicksAdd` | چند Tick بر ثانیه بدون افت UI؟ سقف هر فراخوانی چقدر است؟ |
| S2 | رفتار Session | آیا Tick خارج از سشن حذف می‌شود؟ تنظیم ۲۴/۷ حلش می‌کند؟ |
| S3 | `CustomRatesUpdate` با TF غیر M1 | پذیرفته می‌شود؟ ترمینال چطور HTF می‌سازد؟ |
| S4 | صفحه‌بندی `CopyTicksRange` | سقف واقعی هر فراخوانی؟ |
| S5 | زمان Seed | نوشتن ۱۰۰ هزار و ۵۰۰ هزار کندل M1 چقدر طول می‌کشد؟ |
| S6 | هزینه Rewind | حذف Tail + بازمحاسبه با ۳ Indicator چقدر طول می‌کشد؟ |
| S7 | حیات Service | آیا Service با بسته شدن چارت و تغییر Profile زنده می‌ماند؟ |
| S8 | Tick History بروکر | برای `US30Cash` واقعاً چقدر Tick موجود است؟ |

### Phase 1 — MVP
موتور Replay کامل و صادق، بدون معامله.

### Phase 2 — داده و ناوبری
Tick واقعی، Rewind، Jump، Load More History، CSV Import، Save/Resume Session.

### Phase 3 — شبیه‌ساز معاملات و آمار
Virtual Trading کامل، Risk Engine، Statistics، Journal، Export.

### Phase 4 — قابلیت‌های حرفه‌ای
Blind / Random / Auto-Pause / Multi-Chart / Multi-Symbol / Replay History.

### Phase 5 — SS Strategy
Plugin در L5 روی API پایدار Core.

---

## ۱۶. تعریف MVP

**تعریف موفقیت MVP:**

> کاربر روی `US30Cash` تاریخ `2026.08.27 09:30` را انتخاب می‌کند، Play می‌زند،
> بازار جلو می‌رود، کندل‌ها زنده ساخته می‌شوند، او Timeframe را از M5 به H1 و
> برمی‌گرداند، اسکرول و زوم می‌کند، یک Moving Average می‌اندازد — و **در هیچ لحظه‌ای
> حتی یک کندل از آینده نمی‌بیند.**

### داخل MVP

| ✅ | مورد |
|---|---|
| ✅ | یک نماد، یک جلسه |
| ✅ | Custom Symbol با کپی مشخصات از نماد مبدأ |
| ✅ | Seed از M1 بروکر با Progress و عمق قابل تنظیم |
| ✅ | فیدلیتی F2 (Synthetic Tick) به‌عنوان پیش‌فرض |
| ✅ | Play / Pause / Next Candle / Reset / Restart |
| ✅ | Speed: 0.25x تا 10x با Adaptive Fidelity |
| ✅ | انتخاب تاریخ و ساعت از پنل |
| ✅ | Replay From Here با کلیک روی کندل |
| ✅ | نمایش Replay Time و State و Fidelity |
| ✅ | تغییر Timeframe بدون خرابی |
| ✅ | Auto-Scroll هوشمند + دکمه Follow |
| ✅ | Guard نشت داده + هشدارها |
| ✅ | معماری Service + Indicator + IPC |
| ✅ | Install / Cleanup / Diag |

### خارج از MVP (به‌صورت صریح)

| ❌ | مورد | مقصد |
|---|---|---|
| ❌ | Previous Candle / Rewind | P2 |
| ❌ | Tick واقعی | P2 |
| ❌ | Jump To Date | P2 |
| ❌ | Load More History | P2 |
| ❌ | CSV Import | P2 |
| ❌ | Save / Resume Session | P2 |
| ❌ | هر نوع معامله | P3 |
| ❌ | آمار | P3 |
| ❌ | Multi-Chart / Multi-Symbol | P4 |
| ❌ | SS Strategy | P5 |

**قاعده MVP:** MVP باید **کوچک اما بی‌نقص** باشد. یک Replay صادق و روان
بدون هیچ قابلیت اضافه، بسیار ارزشمندتر از یک ابزار پرقابلیت است که Future Data
نشت می‌دهد یا در سرعت ۵ برابر Freeze می‌کند.

---

## ۱۷. انتقال قابلیت‌ها به V2 و V3

### V2 — عمق داده و ناوبری زمان
Tick Replay واقعی (F1) · Previous Candle / Rewind با Snapshot ·
Jump To Date · Load More History · CSV Import (Bar + Tick) با Wizard و
تعیین Timezone · Save / Resume Session · بهبود Adaptive Fidelity

### V3 — شبیه‌ساز و تحلیل
Market / Pending Orders · SL / TP / Modify / Close / Partial / Trailing ·
Virtual Balance · Risk % و Lot Calculation · Spread / Commission / Slippage ·
تمام متریک‌های آماری · Trade Journal · Export به CSV/Excel ·
Auto-Pause (Entry / SL / TP) · Blind Mode · Random Replay ·
Multi-Chart و Multi-Symbol · Replay History

### V4 — اکوسیستم
SS Strategy به‌عنوان Plugin · Strategy Mode · Session Statistics ·
اشتراک‌گذاری جلسه بین شاگردان آکادمی

---

## ۱۸. تست‌های لازم برای اطمینان از صحت Replay

این بخش مهم‌ترین تفاوت بین «Prototype» و «ابزار واقعی» است.

### ۱۸.۱ تست‌های صحت — Correctness

| # | تست | معیار قبولی |
|---|---|---|
| C1 | **بدون آینده** | در زمان T و برای هر TF، هیچ کندلی با `time ≥ T` وجود نداشته باشد. اجرای خودکار روی ۱۰۰۰ نقطه زمانی تصادفی |
| C2 | **وفاداری OHLC** | OHLC نماد Replay در بازه X **بیت‌به‌بیت** برابر OHLC نماد مبدأ باشد |
| C3 | **کندل نیمه‌کامل HTF** | در `10:37`، کندل M15 دقیقاً `High/Low/Close` بازه `10:30–10:37` باشد |
| C4 | **سازگاری TF** | M15 ساخته‌شده توسط ترمینال == M15 محاسبه‌شده مستقل از روی M1. کندل‌به‌کندل |
| C5 | **Determinism** | یک جلسه با همان پارامترها دو بار اجرا شود → Hash سری کندل‌ها یکسان |
| C6 | **تقارن Rewind** | ۱۰۰ گام جلو + ۱۰۰ گام عقب → Hash State برابر حالت اولیه |
| C7 | **درستی Reset** | بعد از Reset، هیچ داده باقی‌مانده‌ای از جلسه قبل وجود نداشته باشد |
| C8 | **پیوستگی زمان** | `replay_time` هرگز عقب نرود (به‌جز Rewind صریح) و هرگز از داده موجود جلو نزند |

### ۱۸.۲ تست‌های صداقت — Honesty (بحرانی)

| # | تست | چرا |
|---|---|---|
| H1 | **ابهام SL/TP داخل کندل** | کندلی بسازیم که هم SL و هم TP را لمس کند → موتور باید SL را انتخاب کند و معامله را `ambiguous` علامت بزند |
| H2 | **درصد معاملات مبهم** | آمار باید بگوید چند درصد نتایج، تقریبی بوده‌اند |
| H3 | **اعلام فیدلیتی** | در هر افت خودکار فیدلیتی، پنل باید تغییر را نشان دهد |
| H4 | **تشخیص نشت** | با باز بودن چارت نماد مبدأ، Guard باید هشدار بدهد |

### ۱۸.۳ تست‌های Performance

| # | تست | آستانه |
|---|---|---|
| P1 | نرخ پایدار تزریق Tick | طبق جدول بند ۱۰.۴ |
| P2 | زمان Seed | < ۲۰ ثانیه برای ۱۰۰k M1 |
| P3 | پاسخ‌گویی UI زیر بار | < ۱۰۰ ms در سرعت ۱۰x |
| P4 | استرس | ۵ سال M1 · ۸ چارت · ۶ TF · ۴ Indicator بدون Freeze |
| P5 | نشت حافظه | ۲ ساعت Replay مداوم، رشد RAM < ۱۰٪ |
| P6 | فضای دیسک | اندازه‌گیری و گزارش رشد به ازای هر ساعت Replay |

### ۱۸.۴ تست‌های پایداری

| # | تست |
|---|---|
| S1 | بستن و باز کردن چارت وسط Replay → موتور باید زنده بماند |
| S2 | تغییر Profile وسط Replay |
| S3 | Kill کردن ترمینال وسط Replay → جلسه باید قابل بازیابی باشد (P2) |
| S4 | قطع اتصال بروکر وسط Seed → پیام خطای واضح، نه Crash |
| S5 | اجرای همزمان دو جلسه روی دو Slot |
| S6 | Cleanup کامل → هیچ نماد و فایلی باقی نماند |

### ۱۸.۵ زیرساخت تست

چون MQL5 فریم‌ورک تست ندارد، باید ساخته شود:

- `SSReplayTest.mq5` — یک Script که تمام تست‌های خودکار را اجرا و گزارش می‌کند
- **Golden Dataset** — یک مجموعه M1 کوچک و ثابت، Commit شده در ریپو، تا تست‌ها
  مستقل از بروکر باشند
- **Hash Helper** — تابع Hash روی سری OHLC برای تست‌های Determinism
- گزارش خروجی به `Files/SSReplay/logs/test-report.txt`

---

## ضمیمه A — فرض‌هایی که باید در Phase 0 تأیید شوند

موارد زیر بر پایه مستندات و رفتار شناخته‌شده MQL5 نوشته شده‌اند اما **باید
تجربی تأیید شوند** قبل از اینکه معماری روی آن‌ها قفل شود:

| # | فرض | ریسک اگر غلط باشد |
|---|---|---|
| A1 | `CustomTicksAdd` ظرفیت کافی برای پخش زنده در سرعت‌های هدف دارد | F1/F2 غیرعملی می‌شود → F3 مسیر اصلی |
| A2 | تنظیم Session به ۲۴/۷ مانع حذف Tick می‌شود | نیاز به تنظیم دقیق سشن به‌ازای نماد |
| A3 | تاریخچه Custom Symbol فقط M1 را مبنا می‌گیرد و HTF را می‌سازد | تغییر استراتژی Seed |
| A4 | Service به تمام توابع `Custom*` دسترسی دارد | بازگشت به معماری تک‌EA با State Persistence |
| A5 | Service مستقل از چارت و Profile زنده می‌ماند | همان بالا |
| A6 | حذف Tail تاریخچه سریع‌تر از بازسازی کامل است | Rewind = بازسازی کامل |
| A7 | `SYMBOL_TIME` نماد Replay برابر زمان آخرین Tick تزریقی است | نیاز به کانال زمان جداگانه برای Strategy Mode |

**Plan B معماری:** اگر A4 یا A5 رد شوند، معماری به «تک EA + State Persistence
کامل در فایل» تغییر می‌کند: در `OnDeinit` تمام State ذخیره و در `OnInit` بازیابی
می‌شود. کندتر و شکننده‌تر، اما کار می‌کند. بقیه لایه‌ها بدون تغییر می‌مانند —
این دقیقاً دلیل اهمیت لایه‌بندی L0–L5 است.

---

## ضمیمه B — خلاصه اصلاحات نسبت به طرح اولیه

| موضوع | طرح تو | پیشنهاد من | وضعیت |
|---|---|---|---|
| معماری کلی (Custom Symbol → Native Chart) | ✅ درست | تأیید می‌شود | ✅ بدون تغییر |
| «هیچ Object و Bitmap» | ✅ درست | تأیید می‌شود | ✅ بدون تغییر |
| «Core مستقل از SS Strategy» | ✅ درست | تأیید و به L5 منتقل شد | ✅ بدون تغییر |
| Bar Engine حالا / Tick Engine بعداً | ⚠️ | Tick همیشه لایه انتقال | 🔄 اصلاح |
| ساختار تک‌تکه | ⚠️ | Service + Indicator | 🔄 اصلاح |
| Previous Candle هم‌ارز Next | ⚠️ | Rewind با Snapshot، در P2 | 🔄 اصلاح |
| CSV Import در آینده دور | ⚠️ | Phase 2 | 🔄 اصلاح |
| سرعت تا 50x | ⚠️ | Adaptive Fidelity | 🔄 اصلاح |
| فهرست ماژول‌ها | ⚠️ | لایه‌بندی L0–L5 | 🔄 بازسازی |
| شروع مستقیم پیاده‌سازی | ⚠️ | Phase 0 اجباری | ➕ افزوده |
| — | — | تست‌های صداقت (H1–H4) | ➕ افزوده |
| — | — | محاسبه عمق Seed برای HTF | ➕ افزوده |
| — | — | Guard نشت داده | ➕ افزوده |
