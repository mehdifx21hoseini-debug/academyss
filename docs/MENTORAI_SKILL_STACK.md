# MENTORAI — Claude Code Skill Stack (Assessment)

تاریخ: 2026-09-02 — نسخه Claude Code بررسی‌شده: 2.1.258
وضعیت: **Phase A اجرا شد.** Phase B و C هنوز منتظر تصمیم‌های معماری‌اند.

## وضعیت اجرا

| مورد | وضعیت |
|---|---|
| security-guidance | در `.claude/settings.json` اعلام شد (Project scope، منتقل‌شونده به Cloud) |
| `.claude/claude-security-guidance.md` | نوشته شد — Threat model اختصاصی MENTORAI |
| `.claude/security-patterns.json` | نوشته شد — ۶ قانون Pattern (JSON نه YAML، چون PyYAML تضمینی نیست) |
| supabase-postgres-best-practices | کپی شد در `.claude/skills/` — ۳۶ فایل مارک‌داون، ۱۶۸KB، بدون اسکریپت |
| mentorai-architecture | ساخته شد |
| mentorai-security | ساخته شد |
| mentorai-testing | ساخته شد |
| mentorai-review | ساخته شد |
| context7 | **نصب نشد.** `mcp.context7.com` توسط Proxy محیط بلاک است (403 CONNECT). به Phase C منتقل شد. |

## 0. مفروضات

1. Repository فعلی فقط یک سایت استاتیک (پلیر پادکست + پنل ادمین مبتنی بر localStorage) است و هیچ کد Backend، Telegram، RAG یا سند معماری Phase 1 در آن وجود ندارد. معماری Phase 1 در این Session در دسترس نیست؛ بنابراین ارزیابی روی «معماری محتمل» انجام شده است.
2. معماری محتمل (قابل تغییر پس از Audit): Backend پایتون (FastAPI) یا TypeScript، PostgreSQL + pgvector، Redis برای Queue/Cache، Telegram Bot API (و احتمالاً Telethon برای User Account)، CRM با Next.js/React (RTL)، Docker Compose روی VPS، Langfuse/OpenTelemetry برای AI Observability.
3. مواردی که به انتخاب زبان وابسته‌اند (pyright-lsp یا typescript-lsp، pydantic-ai، react-best-practices) «مشروط» علامت خورده‌اند.

## 1. Recommended Skills

| Skill | Category | Priority | Official/Third-party | Why MENTORAI needs it | Install |
|---|---|---|---|---|---|
| security-guidance | Security | ضروری | Anthropic (official marketplace) | بازبینی امنیتی خودکار هر تغییر (injection، secrets، SSRF، authz) + قوانین اختصاصی پروژه | Phase A |
| supabase-postgres-best-practices | Database | ضروری | Supabase (MIT) | Schema، Index، RLS، Locking، Connection pooling، pgvector؛ مستقل از Supabase | Phase A |
| skill-creator (bundled) | Meta | ضروری | Anthropic | ساخت و ارزیابی Custom Skills | موجود |
| claude-api (bundled) | AI/LLM | ضروری | Anthropic | انتخاب مدل، قیمت، Caching، Tool use، Batches | موجود |
| context7 | Docs lookup | بسیار مفید | Upstash (official marketplace) | مستندات به‌روز FastAPI/grammY/Next.js/pgvector | Phase A (اگر شبکه اجازه دهد) |
| webapp-testing | E2E | بسیار مفید | Anthropic (anthropics/skills) | تست و Screenshot اپ لوکال با Playwright، سبک و بدون MCP | Phase B |
| frontend-design | UI/UX | بسیار مفید | Anthropic | UI حرفه‌ای برای CRM؛ RTL را Custom Skill پوشش می‌دهد | Phase B |
| pr-review-toolkit | Code Review | بسیار مفید | Anthropic | Agentهای تخصصی Review: tests، error handling، type design | Phase B |
| langfuse | AI Observability | بسیار مفید | Langfuse (official marketplace) | Tracing هر AI run، prompt versioning، evaluation | Phase B (پس از تأیید Langfuse) |
| promptfoo-evals | LLM Evals | بسیار مفید | promptfoo | Regression test برای RAG و Decision Layer با Mentor Dataset | Phase B |
| pyright-lsp / typescript-lsp | Code intelligence | بسیار مفید (فقط Local) | Anthropic | Type error فوری بعد از هر Edit؛ در Cloud Session اجرا نمی‌شود | Phase B (مشروط) |
| react-best-practices + web-design-guidelines | Frontend | بسیار مفید (مشروط Next.js) | Vercel (MIT) | Performance و Accessibility برای CRM | Phase B |
| redis-development | Cache/Queue | اختیاری | Redis (official marketplace) | الگوهای Redis برای Queue/Rate limit/Dedup | Phase B (مشروط Redis) |
| playwright (MCP) | E2E | اختیاری | Microsoft (official marketplace) | مرورگر تعاملی؛ فقط اگر webapp-testing کافی نبود | Phase C |
| claude-security | Security deep scan | اختیاری | Anthropic | اسکن عمیق Multi-agent قبل از Production؛ پرهزینه | Phase C (قبل از Deploy) |
| hookify | Guardrails | اختیاری | Anthropic | ساخت Hook برای Approval Gate (مثلاً بلاک Migration) | Phase C |
| claude-md-management | Docs | اختیاری | Anthropic | نگه‌داری CLAUDE.md | Phase C |
| sentry / semgrep / qdrant-skills / pydantic-ai / logfire | مشروط | اختیاری | Third-party (official marketplace) | فقط اگر آن سرویس انتخاب شد | Phase C |

