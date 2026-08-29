# Phase 1 — Core Replay Engine

**وضعیت:** ✅ کامل · **کامپایل‌نشده** (بدون MetaTrader در محیط توسعه)
**تست:** `Scripts/SSReplay/Tests/SSR_T1_CoreEngine.mq5` — ۶۸ Assertion، بدون نیاز به بروکر

---

## Scope

| داخل | خارج (به Phase بعدی موکول) |
|---|---|
| Replay Clock قطعی | Custom Symbol → P3 |
| Replay State + ماشین حالت ۸ وضعیتی | Chart API → P4 |
| Replay Timeline (سه بازه مجزا) | UI → P5 |
| Replay Cursor | Load More History → P6 |
| Future Data Guard دولایه | Adaptive Fidelity → P7 |
| Snapshot / Restore | Step Backward تعاملی → P8 |
| قراردادهای انتزاعی Data و Sink | Trading → P9 · Statistics → P10 |
| Tick Synthesizer | منابع واقعی داده → P2 |

---

## سه Seam که کل پروژه رویشان سوار است

```
                  ┌──────────────────────────┐
   Phase 2 ──────▶│  CSSRDataSource          │
   Phase 6        │   ├ CSSRHistoryProvider   │
                  │   ├ CSSRBarProvider       │
                  │   └ CSSRTickProvider      │
                  └───────────┬──────────────┘
                              ▼
                  ┌──────────────────────────┐
   Phase 3 ──────▶│  CSSRReplayController    │◀── Pump(wall_delta_ms)
   (Service)      │   Clock · Timeline       │
                  │   Cursor · Guard         │
                  └───────────┬──────────────┘
                              ▼
                  ┌──────────────────────────┐
   Phase 3 ──────▶│  CSSRReplaySink          │
   (CustomSymbol) └──────────────────────────┘
```

هیچ‌کدام از این سه در Phase 1 پیاده‌سازی واقعی ندارند — فقط قرارداد و یک
Test Double. این عمدی است: موتور باید بدون MetaTrader قابل اجرا و تست باشد.

---

## سه تصمیم فنی که ارزش توضیح دارند

### ۱. زمان همیشه میلی‌ثانیه است، نه `datetime`

کل موتور با `long` میلی‌ثانیه از epoch کار می‌کند — همان مبنای `MqlTick.time_msc`.
`datetime` فقط در مرزها ظاهر می‌شود. قاطی کردن این دو، کلاسیک‌ترین منبع باگ
«یک کندل جابه‌جا» است. تبدیل‌ها فقط در `SSR_Time.mqh` انجام می‌شوند.

### ۲. سرعت عدد صحیح است، نه اعشاری

سرعت به‌صورت **صدم صحیح** نگه داشته می‌شود (`1x = 100`) و پیشروی با حساب صحیح
به‌علاوه یک باقی‌مانده انجام می‌شود:

```
scaled  = wall_delta_ms * speed_x100 + residue
advance = scaled / 100
residue = scaled % 100
```

ضرب یک delta در `0.25` اعشاری و برش، هر بار یک میلی‌ثانیه دِرِیفت می‌دهد؛ در یک
ساعت Replay آن دریفت به یک کندل اشتباه تبدیل می‌شود. حساب صحیح اصلاً دریفت ندارد.

**تست T1.1 این را ثابت می‌کند:** ۴۰۰۰ بار پیشروی ۷ms در سرعت 0.25x باید *دقیقاً*
۷۰۰۰ms بدهد.

### ۳. موتور نه می‌خوابد و نه ساعت می‌خواند

`Pump(wall_delta_ms)` را کسی صدا می‌زند که مالک Thread است — Service در محصول،
یک حلقه با delta ثابت در تست. نتیجه: موتور یک **تابع خالص از ورودی‌هایش** است،
پس هم قطعی است هم بدون MetaTrader قابل تست.

---

## نتیجه Code Review داخلی

بازبینی **دو باگ واقعی** پیدا کرد که هر دو اصلاح شدند:

### 🐞 باگ ۱ — انتشار دوباره تیک وسط کندل (Critical)

کندل مصنوعی همیشه کل یک دقیقه را پوشش می‌دهد. وقتی یک Pump وسط کندل تمام می‌شد،
Pump بعدی همان کندل را دوباره می‌خواند و **از ابتدا** می‌ساخت. Guard فقط دُم آینده
را می‌بُرید، نه سرِ گذشته را — پس تیک‌های ابتدای کندل دوبار منتشر می‌شدند.

در MT5 این یعنی کندل خراب.

