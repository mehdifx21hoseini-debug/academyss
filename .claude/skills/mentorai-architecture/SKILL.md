---
name: mentorai-architecture
description: Architectural ground rules for the MENTORAI AI mentoring platform (Sobhan Samadi Academy) - what the system is, what is decided and what is still open, the source of truth for each subject, which changes need the owner's approval before they are made, and how to record an architecture decision. Load before designing a component, choosing a technology or framework, adding a service or dependency, changing the data model, planning a migration, or answering a question about how MENTORAI should be structured. Also load when the request mentions the Telegram bot, the conversation engine, human handoff, the knowledge base, student memory, the CRM or admin panel, or MENTORAI deployment.
license: MIT
---

# MENTORAI architecture

## What this system is

MENTORAI is a production AI mentoring platform for Sobhan Samadi Academy. Students reach it
through Telegram. An AI answers what it can answer confidently and escalates everything else
to a human mentor. A management panel gives staff visibility into leads, conversations,
mentors, the knowledge base, AI runs and KPIs.

The audience is Persian-speaking. Right-to-left layout, Persian typography, Persian text
normalization and Persian retrieval quality are architectural requirements, not a later
localization pass.

## Current state, and what it means for you

The repository today holds a static marketing and podcast site: `index.html`, `admin.html`,
`css/`, `js/`, `assets/`. The admin panel authenticates in the browser against a password
in `js/admin.js` and stores content in `localStorage`. There is no backend, no database, no
Telegram integration, no AI and no test suite.

Two consequences:

1. **Nothing about the MENTORAI stack is decided yet.** Backend language, framework,
   database, vector store, queue, hosting and messaging approach are all open. Do not write
   code, scaffolding or configuration that assumes an answer. If a task needs one, say which
   decision is missing and ask.
2. **The existing admin panel is not a foundation.** Its authentication is client-side and
   its data lives in the visitor's browser. Treat it as a prototype to be replaced, not as
   the CRM to extend. Do not copy its patterns into new code.

## Decision priority

When two goals conflict, resolve in this order. This order is the owner's, not a default.

1. Reliability
2. Security
3. Correctness
4. Maintainability
5. User experience
6. Scalability
7. Cost
8. Development speed

"Simple now, scalable later" is the sizing rule. Build for the load that exists, behind
boundaries that let the load grow. Do not add a queue, a cache, a service split or a vector
database that the current requirement does not need.

## Source of truth

Never let two places disagree about the same fact. For each subject there is exactly one
authority, and everything else reads from it.

| Subject | Source of truth |
|---|---|
| Database schema | Migration files in version control |
| Application configuration | Environment variables, loaded through one typed config module |
| Secrets | Secret manager or environment, never the repository |
| Academy knowledge | Knowledge base documents with explicit source metadata |
| Student state and profile | Database |
| Conversation and message history | Database |
| Mentor assignment | Database |
| Infrastructure shape | Infrastructure configuration in version control |
| Why a decision was made | `docs/ARCHITECTURE_DECISIONS.md` |

Knowledge base sources stay separated by provenance. Official course material, academy
rules and product information are one class of source. Real mentor answers collected from
conversations are another. Every chunk carries its source class, and retrieval can filter on
it. Never blend them into one undifferentiated corpus.

## Boundaries to keep

Design so these stay separable, whatever stack is chosen.

- **Channel adapter** speaks Telegram and nothing else. It converts an inbound update into a
  domain message and a domain response back into a Telegram call. No business logic here.
- **Conversation engine** owns conversations, messages, senders, status and transitions. A
  conversation is a first-class entity, not a side effect of message rows.
- **Decision layer** decides whether the AI answers or a human is needed. It is a separate,
  testable unit with its own inputs, outputs and recorded rationale. It must be possible to
  read why it chose escalation for any given message.
- **Retrieval** turns a question into ranked passages with scores and source metadata. It
  does not generate text.
- **Memory** exposes short-term conversation context and long-term student memory through a
  policy, not through direct table access from anywhere.
- **AI runtime** performs model calls and records every execution: model, prompt version,
  latency, tokens, retrieved documents and their scores, the decision taken, the response and
  any error.
- **Management panel** reads and writes through the same authorized API the rest of the
  system uses. It gets no privileged direct database path of its own.

## Approval gates

Stop and ask the owner before doing any of these, even when the change looks obviously right:

- Changing the core architecture or replacing a chosen technology
- Removing a technology already in use
- Running or authoring a destructive database migration, or deleting data
- Changing infrastructure, hosting or the deployment target
- Introducing a new recurring cost or selecting a paid service
- Deploying to production
- Changing a public or inter-service API contract
- Changing the security model, the authentication scheme or the role model

Small, non-destructive, reversible changes inside an approved plan do not need a separate
approval each time. The point of the gate is to protect decisions with cost or blast radius,
not to stall the work.

## Recording decisions

Every decision that closes one of the open questions goes into `docs/ARCHITECTURE_DECISIONS.md`
as a numbered entry, newest last, with four parts:

```markdown
## ADR-007: <the decision, stated as a sentence>

- Date: YYYY-MM-DD
- Status: Accepted | Superseded by ADR-0NN

**Decision.** What we will do.

**Reason.** Why, tied to the priority order above.

**Alternatives.** What else was considered and why it lost.

**Trade-offs.** What this costs us, and what we will have to watch.
```

Write the ADR when the decision is made, not at the end of the phase. If you find yourself
explaining a choice in chat for a second time, it belongs in an ADR.

## Documentation to keep current

`README`, `ARCHITECTURE`, `SETUP`, `ENVIRONMENT`, `DATABASE`, `API`, `DEPLOYMENT`,
`SECURITY`, `TESTING`, `TROUBLESHOOTING`, `ARCHITECTURE_DECISIONS`. A change that makes one
of these wrong is not finished until that file is corrected in the same change.

## Working process

The owner's process is sequential and gated:

audit → architecture → questions → approval → implementation plan → approval → implement →
test → verify → document → next phase

Group questions by urgency. Critical questions block progress and must be answered.
Important questions can be carried with a stated assumption. Optional questions are for
later. Offer multiple-choice answers wherever the options are enumerable, so answering is
fast.

## Related skills

- `.claude/skills/mentorai-security/SKILL.md` for the security and access model
- `.claude/skills/mentorai-testing/SKILL.md` for what counts as tested
- `.claude/skills/mentorai-review/SKILL.md` for the review checklist
- `.claude/skills/supabase-postgres-best-practices/SKILL.md` for Postgres schema and query rules
