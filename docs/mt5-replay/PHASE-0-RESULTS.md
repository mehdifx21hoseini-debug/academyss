# Phase 0 — Results

**وضعیت:** ⬜ اجرا نشده
**تاریخ اجرا:** —
**Build ترمینال:** —
**بروکر / سرور:** —
**CPU / RAM دستگاه:** —

> این فایل بعد از اجرای تست‌ها پر می‌شود. تا وقتی خالی است، **هیچ تصمیم معماری
> نهایی نیست** و هر عددی در سند طراحی یک تخمین است، نه یک واقعیت.

---

## جدول تصمیم

| Spike | Tier | وضعیت | عدد کلیدی | تصمیم معماری |
|---|---|---|---|---|
| A1 Symbol Lifecycle | 🔴 | ⬜ | `properties_mismatch = ?` | — |
| A2 Rates & Aggregation | 🔴 | ⬜ | `ohlc_mismatch = ?` | — |
| A3 Future Isolation | 🔴 | ⬜ | `leaks_found = ?` | — |
| B1 TicksAdd Broadcast | 🔴 | ⬜ | `forming_bar_took_close = ?` | — |
| B2 Tick Throughput | 🔴 | ⬜ | `best_ticks_per_sec = ?` | — |
| B3 Session Behavior | 🟠 | ⬜ | `acceptance_rate = ?%` | — |
| B4 Broker Data Audit | 🟠 | ⬜ | `tick_history_depth = ? days` | — |
| C1 Service API Access | 🔴 | ⬜ | `12 ops ok?` | — |
| C2 Service Persistence | 🔴 | ⬜ | `gaps_over_3s = ?` | — |
| C3 IPC Integrity | 🟠 | ⬜ | `torn_reads = ?` | — |
| C4 Replay Clock | 🟠 | ⬜ | `sec_mismatches = ?` | — |
| D1 Seed Performance | 🟡 | ⬜ | `100k in ? s` | — |
| D2 TF Switch Cost | 🟡 | ⬜ | `worst_switch = ? ms` | — |
| D3 Sustained Run | 🟡 | ⬜ | `mem_growth = ?%` | — |
| D4 Rewind Cost | 🟡 | ⬜ | `tail_1bar avg = ? ms` | — |

---

## اعدادی که باید در سند طراحی جایگزین تخمین شوند

| بخش سند | مقدار فعلی (تخمین) | مقدار واقعی | منبع |
|---|---|---|---|
| ۱۰.۲ جدول Adaptive Fidelity | تخمینی | — | B2 |
| ۱۰.۴ نرخ تزریق Tick | `≥ ۲۰۰۰ tick/s` | — | B2 |
| ۱۰.۴ زمان Seed ۱۰۰k | `< ۲۰ s` | — | D1 |
| ۱۰.۴ مصرف RAM | `< ۳۰۰ MB` | — | D3 |
| ۱۰.۴ گام Step Back | `< ۵۰۰ ms` | — | D4 |
| ۳.۲ طول نام نماد | `≈ ۳۱ کاراکتر` | — | A1 |
| ۵.۲ سقف `CopyTicksRange` | نامعلوم | — | B4 |
| ۲.۴ نرخ کانال IPC | نامعلوم | — | C3 |
| Feeder — اندازه Batch بهینه | نامعلوم | — | B2 |
| HistoryLoader — اندازه Chunk بهینه | نامعلوم | — | D1 |

---

## فرض‌های ضمیمه A سند طراحی

| # | فرض | نتیجه | Spike |
|---|---|---|---|
| A1 | ظرفیت `CustomTicksAdd` کافی است | ⬜ | B2 |
| A2 | Session ۲۴/۷ مانع حذف Tick می‌شود | ⬜ | B3 |
| A3 | مبنای ذخیره‌سازی فقط M1 است | ⬜ | A2 |
| A4 | Service به توابع `Custom*` دسترسی دارد | ⬜ | C1 |
| A5 | Service مستقل از چارت زنده می‌ماند | ⬜ | C2 |
| A6 | حذف Tail سریع‌تر از بازسازی کامل است | ⬜ | D4 |
| A7 | `SYMBOL_TIME` برابر زمان آخرین تیک است | ⬜ | C4 |

---

## مشاهدات دستی

### CPU (از Task Manager)

| زمان | تست | CPU % | RAM ترمینال |
|---|---|---|---|
| — | — | — | — |

### حجم دیسک `bases\Custom`

| مرحله | حجم |
|---|---|
| قبل از همه تست‌ها | — |
| بعد از D1 (۵۰۰k کندل) | — |
| بعد از Cleanup | — |

---

## تصمیم نهایی Gate

پس از تکمیل Tier A، B و C:

- [ ] معماری `Custom Symbol → Native Chart` تأیید شد
- [ ] لایه انتقال Tick تأیید شد
- [ ] معماری `Core = Service` تأیید شد
- [ ] سند طراحی با اعداد واقعی به‌روز شد
- [ ] Phase 1 (MVP) می‌تواند شروع شود

**Plan Bهای فعال‌شده:** —