**اصلاح:** `TrimWindow()` که هر دو سر بازه را می‌بُرد، نه فقط بالا را.
**تست:** `CheckEq("exact tick count over one bar", 9, sink.TickCount())` —
اگر تیکی دوبار منتشر شود یا جا بیفتد، این عدد فوراً غلط می‌شود.

### 🐞 باگ ۲ — حذف خاموش کندل زیر سقف Pump (High)

`SSR_MAX_BARS_PER_PUMP` تعداد کندل را محدود می‌کرد، اما Cursor همچنان تا انتهای
بازه جلو می‌رفت. یعنی کندل‌های بالای سقف **برای همیشه رد می‌شدند** نه اینکه به
Pump بعدی موکول شوند.

**اصلاح:** Cursor فقط تا انتهای آخرین کندل واقعاً مصرف‌شده جلو می‌رود.
بقیه بدهکار می‌مانند و Pump بعدی برشان می‌دارد.

### 🔧 اصلاحات کیفی

| مورد | چرا |
|---|---|
| `TrimWindow` قبل از `FilterTicks` | ترتیب مهم است — سر قبل از دُم |
| تفکیک `OrderViolations` از `DuplicateStamps` | تیک واقعی بروکر می‌تواند هم‌میلی‌ثانیه باشد؛ یکی کردنشان در Phase 2 سیل False Positive می‌داد |
| حذف `const` از `RestoreSnapshot` | MQL5 متد `const` ندارد؛ صدا زدن متد روی `const&` قابل اتکا نیست |
| Accessorهای مستقیم روی Controller | خواندن فیلد از struct برگشتی by-value در MQL5 قابل اتکا نیست |
| جایگزینی `MathMax` روی `long` | ارتقا به `double` و برگشت، بی‌دلیل و ریسک‌دار بود |

---

## Architecture Consistency — بررسی خودکار

```
grep -rE "CustomSymbol|CustomRates|CustomTicks|Chart*|OrderSend|
          SymbolInfo|CopyRates|CopyTicks|Sleep|Comment" Core/ Common/
→ صفر نتیجه ✅
```

Core فقط `MqlRates` و `MqlTick` را می‌شناسد — و آن‌ها **ساختار داده‌اند، نه API**.
جهت وابستگی یک‌طرفه است: `Core → Common`، هرگز برعکس.

---

## TODOهای واقعی (نه آرزو)

| # | مورد | شدت | مقصد |
|---|---|---|---|
| T1 | `CSSRProviderBase.m_guard` اشاره‌گر خام به عضو Controller است. اگر Controller زودتر از DataSource نابود شود، Provider اشاره‌گر آویزان دارد. نیاز به `Detach()` صریح در `Release()` | 🟠 High | Phase 2 |
| T2 | `SSR_Log.mqh` از `FileOpen` استفاده می‌کند، پس Core به‌طور غیرمستقیم به File IO وابسته است. پیش‌فرض خاموش است، ولی راه درست یک `ILogSink` است | 🟡 Medium | Phase 7 |
| T3 | رفتار `StepBars` دقیقاً روی مرز کندل تست نشده | 🟡 Medium | Phase 8 |
| T4 | `SSR_MAX_BARS_PER_PUMP = 512` یک عدد حدسی است. باید با اعداد واقعی B2/D1 جایگزین شود | 🟡 Medium | Phase 7 |
| T5 | `EmitWindow` در حالت FULL_TICK از `lo - 1` استفاده می‌کند تا بازه نیمه‌باز شود؛ اگر `lo == 0` باشد معنا ندارد. عملاً محافظت شده ولی باید صریح شود | 🟢 Low | Phase 2 |
| T6 | Snapshot هنوز به فایل serialize نمی‌شود | 🟢 Low | Phase 12 |
| T7 | تجمیع D1 در `SSRBarOpenMsc` بر مبنای نیمه‌شب UTC است؛ برای W1/MN1 عمداً پشتیبانی نشده | 🟢 Low | — (مستند شده) |

---

## Definition of Done — وضعیت

| # | معیار | وضعیت |
|---|---|---|
| ۱ | ماشین حالت ۸ وضعیتی، گذار نامعتبر رد شود | ✅ T1.2 |
| ۲ | ساعت قطعی، دو اجرا خروجی یکسان | ✅ T1.1 + T1.5 |
| ۳ | Future Guard دولایه | ✅ T1.6 |
| ۴ | Core بدون ارجاع به Chart/Custom/UI | ✅ grep |
| ۵ | Snapshot/Restore دقیق | ✅ T1.8 |
| ۶ | تست بدون داده بروکر اجرا شود | ✅ Memory source |

**باقی‌مانده:** کامپایل واقعی در MetaEditor — به Phase 16 موکول است.
