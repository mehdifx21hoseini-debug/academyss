---
name: mentorai-testing
description: Testing standard for the MENTORAI AI mentoring platform - what "tested" is allowed to mean, the shape of the test suite, how to test Telegram update processing including duplicate and concurrent delivery, database tests against real Postgres, retrieval and escalation tests that tolerate model non-determinism, and the checks required before calling work done. Load before writing tests, before claiming a change works, before marking a task complete, and when adding or changing Telegram processing, the conversation engine, the decision layer, retrieval, memory, authentication or an API endpoint in MENTORAI.
license: MIT
---

# MENTORAI testing standard

## What "tested" means

A change is tested when its tests exist, were run in this session, and passed, and you can
quote the output. Nothing else earns the word.

Never describe as tested: code whose tests you wrote but did not run, code whose tests you
ran before the last edit, code covered only by a test you skipped, or code you reasoned
about carefully. If tests fail, say so and show the failure. If a part of the change is
untested, name that part explicitly rather than reporting the whole as done.

Never make a test pass by weakening it. Do not skip, disable, quarantine, loosen an
assertion or add a broad exception handler to get to green. A failing test is either a real
defect or a wrong test, and both are fixed by understanding the cause first.

## Shape of the suite

Weighted toward the bottom, but the middle carries this system.

- **Unit tests** for pure logic: Persian text normalization, chunking, the decision layer's
  rules, memory policy filters, prompt assembly, formatting.
- **Integration tests** for anything crossing a boundary: repository against a real
  database, the Telegram adapter against a fake transport, retrieval against a real index,
  the AI runtime against a stubbed model client.
- **End-to-end tests** for the handful of flows that must never break, listed below.

Speed matters only in the unit layer. An integration test that is slow because it uses a
real database is correct, not wasteful.

## Critical flows that need end-to-end coverage

1. A student sends a message and receives an AI answer, and the conversation and both
   messages are persisted with the right senders.
2. A message the AI should not answer escalates, the AI stops responding on that
   conversation, and the assigned mentor is notified.
3. A mentor replies, the reply is stored as a mentor message, and the AI stays silent while
   the human is engaged.
4. The AI resumes after the human intervention ends, only under the conditions that allow it.
5. A student arriving through a second identity resolves to the same student record and the
   same conversation history.
6. A mentor cannot read a student assigned to another mentor, through any endpoint.

## Testing Telegram processing

The channel is at-least-once and concurrent. Test it that way.

- **Duplicate delivery.** Feed the same update twice and assert exactly one message row,
  one AI run and one outbound send. Deduplication is a required behavior with a required
  test, not a nice-to-have.
- **Concurrent delivery.** Deliver two updates for the same conversation simultaneously and
  assert the conversation state is consistent and no message is lost or double-processed.
- **Out-of-order delivery.** Deliver updates out of sequence and assert ordering is
  reconstructed from the update's own ordering data, not from arrival time.
- **Failure mid-flight.** Fail the outbound send after the inbound message is stored and
  assert the retry does not duplicate the stored message.
- **Malformed and hostile updates.** Missing fields, empty text, very long text, media
  without a caption, text containing SQL and prompt-injection attempts. None may crash the
  worker or reach a query unparameterized.

Build one fixture factory for updates and derive every case from it, so a change to the
update shape touches one place.

Never call the real Telegram API from a test. The adapter takes a transport; tests pass a
fake one that records calls.

## Database tests

Run against real PostgreSQL, at the version production uses. SQLite substitution hides
exactly the behavior worth testing.

- Each test runs in a transaction that rolls back, or against a fresh schema. Tests never
  depend on each other's rows or on execution order.
- Test migrations by applying them to an empty database, and test that a destructive
  migration is caught by review before it is written, not after it runs.
- Assert the constraints exist: uniqueness that prevents duplicate messages, foreign keys,
  and the not-null columns the domain depends on. A constraint without a test is a comment.
- For scoped queries, write the negative test: assert the other mentor's rows are absent,
  not merely that the right rows are present.

## Retrieval tests

Model output varies. Assertions must be about behavior that does not.

- Keep a small fixed evaluation set of Persian questions with the passages that should be
  retrieved. Assert the expected passage appears in the top results, not that the output
  text matches a string.
- Test the retrieval pipeline's parts separately: normalization is deterministic and asserts
  exactly, chunking asserts boundaries and overlap, ranking asserts ordering on fixed inputs.
- Test that source class filtering works: a query restricted to official course material must
  not return a mentor's conversational answer.
- Test Persian specifically: text with and without the zero-width non-joiner, Arabic forms
  of letters that also exist in Persian, Persian and Arabic-Indic digits, and mixed
  Persian-English queries all reach the same passages.
- Track retrieval quality as a number over the evaluation set and fail the build when it
  drops, rather than asserting a threshold no one revisits.

## Decision layer and escalation tests

The decision layer is rule-driven and must be tested as rules, not as model behavior.

- Table-driven cases for each escalation reason: outside the knowledge base, low confidence,
  explicit request for a mentor, sensitive topic, complaint, money or account matters,
  personal decisions.
- Assert the recorded rationale, not only the outcome. If the reason is not recoverable from
  the record, the observability requirement is not met.
- Assert the fail-safe direction: when inputs are missing or the model call fails, the
  decision is to escalate, never to answer anyway.

## Memory tests

- Assert the memory policy's filter: content the policy excludes must not reach long-term
  memory, and the test names the category it is excluding.
- Assert short-term context has a bound and that the oldest content is what drops.
- Assert that deleting a student clears their long-term memory too.

## Authentication and authorization tests

For every endpoint, three cases minimum: no session, wrong role, right role but wrong
assignment. All three must be denied before the allowed case is worth asserting.

## Before calling anything done

Run, in this order, and report what happened:

1. The project's linter and formatter
2. Type checking, if the chosen language has it
3. Unit and integration tests for the changed area
4. The end-to-end flow that covers the change, if one exists
5. A read of your own diff, looking for what a reviewer would reject

Then state plainly what you ran, what passed, and what you did not cover.
