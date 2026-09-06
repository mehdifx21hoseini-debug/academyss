---
name: mentorai-review
description: Review checklist for MENTORAI changes - the project-specific defects that generic review misses, covering message deduplication and idempotency, transaction boundaries, mentor-scoped data access, Persian text and RTL correctness, secrets and PII, AI run observability, escalation fail-safe direction, configuration hardcoding, and whether documentation and architecture decision records were updated. Load when reviewing a diff, a pull request or your own change before committing in MENTORAI, and when deciding whether a change is ready to hand over.
license: MIT
---

# MENTORAI review checklist

Use this in addition to `/code-review`, not instead of it. The bundled review finds general
correctness defects. This list is the set of mistakes that are specific to this system and
expensive here.

Read the diff adversarially. The question is not "does this look reasonable" but "what input
or ordering makes this wrong".

## Message handling

- Does a repeated delivery of the same inbound message produce exactly one stored message,
  one AI run and one outbound send? Point at the mechanism, not the intention.
- Is the deduplication key one that Telegram actually guarantees, and is it enforced by a
  database constraint rather than a read-then-write check that two workers can both pass?
- If two messages for the same conversation are processed at once, can the conversation land
  in a state neither path intended?
- Does a retry after a partial failure re-send a message the student already received?
- Is a failure path that drops a message silent, or does it reach a dead-letter path someone
  can inspect?

## Transactions and state

- Does every write that spans more than one table run inside a transaction?
- Is the transaction scope tight, or does it hold a connection open across a model call or an
  HTTP request?
- After an error halfway through, is the conversation state consistent, or is there a message
  without its run record, or an escalation without a notified mentor?
- Are conversation status transitions explicit and enumerated, or inferred from whichever
  fields happen to be set?

## Access scoping

- Is every query that reaches students, conversations, messages, leads or notes scoped by the
  caller's role and assignment, in the query itself?
- Is an identifier from the request used to fetch a row before the caller is authorized
  against that row?
- Does a new endpoint have the three denial cases covered: no session, wrong role, wrong
  assignment?
- Does the CRM reach the database through the same authorized path as everything else, or has
  it acquired a private one?

## Persian and RTL

- Is user-supplied Persian text normalized on the same path before storage and before search,
  so the two agree? Zero-width non-joiner, Arabic forms of Persian letters, Persian and
  Arabic-Indic digits.
- Does a string operation assume one byte per character, or slice text in a way that can
  split a grapheme?
- Does new UI set direction explicitly rather than inheriting it, and does mixed
  Persian-English content render in the right order?
- Are numbers, dates and times presented in the form the audience expects, and stored in a
  single unambiguous form?

## Secrets and personal data

- Does any credential appear in the diff, including in a test fixture, a comment, an example
  file or a default value?
- Does a log line at INFO or above carry message content, a name, a phone number, an email
  address or a Telegram user ID?
- Does an error response to a student or an unauthenticated caller reveal a stack trace, a
  query or an internal identifier?
- Does new telemetry send conversation content anywhere outside the system, and if so, was
  that decided and recorded?

## AI behavior

- Is every model execution recorded with model, prompt version, latency, tokens, retrieved
  documents with their scores, the decision taken, the response and any error? A run that
  cannot be explained afterwards fails this check.
- Is retrieved content or student text concatenated into the system prompt, rather than
  passed as delimited data?
- When the model call fails, times out or returns something unparseable, does the system
  escalate to a human, or does it answer anyway or fail silently? The fail-safe direction is
  always toward the human.
- Is there a spend or rate bound on the AI path, and does exceeding it escalate rather than
  break?
- Does the change let retrieved content influence the escalation decision or the AI's
  identity? It must not.

## Configuration

- Is any value that differs between development and production written into the source?
  Timeouts, model names, limits, URLs, feature switches.
- Does configuration flow through the one typed configuration module, or does this code read
  the environment directly?
- Does a missing required setting fail loudly at startup, or fall back to a default that
  will be wrong in production?

## Tests

- Do the tests cover the failure and the duplicate, or only the happy path?
- Is there a negative authorization test, not just a positive one?
- Was the suite actually run after the last edit? If the answer is not a quoted result, the
  change is not ready.

## Documentation

- Does this change make `README`, `ARCHITECTURE`, `SETUP`, `ENVIRONMENT`, `DATABASE`, `API`,
  `DEPLOYMENT`, `SECURITY`, `TESTING` or `TROUBLESHOOTING` wrong? Fix it in the same change.
- Did this change close an open architecture question? Then it needs an entry in
  `docs/ARCHITECTURE_DECISIONS.md` with the decision, the reason, the alternatives and the
  trade-offs.
- Did it cross an approval gate listed in `.claude/skills/mentorai-architecture/SKILL.md`
  without approval? That is a blocking finding, whatever the code quality.

## Scope

- Does the diff do only what was asked? Unrelated refactors, renames and reformatting make a
  change hard to review and hard to revert.
- Is anything here speculative, built for a requirement that does not exist yet?

## Reporting

Lead with the most severe finding. For each one, name the file and line, describe the input
or ordering that makes it fail, and say what the fix is. Separate what blocks the change from
what is worth doing later. If nothing blocks it, say that plainly.
