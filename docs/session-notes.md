# Session notes (留言)

Session notes are texts and images a boss leaves for one exact agent session. They are a
separate business type from messages: no channel delivery, push, inbox entry,
ask semantics, or quiet hours. They do not depend on the SSE daemon. Agent replies
are ordinary agent-to-boss messages linked to the note, with normal message delivery.

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
  "read_at": null,
  "images": [{ "index": 0, "content_type": "image/jpeg", "bytes": 123456 }],
  "replies": [{ "message_id": "message-id", "body": "Checked the output.",
    "agent_name": "Agent", "created_at": "2026-11-02 10:01:00" }]
}
```

Timestamps use SQLite's UTC `YYYY-MM-DD HH:MM:SS` format. `boss_name` is the boss's
current name, or `Deleted boss` if its row was physically deleted. Bodies are trimmed
and limited to 4000 Unicode characters. A note requires a non-empty body or at
least one image. `images` is always present, ordered by index, and empty when none.

Migration `0066_session_note_images.sql` adds `session_note_images` with required
`note_id` (references `session_notes(id)`), `idx`, `content_type`, `bytes`, and
`r2_key`; `(note_id, idx)` is the primary key. Images live in the `ATTACHMENTS` R2
bucket under `notes/<note_id>/<idx>`. They belong only to their note, never Box.
Public `/api/attachments/*` GET/HEAD requests refuse `notes/` keys with 404.

Each note accepts 0..4 images, each at most 10 MB (10 × 1024 × 1024 bytes).
Allowed declared types are `image/jpeg`, `image/png`, `image/heic`, `image/webp`,
and `image/gif`; leading bytes must match. Spoofed or unsupported types return 400;
oversized images return 413. Uploads precede the atomic D1 insert. Failed inserts
leave no note, retry-key or image rows; orphaned uploads are deleted best-effort.

## Boss API

Boss token authentication is required. Admins can access all agents; managers and
viewers can access granted agents. Unknown or inaccessible sessions return 404;
IDs must match exactly. Inactive and completed sessions accept notes.

- `POST /api/boss/sessions/:id/notes`, JSON `{ "body": "text" }`: returns the note
  with 201. Also accepts `multipart/form-data` with text field `body` and repeatable
  file parts named `image`; body may be empty when images exist. Invalid bodies return 400; viewers cannot write (403).
- Optional `Idempotency-Key`: the same boss, session and key return the original
  note with 200. A changed retry body does not replace the original body. Retry
  images are returned unchanged and no new objects or image rows are stored. Retry
  keys are stored separately in `session_note_keys` and claimed atomically with
  creation; keys do not expire.
- `GET /api/boss/sessions/:id/notes`: returns `{ "notes": [Note] }`, newest first,
  at most 50. Viewers may read. Ties use insertion order.

- `GET /api/boss/sessions/:id/notes/:noteId/images/:index`: image bytes with their
  content type and `Cache-Control: private, max-age=3600`. Viewers may read. Returns
  404 for inaccessible sessions, wrong note/session pairing or missing image index.

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

- `GET /api/sessions/:id/notes/:noteId/images/:index`: same image response, only
  for the owning agent; foreign sessions and wrong note/session pairs return 404.

## Agent replies (v3)

`POST /api/messages` accepts `metadata.note_id` as a non-empty string. The message
must be agent-to-boss (no `to`), async, without options or attachments, and text only.
It requires a `session_id` owned by the sender and a note with that exact session
and agent. Invalid combinations, missing notes, and foreign notes return 400 before
inserting a message or link. The normal signing, idempotency, destinations, push,
quiet-hours and inbox pipeline applies unchanged; signatures cover `note_id`.

Migration `0067_session_note_replies.sql` adds `session_note_replies`, with required
`note_id` and `message_id` foreign keys, `created_at DEFAULT (datetime('now'))`, a
`(note_id, message_id)` primary key, and a message ID index. The link and pending-to-read
transition share the message insert's atomic batch. Only pending notes get a new
`read_at`; retries create no second message or link.

All note JSON includes `replies`, empty when none, oldest first with insertion order
breaking timestamp ties. Each reply contains `message_id`, displayable `body`
(`metadata.content` when non-empty, otherwise message `body`), current `agent_name`,
and link `created_at`. Listings fetch replies for all selected notes in one query.

## CLI and hooks

```sh
hiboss note read          # print every pending note, then mark them read
hiboss note read --json   # print { "notes": [...] }, then mark them read
hiboss note list          # pending notes, without marking
hiboss note list --all    # pending and read notes, without marking
hiboss note list --json   # structured output without marking
hiboss note reply <note-id> "Checked the output."
hiboss note reply <note-id> "Detailed response" --content-file response.md
```

Commands use the current registered session. Text output includes boss name, time,
status, ID and full body, then replies and `Reply: hiboss note reply <note-id> "<text>"`,
or a clear no-pending-notes message. Reply uses the same signed client send path as
`hiboss send` and prints the server message ID. Its text is a title of at most 144
Unicode characters; `--content-file` loads full UTF-8 Markdown details like send.
JSON output uses the
API envelope, including an empty `notes` array. Read acknowledgement follows a
successful stdout flush, in batches of at most 50. Both read and list download
images to `<cache>/hiboss/notes/<note_id>/<index>.<ext>` with 0700 directories and
0600 files. Complete files are reused; partial downloads are never cached. Text
prints each local path, type and size with an instruction to open it. JSON adds
`images[].path` for downloaded images. A failed image prints its error to stderr;
that note stays unread while other fully downloaded notes can be acknowledged. A failed acknowledgement exits
non-zero, so already printed notes may be printed again on retry.

The detached `bg-check` fetches pending IDs on every run and atomically writes a
private state file. A 15-second note TTL triggers it alongside the existing TTLs.
PostToolUse performs local I/O only and announces new IDs:

```text
BOSS NOTE (留言): the boss left N note(s) with M image(s) for this session. Read them now: hiboss note read
```

Still-unread notes are re-announced no more than once every five minutes. New IDs
may trigger an earlier announcement. SessionStart also polls and announces pending
notes. Pending and announcement state include the session ID to reject stale state.
Polling failures preserve the last successful snapshot. The Codex hook adapter
uses the same lifecycle path and inherits the detached poller's session context.
