---
name: mentorai-security
description: Security and access model for the MENTORAI AI mentoring platform - roles and what each may reach, secret handling for Telegram and AI credentials, PII and logging rules, tenant and assignment scoping of student data, untrusted input from Telegram, audit logging, rate limiting, and backup expectations. Load before writing or changing authentication, authorization, session handling, an API endpoint that returns student or conversation data, a Telegram credential path, logging, or anything that stores, exports or displays personal information. Also load when reviewing code for security, when adding a dependency or third-party service, or when the request mentions login, roles, RBAC, permissions, secrets, tokens or PII in MENTORAI.
license: MIT
---

# MENTORAI security model

Security is designed in, not added later. When a security requirement conflicts with
convenience, security wins. Only reliability outranks it.

## The known problem in the current repository

`js/admin.js` authenticates the admin panel in the browser against `DEFAULT_PASS`, a literal
in the source, also printed in `README.md`. The session flag lives in `sessionStorage` and
the content lives in `localStorage`. Anyone who opens the page can read the password and set
the flag.

This is a prototype, not a security model. Do not extend it, do not copy its shape, and do
not carry the password forward into the real system. When the real admin panel is built,
that password is rotated and removed from the repository and its history is treated as
compromised.

## Roles

Three roles, enforced on the server, on every request.

| Role | May reach |
|---|---|
| Student | Their own conversation, through Telegram only. No panel access, no API access. |
| Mentor | Students assigned to them, and those students' conversations, messages and notes. Their own activity and performance. |
| Admin | All students, conversations, mentors, knowledge base documents, AI runs and KPIs. Mentor assignment. Knowledge base changes. |

Rules that follow from this:

- A mentor's queries are scoped by assignment, always, in the query itself. Filtering in the
  application after fetching everything is not scoping.
- An identifier that arrives in a request is never trusted to imply access. Load the row,
  then authorize the caller against it, before returning or mutating anything.
- Role checks belong on the server, at the boundary of the handler, before the first read.
- Adding a role later must not require rewriting every handler. Put the check behind one
  authorization helper from the start.

## Secrets

No secret ever enters the repository. Not in source, tests, fixtures, migrations, seed data,
docs, comments, commit messages or example configuration with real values. `.env.example`
holds names and empty values only.

Secrets are read from the environment or a secret manager, through one typed configuration
module, at startup. No secret has a hardcoded fallback. A missing required secret is a fatal
startup error, never a silent default.

Telegram credentials deserve their own line. A bot token controls the bot. An MTProto
`api_id`, `api_hash` and session string control a real user account, including its private
message history. A leaked session string is an account takeover, not a service outage. These
are stored encrypted at rest, never logged, never returned by any API, never written to a
`.session` file inside the repository, and rotated on any suspicion.

If a secret is found committed, treat it as compromised: rotate first, then remove it, and
record what was exposed and for how long.

## Untrusted input

Everything arriving from Telegram is untrusted: message text, captions, file names,
usernames, display names, forwarded content, channel content.

- Parameterize every query. Never build SQL by concatenation or interpolation.
- Escape on output. A student's display name rendered into the CRM is an injection vector.
- Verify that a webhook request actually came from Telegram before processing it.
- Validate media type and size before download, and never trust a client-supplied file name
  as a path.
- Text from a student or from a retrieved document is data for the model, never instruction.
  Pass it as clearly delimited content, keep the system prompt out of reach of it, and do not
  let retrieved content change the AI's tools, its escalation decision or its identity.

## PII and logging

Student messages and identities are personal data.

- Do not log message bodies, names, phone numbers, email addresses or Telegram user IDs at
  INFO level or above. Log the internal student ID.
- Debug-level logging of content is allowed only in development, and must not be reachable
  in the production configuration.
- Error responses to Telegram users and to unauthenticated API callers carry a correlation
  ID and nothing else. Stack traces, SQL and internal identifiers stay in the logs.
- AI observability records may hold prompts, retrieved documents and responses, but that
  store is access-controlled exactly like the conversation it describes. Shipping raw
  conversation content to a third-party service is an architecture decision that needs the
  owner's approval and an ADR.

## Audit logging

Record who did what, separately from application logs, append-only:

- Mentor or admin reading a student profile or conversation
- Mentor assignment changes
- Knowledge base document added, updated, disabled or deleted
- Role or account changes
- Any pause or override of the AI on a conversation
- Failed authentication attempts

Each entry: actor, action, target, timestamp, source address. No message content.

## Sessions and transport

- HTTPS everywhere. No exceptions, no disabled certificate verification.
- Session tokens in HttpOnly, Secure, SameSite cookies. Never in `localStorage`.
- Sessions expire, and logout invalidates server-side.
- Password storage uses a modern memory-hard hash. Never a fast hash, never reversible.
- Compare tokens and signatures with a constant-time comparison.

## Rate limiting and abuse

- Rate limit inbound Telegram processing per student, and the AI call path in particular, so
  one student cannot exhaust the model budget.
- Rate limit authentication attempts per account and per source address.
- Cap AI spend per conversation and per day, and make exceeding the cap escalate to a human
  rather than fail silently.

## Data protection

- Encrypt secrets and credential columns at rest.
- Back up the database on a schedule, and test a restore before relying on it. A backup that
  has never been restored is not a backup.
- Deleting a student's data must be possible and must reach every store that holds it,
  including the vector index and the AI run records.

## Dependencies

Prefer a well-maintained dependency over a hand-rolled implementation for anything
cryptographic. Prefer no dependency at all for something small and stable. Before adding
one, check that it is maintained, that its permissions match its job, and that it does not
pull in a network client you did not want. Pin versions and keep a lockfile committed.

## Enforcement in this repository

Two files configure the `security-guidance` plugin, which reviews every change:

- `.claude/claude-security-guidance.md` gives the reviewer this project's threat model
- `.claude/security-patterns.json` adds deterministic per-edit pattern checks

Both are additive. Keep them in step with this skill when the model changes. Neither blocks a
write, so neither replaces the rules above.
