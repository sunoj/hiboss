# Session Stream — implementation contract (v1)

Turns a session screen from "a filtered slice of the last 100 messages" into a **real-time,
complete, resumable stream** of everything that happened in one agent session — every
direction, in order, replayable after a disconnect.

Grounded in `docs/research-session-stream.md`; read that first for the evidence behind these
choices. Where this document is silent, use your judgement; prefer the simpler option and say
what you chose.

## Decisions already made (do not relitigate)

| Decision | Choice |
|---|---|
| Model | An append-only **event log**, with `messages` kept as the message projection. Not a terminal emulator. |
| Ordering | A server-assigned **per-session `sequence`**, not wall-clock time. |
| Transport | SSE, with a cursor and replay. WebSocket only if commands ever flow the other way. |
| Resume | `after=<sequence>` on both history and stream; SSE `id:` carries the sequence. |
| Terminal rendering | Not now. Only when a real producer emits ANSI, and then only inside a row. |
| Existing streams | `/api/boss/stream` (options + feed) stays as-is. This is a new, session-scoped surface. |

## Data model — `server/migrations/0028_session_events.sql`

```sql
CREATE TABLE IF NOT EXISTS session_events (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  session_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  kind TEXT NOT NULL,                    -- open string; see the taxonomy below
  direction TEXT,                        -- mirrors messages.direction when applicable
  actor_agent_id TEXT,
  target_agent_id TEXT,
  message_id TEXT,                       -- REFERENCES messages(id) when the event projects one
  source TEXT,                           -- JSON: record_type, record_uuid, parent_uuid, source_version, line_ordinal
  payload TEXT,                          -- JSON, normalized per kind
  raw TEXT,                              -- JSON: the original source record, retained verbatim
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (session_id, sequence)
);

CREATE INDEX IF NOT EXISTS idx_session_events_cursor ON session_events(session_id, sequence);
```

Note `created_at` uses `strftime(... '%f' ...)` for **milliseconds**. `datetime('now')` is
second-resolution and has already caused one real ordering bug in this repo; the sequence is
what orders events, and the timestamp is for display only.

### Sequence allocation

Allocate inside the same D1 `batch()` as the write it belongs to. D1 serialises a single
database's queries, so `MAX(sequence)+1` scoped to the session is safe; make the uniqueness
constraint the backstop rather than the plan. A failed insert must fail the write it belongs
to, not silently skip the event — a gap in the sequence is worse than an error, because the
client cannot tell a gap from a dropped connection.

### Backfill

The migration must **backfill events from existing `messages`**, ordered by
`(created_at, id)`, so sessions that already exist open with their history rather than
appearing empty. Say in your report how many rows that produced.

## Writers — the part most likely to be got wrong

Every path that inserts into `messages` with a `session_id` (or `target_session_id`) must
append a corresponding event in the same batch. Find them all: agent→boss, boss→agent
replies, agent→agent, channel-originated replies (Discord/Telegram webhooks), option
resolutions, and the scheduled expiry sweep.

**Miss one and the stream silently omits that message** — no error, no test failure, just an
incomplete transcript that nobody notices until they are reading a conversation with a hole
in it. Enumerate the write sites you found in your report, and add a test per site.

Note the known trap: a reply currently sets `target_session_id` and **not** `session_id`
(this caused a real bug in the iOS client today). The event's `session_id` must resolve to
the session the conversation belongs to, whichever column carries it.

## API

### `GET /api/sessions/:id/events` — `dualAuth`, existing session visibility rules

Query: `after` (sequence, exclusive), `limit` (default 100, max 500).
Response: `{ "events": [Event], "next_after": <sequence> | null, "resync": false }`

If `after` predates retained history, return `{ "events": [], "resync": true }` and let the
client reload a fresh window. Never return a silently truncated range.

### `GET /api/sessions/:id/stream` — `dualAuth`

SSE. Accepts `after=<sequence>` or the `Last-Event-ID` header; replays everything after that
cursor, then tails. Every frame carries `id: <sequence>`. Keepalive and duration cap follow
the existing boss stream's shape; on reconnect the client resumes from its last applied
sequence, so a cap is no longer data loss.

### Event shape

```jsonc
{ "id": "…", "session_id": "…", "sequence": 42, "kind": "message",
  "direction": "agent_to_boss", "actor_agent_id": "…", "actor_name": "worker-payments",
  "target_agent_id": null, "message_id": "…",
  "source": { "record_type": "assistant", "record_uuid": "…", "parent_uuid": "…",
              "source_version": "…", "line_ordinal": 123 },
  "payload": { "body": "…", "priority": "high", "options": ["…"], "type": "approval_request" },
  "raw": { "…the original record, verbatim…" },
  "created_at": "2026-08-14T09:00:00.123Z" }
```

### Taxonomy — grounded in the real Claude Code format

`docs/research-claude-code-format.md` characterised the actual transcripts on this machine:
**19 top-level record types**, nested content blocks, a UUID parent graph, and separate
child transcripts for sub-agent runs. The taxonomy is therefore:

`message` · `tool_call` · `tool_result` · `system` · `hook` · `compaction` · `control` ·
`file_history` · `error` · `raw`

**`kind` is an open string, not a closed enum.** So are record types, block types, tool
names and hook events. A value we have never seen must be stored, counted and rendered
through a fallback — never dropped, and never a reason to fail the stream.

The `raw` column is part of the design, not a temporary escape hatch. The on-disk format is
undocumented and drifts; a normalized projection alone would silently lose whatever we did
not anticipate, and there would be no way to recover it after the fact.

Two consequences worth stating plainly:

- **Claude's records carry no durable global ordering** — no top-level sequence, index or
  byte offset. Our per-session `sequence` is the only order that exists. Do not attempt to
  reconstruct order from timestamps or the UUID graph.
- **Pairing is a relation, not a merge.** Pair `tool_call` with `tool_result` by
  `tool_use_id` when both are present, but still store unpaired calls and results. A missing
  or late partner must not delete a row.
- Preserve the distinction between absent, `null`, `false`, empty string and empty array
  when the source draws it; the corpus shows those differences carry meaning.

## iOS

A `SessionStreamStore` per open session, replacing the "filter the shared 100-row history"
approach in `SessionMessagesView`:

- Loads a bounded window via the history endpoint, then opens the stream from the same cursor.
- **Appends** events; never refetches the whole history on each event.
- Batches UI updates — a burst of events must not mean a layout pass per event.
- Keeps a bounded rendered window with backfill on scroll-up.
- **Bottom-following with an explicit scroll lock**: it follows live output until the reader
  scrolls up, then stops and offers a "jump to live" affordance. A view that yanks the reader
  back to the bottom mid-read is the single most irritating thing this screen can do.
- On foreground and on reconnect, resumes from the last applied sequence; on `resync: true`,
  reloads the window and says so rather than showing a hole.
- Dense and legible. Presentation: `message` events are SMS-style bubbles (boss trailing,
  agents leading); every other kind — including unknown — is a slim centred system line.
  Monospace for raw output regions only, respecting Dynamic Type. Data model, streaming,
  cursor and scroll-lock are unchanged.

Native-first still binds (`docs/macos-design-v2.md`). New strings go through the String
Catalog with zh-Hans / ja / ko (ja/ko needs-review).

## Out of scope for v1 (do not build)

Sub-message streaming (token/chunk events), ANSI/terminal rendering, WebSocket, sending from
this screen, the macOS and web surfaces, and any retention/archival policy beyond keeping
events indefinitely.
