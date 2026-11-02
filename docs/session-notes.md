# Session notes (留言)

Session notes are short texts a boss leaves for one exact agent session. They are a
separate business type from messages: no channel delivery, push, inbox entry,
ask/reply semantics, or quiet hours. They do not depend on the SSE daemon.

## Storage and representation

Migration `server/migrations/0065_session_notes.sql` creates `session_notes` with
`id` (TEXT primary key), `session_id` (required session reference), `agent_id`,
`boss_id`, `body`, `status`, `created_at` (default `datetime('now')`), and nullable
`read_at`. Required fields are non-null. The `(session_id, status)` index supports
polling. The only states are `pending` → `read`. Read acknowledgement is idempotent.
A session with notes remains a completed history row when deregistered.

Every note returned by the API has exactly this shape:

```json
{
  "id": "note-id",
  "session_id": "session-id",
  "agent_id": "agent-id",
  "boss_name": "Boss",
  "body": "Please check the final output.",
  "status": "pending",
  "created_at": "2026-11-02 10:00:00",
  "read_at": null
}
```

Timestamps use SQLite's UTC `YYYY-MM-DD HH:MM:SS` format. `boss_name` is the boss's
current name. Bodies are trimmed and limited to 1..4000 Unicode characters.

## Boss API

Boss token authentication is required. Admins can access all agents; managers and
viewers can access granted agents. Unknown or inaccessible sessions return 404;
IDs must match exactly. Inactive and completed sessions accept notes.

- `POST /api/boss/sessions/:id/notes`, JSON `{ "body": "text" }`: returns the note
  with 201. Invalid bodies return 400; viewers cannot write (403).
- Optional `Idempotency-Key`: the same boss, session and key return the original
  note with 200. A changed retry body does not replace the original body. Retry
  keys are stored separately in `session_note_keys` and claimed atomically with
  creation; keys do not expire.
- `GET /api/boss/sessions/:id/notes`: returns `{ "notes": [Note] }`, newest first,
  at most 50. Viewers may read. Ties use insertion order.

## Agent API

Agent key authentication is required. The session must belong to the caller;
unknown, foreign, or prefix-only session IDs return 404.

- `GET /api/sessions/:id/notes?status=pending|all`: returns `{ "notes": [Note] }`,
  oldest first, with insertion order breaking timestamp ties. Default is `pending`;
  unsupported status values return 400. Agent lists have no 50-note truncation.
- `POST /api/sessions/:id/notes/read`, JSON `{ "ids": ["note-id"] }`: requires
  1..50 strings (400 otherwise). Returns `{ "read": n }`, counting only notes
  changed from pending to read. IDs outside that session or agent are ignored.
  A successful transition sets `read_at`; retries leave it unchanged.

## CLI and hooks

```sh
hiboss note read          # print every pending note, then mark them read
hiboss note read --json   # print { "notes": [...] }, then mark them read
hiboss note list          # pending notes, without marking
hiboss note list --all    # pending and read notes, without marking
hiboss note list --json   # structured output without marking
```

Commands use the current registered session. Text output includes boss name, time,
status, ID and full body, or a clear no-pending-notes message. JSON output uses the
API envelope, including an empty `notes` array. Read acknowledgement follows a
successful stdout flush, in batches of at most 50. A failed acknowledgement exits
non-zero, so already printed notes may be printed again on retry.

The detached `bg-check` fetches pending IDs on every run and atomically writes a
private state file. A 15-second note TTL triggers it alongside the existing TTLs.
PostToolUse performs local I/O only and announces new IDs:

```text
BOSS NOTE (留言): the boss left N note(s) for this session. Read them now: hiboss note read
```

Still-unread notes are re-announced no more than once every five minutes. New IDs
may trigger an earlier announcement. SessionStart also polls and announces pending
notes. Pending and announcement state include the session ID to reject stale state.
Polling failures preserve the last successful snapshot. The Codex hook adapter
uses the same lifecycle path and inherits the detached poller's session context.
