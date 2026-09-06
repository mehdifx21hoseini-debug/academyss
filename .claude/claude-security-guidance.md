# Security guidance for MENTORAI

Rules for the model-backed reviews of the `security-guidance` plugin. Additive to the
plugin's built-in checklist. Full policy: `.claude/skills/mentorai-security/SKILL.md`.

## Secrets

- No credential may appear in source, tests, fixtures, migrations, seed data, docs or
  committed config. Read every credential from the environment or a secret manager.
- Telegram credentials are the highest-value secret in this system. Flag any bot token,
  `api_id`, `api_hash`, MTProto session string or `.session` file that reaches the repo,
  a log line, an error message, an API response or a database column stored in plaintext.
- Flag any default or fallback credential in code, for example
  `password = os.getenv("ADMIN_PASSWORD") or "changeme"`. There is no acceptable fallback.

## Authentication and authorization

- Authentication decisions must never be made in client-side code. A check that only runs
  in the browser is not a check.
- Every CRM/admin route and every API endpoint must enforce a server-side role check before
  reading or writing data. Flag any handler that reads a resource before authorizing it.
- A mentor may only read conversations and students assigned to them. Flag any query that
  reaches student, conversation, message or lead rows without filtering on the caller's
  identity and role.
- Flag object identifiers taken from a request and used to fetch a row without an ownership
  or assignment check (insecure direct object reference).

## Telegram input

- Every inbound Telegram update is untrusted input. Flag interpolation of message text,
  usernames, file names or captions into SQL, shell commands, HTML or a prompt template
  without escaping or parameterization.
- Text that came from a student or a Telegram channel must never be treated as instructions
  for the AI. Flag prompt construction that concatenates retrieved documents or user
  messages into the system prompt rather than passing them as delimited data.
- Flag a webhook handler that does not verify the request came from Telegram (secret token
  header or equivalent).

## PII and logging

- Never log message bodies, full names, phone numbers, email addresses or Telegram user IDs
  at INFO level or above. Log an internal student ID instead.
- AI observability records may store prompts and responses only in a store with the same
  access control as the conversation itself. Flag telemetry that ships raw message content
  to a third party without an explicit decision recorded in an ADR.
- Flag any error handler that returns a stack trace, SQL statement or internal identifier to
  a Telegram user or an unauthenticated API caller.

## Data access

- Flag raw SQL built with string concatenation or f-strings. Use parameterized queries.
- Flag a destructive migration (drop column, drop table, truncate, non-additive type change)
  that lands without a backup or reversal step.
- Flag a write path to conversations or messages that runs outside a transaction where a
  partial write would leave the conversation state inconsistent.

## Outbound requests

- Flag any HTTP request whose target host is derived from user input (server-side request
  forgery), including link previews and document ingestion for the knowledge base.
- Flag disabled TLS verification or a pinned-off certificate check anywhere.