## 2. Skills I Should NOT Install

| Skill | دلیل رد |
|---|---|
| telegram (official marketplace) | Bridge برای چت با Claude Code از داخل Telegram است، نه Skill ساخت ربات؛ دسترسی Telegram به Session شما می‌دهد. |
| superpowers | Hook در SessionStart که هر Session Context تزریق می‌کند (باگ تزریق دوبل #648)، فرآیند سنگین و موازی با فرآیند Approval-gated خودمان و Skills bundled. |
| engineering (knowledge-work-plugins) | عمومی؛ ده MCP Server (Asana، Datadog، Slack…) بسته‌بندی می‌کند؛ هزینه Context بدون ارزش خاص. |
| telegram-bot-builder (davila7) | Dedup/Idempotency، sendChatAction، MTProto و Human Handoff ندارد؛ Custom Skill بهتر است. |
| rag-architect (Jeffallan) | Qdrant + OpenAI + Cohere + LangChain را تجویز می‌کند؛ فارسی و pgvector ندارد. |
| devops-skills packs | Kubernetes/Terraform/Helm برای VPS + Compose بیش‌ازحد است. |
| persian-rtl-format | فقط Rendering متن ترکیبی در ترمینال را درست می‌کند. |
| andrej-karpathy-skills | چهار قانون رفتاری ~40 خط؛ در CLAUDE.md می‌نویسیم، Plugin لازم نیست. |
| feature-dev | Workflow هفت‌مرحله‌ای که با فرآیند AUDIT→ARCH→APPROVAL ما تداخل دارد. |
| commit-commands / code-simplifier / github / agent-sdk-dev / mcp-builder | با ابزارهای موجود (bundled /simplify، GitHub MCP، claude-api) هم‌پوشانی دارند یا فعلاً بی‌ربط‌اند. |
| supabase (MCP) / neon / prisma / planetscale | فقط برای Hosting همان سرویس؛ تصمیم Infra گرفته نشده. |
| deepeval / mlflow | با promptfoo هم‌پوشانی دارد؛ یک ابزار Eval کافی است. |
| remember / browser-use / desktop-commander | Third-party با دسترسی گسترده به مکالمات یا ماشین؛ ریسک بدون نیاز. |
| hookdeck webhook-skills | الگوهای Idempotency مفید است ولی ~180 Skill Provider است؛ در mentorai-telegram پوشش می‌دهیم. |

## 3. Custom Skills (پیشنهادی برای `.claude/skills/`)

| Skill | چه چیزی را حل می‌کند | Phase |
|---|---|---|
| mentorai-architecture | Source of Truth، Module boundaries، Approval Gates، ADR template، اولویت‌های محصول | A |
| mentorai-security | RBAC matrix، Secret policy، PII logging، Telegram credentials + تولید `claude-security-guidance.md` و `security-patterns.yaml` | A |
| mentorai-testing | تعریف «Tested»، هرم تست، Fixture برای Telegram update، DB test با Postgres واقعی، RAG/Escalation tests | A |
| mentorai-review | Checklist review اختصاصی: Idempotency، Transaction، فارسی، Secrets، ADR/Docs به‌روز | A |
| mentorai-telegram | Dedup update_id، Webhook vs Polling، Bot API vs MTProto، Typing/Delay، Rate limits، Handoff State Machine | B |
| mentorai-rag-persian | نرمال‌سازی فارسی (ZWNJ، ی/ک عربی، ارقام)، Chunking فارسی، Hybrid search pgvector + FTS، Reranking، Metadata source | B |
| mentorai-memory-escalation | Memory Policy (Short/Long-term، PII)، Identity Resolution، Decision Layer و قوانین Escalation | B |
| mentorai-ai-runtime | Model routing، Prompt versioning، AI run record schema، Cost/latency budget، Langfuse conventions | B |
| mentorai-ui-rtl | RTL، تایپوگرافی فارسی، ارقام، تاریخ جلالی، جستجوی فارسی در CRM | B |
| mentorai-deploy | Docker Compose، VPS، Backup/Restore، Health checks، Runbook (+ خروجی /run-skill-generator) | B |

## 4. Installation Plan

- **Phase A (انجام شد):** security-guidance، supabase-postgres-best-practices، Custom: mentorai-architecture، mentorai-security، mentorai-testing، mentorai-review. context7 به‌دلیل بلاک بودن شبکه انجام نشد.
- **Phase B (حین توسعه):** webapp-testing، frontend-design، pr-review-toolkit، langfuse، promptfoo-evals، LSP مناسب زبان، Vercel skills (اگر Next.js)، redis-development (اگر Redis)، بقیه Custom Skills.
- **Phase C (آینده):** playwright MCP، claude-security، hookify، claude-md-management، sentry/semgrep/qdrant/pydantic-ai/logfire به‌شرط انتخاب سرویس.

## 5. Exact Installation Commands

نکته‌ی کلیدی: این پروژه در Cloud Session اجرا می‌شود. Plugin با scope کاربر به Cloud منتقل نمی‌شود؛ باید در `.claude/settings.json` ریپو اعلام شود. Skillهای پوشه‌ی `.claude/skills/` با Clone منتقل می‌شوند.

### 5.1 Plugins از Official Marketplace (اعلام در ریپو)

```json
{
  "enabledPlugins": {
    "security-guidance@claude-plugins-official": true
  }
}
```

این فایل نوشته شده است. `context7` عمداً حذف شد: در این محیط Cloud، دامنه‌ی `mcp.context7.com`
توسط Proxy بلاک است و اعلام آن در ریپو باعث خطای MCP در هر Session می‌شود. اگر مالک پروژه
آن دامنه را در Network policy محیط Allow کند، یک خط به همین فایل اضافه می‌شود.

معادل ترمینال روی ماشین Local، جایی که context7 احتمالاً در دسترس است:

```text
/plugin install context7@claude-plugins-official
/reload-plugins
```

Phase B (به همان روش): `pr-review-toolkit`، `frontend-design`، `langfuse`، `pyright-lsp` یا `typescript-lsp`، `redis-development`.
Phase C: `playwright`، `claude-security`، `hookify`، `claude-md-management`.

### 5.2 Skills کپی‌شده داخل ریپو (Pinned در Git)

```bash
# انجام شد:
npx skills add supabase/agent-skills --skill supabase-postgres-best-practices -a claude-code --copy -y

# Phase B:
npx skills add anthropics/skills --skill webapp-testing -a claude-code --copy
npx skills add vercel-labs/agent-skills --skill react-best-practices -a claude-code --copy
npx skills add vercel-labs/agent-skills --skill web-design-guidelines -a claude-code --copy
npx skills add promptfoo/promptfoo --skill promptfoo-evals -a claude-code --copy
```

`--copy` به‌جای Symlink استفاده می‌شود تا محتوا داخل `.claude/skills/` بماند، Review شود و به Cloud منتقل شود. قبل از Commit هر SKILL.md بازبینی می‌شود (frontmatter `allowed-tools` و اسکریپت‌ها).

### 5.3 Custom Skills

```text
/skill-creator   → ساخت هر Skill در .claude/skills/<name>/SKILL.md
```
