# SS Replay — Phase 0 Spike Tests

> **این کد محصول نیست.** هدف فقط اثبات یا رد فرض‌های معماری است.
> هیچ‌چیز از این پوشه وارد موتور نهایی نمی‌شود.

مشخصات کامل هر تست در [`docs/mt5-replay/PHASE-0-SPIKE-PLAN.md`](../docs/mt5-replay/PHASE-0-SPIKE-PLAN.md).

---

## نصب

۱. پوشه Data ترمینال را باز کن: **File → Open Data Folder**
۲. محتویات `MQL5/` این پروژه را روی `MQL5/` ترمینال کپی کن:

```
MQL5/Include/SSReplay/Spike/SSR_SpikeKit.mqh
MQL5/Scripts/SSReplay/Spike/SSR_A1_...  تا  SSR_Z_Cleanup.mq5
MQL5/Services/SSReplay/Spike/SSR_C1_... و SSR_C2_...
MQL5/Indicators/SSReplay/Spike/SSR_Probe_...
```

۳. در MetaEditor: **Ctrl+Shift+B** برای کامپایل همه
۴. در MT5: **View → Navigator** و Refresh

### تنظیمات ترمینال قبل از شروع

| تنظیم | مقدار | چرا |
|---|---|---|
| Tools → Options → Charts → Max bars in chart | `Unlimited` یا حداقل ۱۰ میلیون | تست‌های D1 و D2 با ۵۰۰ هزار کندل کار می‌کنند |
| Tools → Options → Charts → Max bars in history | `Unlimited` | همان |
| یک Profile خالی به نام `SSR_Test` بساز | — | تست‌ها چارت باز و بسته می‌کنند |

---

## ترتیب اجرا

**این ترتیب اختیاری نیست.** اگر Tier A شکست بخورد، ادامه دادن بی‌معنی است.

```
1. SSR_Z_Cleanup                (InpDeleteResults = true)   ← شروع تمیز
2. SSR_B4_BrokerDataAudit       ← اول، چون بقیه را جهت می‌دهد

── TIER A ── Blocker ──────────────────────────────────────
3. SSR_A1_SymbolLifecycle
4. SSR_A2_RatesAndAggregation   ★ مهم‌ترین تست کل Phase 0
5. SSR_A3_FutureIsolation

── TIER B ── Transport ────────────────────────────────────
6. SSR_B1_TicksAddBroadcast     (+ TickWitness روی چارت نماد تست)
7. SSR_B2_TickThroughput        (+ UIJitter روی چارت دیگر) × ۳ بار
8. SSR_B3_SessionBehavior

── TIER C ── Process Model ────────────────────────────────
9.  SSR_C1_ServiceApiAccess     ← Service است، از Navigator
10. SSR_C2_ServicePersistence   ← Service + Checklist دستی
11. SSR_C3_IpcChannel
12. SSR_C4_ReplayClock

── TIER D ── Performance ──────────────────────────────────
13. SSR_D1_SeedPerformance      (+ UIJitter)
14. SSR_D2_TimeframeSwitch
15. SSR_D4_RewindCost
16. SSR_D3_SustainedRun         ← آخر، چون ۲ ساعت طول می‌کشد
```

---

## دستورالعمل تست‌های خاص

### B1 — قبل از اجرا

۱. اسکریپت را با `InpOpenChart = true` اجرا کن
۲. به‌محض باز شدن چارت `SSRB1`، ایندیکیتور `SSR_Probe_TickWitness` را روی آن بینداز
۳. اگر Witness هیچ `OnCalculate` ثبت نکرد ← تست FAIL است، حتی اگر بقیه PASS باشند

### B2 — سه بار اجرا، با سه برچسب

| اجرا | `InpCharts` | Indicator روی چارت | `InpLabel` |
|---|---|---|---|
| ۱ | `0` | — | `charts0_ind0` |
| ۲ | `1` | — | `charts1_ind0` |
| ۳ | `4` | ۴ ایندیکیتور روی هر چارت | `charts4_ind4` |

قبل از هر اجرا `SSR_Probe_UIJitter` را روی یک چارت **دیگر** (نماد واقعی) بینداز
و `InpLabel` آن را هم‌نام بگذار.

### C2 — Checklist دستی

Service را استارت کن و دقیقاً این کارها را در این زمان‌ها انجام بده:

```
t+30s   تایم‌فریم چارت را M5 → M15 کن
t+60s   دوباره M15 → H1
t+90s   چارت را ببند
t+120s  یک چارت جدید باز کن
t+150s  Symbol آن چارت را عوض کن
t+180s  Profile را عوض کن
t+240s  همه چارت‌ها را ببند
t+300s  Service را Stop کن
```

بعد `MQL5/Files/SSR_Spike/c2_heartbeat.csv` را باز کن.
**PASS:** ستون `seq` هیچ‌وقت ریست نشده و هیچ `gap_ms` بالای ۳۰۰۰ نیست.

### D3 — قبل از اجرا

- `SSR_Probe_UIJitter` را برای کل مدت روی چارت دیگری بگذار
- CPU را از Task Manager در دقیقه‌های **۱۰، ۶۰ و ۱۲۰** دستی یادداشت کن
- حجم پوشه `<DataFolder>\bases\Custom` را قبل و بعد یادداشت کن

---

## خروجی

```
<DataFolder>/MQL5/Files/SSR_Spike/
├── env.csv               محیط اجرا
├── results.csv           تمام اعداد اندازه‌گیری‌شده
├── verdicts.csv          PASS/FAIL هر Assertion
├── c2_heartbeat.csv      ضربان Service
└── d3_timeseries.csv     سری زمانی حافظه و نرخ
```

هر سه فایل اول را برای من بفرست تا تحلیل کنم و سند طراحی را با اعداد واقعی به‌روز کنم.

---

## چیزهایی که این تست‌ها نمی‌سنجند

صادقانه، تا انتظار اشتباه شکل نگیرد:

| مورد | چرا نه | جایگزین |
|---|---|---|
| **CPU درصد** | MQL5 هیچ API برای مصرف CPU ندارد | ثبت دستی + متریک UI Jitter که معیار بهتری است |
| **حجم دیسک** | MQL5 اندازه پوشه را نمی‌خواند | ثبت دستی از `bases\Custom` |
| **رفتار واقعی بروکر** | Golden Dataset مصنوعی است | B4 وضعیت واقعی داده بروکر را جدا Audit می‌کند |
| **تجمیع D1** | ممکن است به روز معاملاتی بروکر گره بخورد نه نیمه‌شب UTC | در A2 فقط اطلاعاتی گزارش می‌شود، Blocker نیست |

---

## نکته درباره کامپایل

این کدها روی محیط بدون MetaTrader نوشته شده‌اند و **کامپایل نشده‌اند**.
احتمال خطای کوچک کامپایل وجود دارد. اگر MetaEditor خطایی داد، متن کامل خطا
به‌همراه نام فایل و شماره خط را بفرست تا اصلاح شود.
