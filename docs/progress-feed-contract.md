# Progress Feed — implementation contract (v1)

A per-project, Twitter-style timeline. Agents post short progress updates with optional
images and short muted looping clips; the boss reads them in the iOS app. This is a
**low-noise** surface: posting never sends a push, never enters the inbox, and never
touches the `messages` table or the delivery/notify machinery.

This document is the API contract shared by the server, CLI, HibossKit and iOS slices.
Where it is silent, use your judgement; prefer the simpler option and say what you chose.

## Decisions already made (do not relitigate)

| Decision | Choice |
|---|---|
| Storage | New `progress_posts` table. **Not** a `messages.type`. |
| Project identity | Plain text column supplied by the CLI (git-root basename). Not derived server-side. |
| Visibility | Boss token reads every accessible project; an agent key reads **only its own** posts. |
| Notifications | None in v1. No APNs, no channel fan-out, no delivery_queue. |
| CLI verb | `hiboss progress <post\|list\|rm>` |
| iOS placement | Replaces the **Messages** tab. |
| Animation | Short muted looping MP4, Twitter-style. Not animated GIF. |
| Live updates | Pull-to-refresh + refresh on appear. No SSE in v1. |

## Data model — `server/migrations/0026_progress_posts.sql`

```sql
CREATE TABLE IF NOT EXISTS progress_posts (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  session_id TEXT,
  project TEXT NOT NULL,
  body TEXT NOT NULL,
  media TEXT,                       -- JSON array of MediaItem, NULL when none
  tags TEXT,                        -- JSON array of strings, NULL when none
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_progress_created ON progress_posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_progress_project ON progress_posts(project, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_progress_agent ON progress_posts(agent_id, created_at DESC);
```

Mirror the table into `server/schema.sql` (that file tracks the consolidated final state).

### MediaItem (JSON, stored in `media`, echoed verbatim in API responses)

```jsonc
{
  "url": "https://<host>/api/attachments/<key>",  // required
  "kind": "image" | "video",                      // required
  "content_type": "image/png",                    // required
  "size": 20480,                                  // required, bytes
  "width": 1200,                                  // optional
  "height": 800,                                  // optional
  "duration_ms": 3200,                            // optional, video only
  "poster_url": "https://<host>/api/attachments/<key>", // optional, video only
  "alt": "screenshot of the new tab"              // optional
}
```

`width`/`height` exist so iOS can reserve the right aspect ratio before the image loads.
The CLI fills them when it can probe the file; both clients must tolerate them missing.

## Server — `server/src/routes/progress.ts`, mounted at `/api/progress`

Keep the file ≤ 300 lines; split helpers into `progress-helpers.ts` if needed.

### `POST /api/progress` — `apiAuth` (agent only)

Request:
```jsonc
{
  "body": "Shipped the progress feed. Migration + 4 endpoints.",  // required, 1..2000 chars
  "project": "hiboss",        // optional; falls back to the agent's name
  "session_id": "abc123",     // optional
  "media": [ MediaItem ],     // optional, max 4 items
  "tags": ["release"]         // optional, max 8 items
}
```
Validation: reject empty/whitespace-only `body` (400), `body` > 2000 chars (400),
> 4 media items (400), a MediaItem whose `kind` is not `image`/`video` (400), and a
MediaItem `url` whose origin is not this worker's own `/api/attachments/` path (400 —
this keeps the feed from rendering arbitrary remote URLs). Returns `201` + the full post.

### `GET /api/progress` — `dualAuth`

- Boss token: posts from every agent the boss can access (reuse the
  `getAccessibleAgentIds` pattern from `boss-api.ts` / `boss-inbox.ts`; `admin` = all).
- Agent key: `WHERE agent_id = <caller>` only. Never widen this.

Query params: `project` (exact match), `limit` (default 20, max 100), `before`
(ISO timestamp cursor, returns strictly older posts), `agent_id` (boss only).

Response: `{ "posts": [Post], "next_before": "2026-08-14T09:00:00Z" | null }`

### `GET /api/progress/projects` — `dualAuth`

Feeds the iOS filter control. Same visibility rules.
`{ "projects": [{ "project": "hiboss", "count": 12, "last_post_at": "...", "agent_id": "..." }] }`

### `GET /api/progress/:id` — `dualAuth`, same visibility rules, 404 when out of scope.

### `DELETE /api/progress/:id` — `dualAuth`. Author agent or any boss. 404 when out of scope.

### Post shape (all responses)

```jsonc
{
  "id": "…", "project": "hiboss", "agent_id": "…", "agent_name": "hiboss-cli",
  "session_id": "…" | null, "body": "…",
  "media": [MediaItem], "tags": ["…"], "created_at": "2026-08-14T09:00:00Z"
}
```
`media`/`tags` are always arrays in responses (never null). Join `api_keys.name` for
`agent_name`. Normalise `created_at` the same way existing routes do — match
`mapMessageRow`'s treatment so the Swift decoder sees one format, not two.

## Media upload — extend `server/src/routes/attachments.ts`

Today: 10 MB cap for every upload, whole body buffered via `arrayBuffer()`.

1. Raise the cap to **50 MB when the content type starts with `video/`**; keep 10 MB otherwise.
2. Restrict accepted types on the raw-binary path to `image/*` and `video/mp4`
   (plus `image/gif` — the CLI may still upload one when ffmpeg is unavailable).
3. Buffering 50 MB inside a Worker is the risk here. **Verify, do not assume**: try
   streaming `c.req.raw.body` straight into `ATTACHMENTS.put()` with the declared
   `content-length`, and fall back to `arrayBuffer()` if R2 rejects an unknown-length
   stream. Say in your report which one you shipped and what the test showed.
4. The multipart path keeps the 10 MB cap — the CLI uses raw binary for large media.

## CLI — `cli/src/commands/progress.rs` (+ `client/progress.rs`)

Repeatable singular flags only; never comma-joined lists, never a plural `--images`.

```
hiboss progress post "<body>" [--image <path>]… [--video <path>]… [--url <url>]…
                              [--project <name>] [--session <id>] [--tag <t>]… [--alt <text>]…
hiboss progress list [--project <name>] [--limit <n>] [--before <iso>] [--json]
hiboss progress rm <id>
```

- `--project` defaults to the basename of the git root already resolved in
  `cli/src/session.rs` (`resolve_project_dir`); reuse it, don't reimplement.
- `--session` defaults to the current session id from `session.rs`.
- Max 4 media items total; error clearly past that.
- **GIF → MP4**: when `--image`/`--video` is a `.gif` and `ffmpeg` is on PATH, convert to
  a muted, looping-friendly MP4 (yuv420p, `+faststart`) in a temp dir and upload that.
  No ffmpeg → upload the GIF as-is and warn on stderr that iOS shows a still frame.
- **Probe dimensions** with `ffprobe` when present (and `sips -g pixelWidth` on macOS for
  images as a cheap fallback); omit `width`/`height` when neither is available.
- **Video poster**: with ffmpeg, extract frame 0 as JPEG, upload it, set `poster_url`.
- Videos upload through a new raw-binary client method (`x-filename` header, streamed
  body); images may keep the existing multipart `upload_file`.
- `list` prints a compact human-readable feed by default (project · relative time · body,
  media as `[image]`/`[video 3.2s]` markers) and raw JSON under `--json`.
- Errors go to stderr, data to stdout, matching the other commands.

Register the subcommand in `cli/src/main.rs` and `cli/src/commands/mod.rs`.
Every new function needs at least one test; no `unwrap()` in production paths.

## HibossKit — `Sources/HibossKit/`

- `ProgressPost` + `ProgressMedia` `Codable`/`Sendable`/`Identifiable` models in a new
  `ProgressFeed.swift`, matching the JSON above and tolerant of missing optionals.
- `HibossAPI`: `progressFeed(project:limit:before:) async throws -> ProgressFeedPage`,
  `progressProjects() async throws -> [ProgressProject]`, `deleteProgressPost(id:)`.
  Follow the existing method style, error mapping, and `clientSource` conventions.
- Decoder tests covering: a post with no media, one with an image, one with a video that
  has a poster and duration, and one whose `width`/`height` are absent.

## iOS — replace the Messages tab

Read `docs/macos-design-v2.md` first: **native-first is a hard contract**. System controls,
semantic colours, Dynamic Type, SF Symbols. No hex literals in views, no `.system(size:)`,
no transcribed web palette. Build it and look at it before declaring done.

- `ios/App/Progress/` — `ProgressFeedView`, `ProgressPostCard`, `ProgressMediaView`,
  `ProgressFeedStore` (`@MainActor` `ObservableObject`, mirroring `InboxStore`'s shape:
  loading/loaded/empty/error states, `refresh()`, cursor pagination on scroll-to-end).
- `RootTabView`: swap the Messages tab for `Label("进展", systemImage: …)` — pick the SF
  Symbol that actually reads as a timeline and say which you chose. Tab order otherwise
  unchanged, so muscle memory for Inbox/Sessions/Settings survives.
- **Do not orphan `MessagesView`**: it is still reachable per-session from Sessions, but
  add a toolbar entry point (e.g. an "All messages" item in Inbox) that pushes the global
  `MessagesView`, so nothing that exists today becomes unreachable.
- Card: project name + relative time (reuse `RelativeTime`) + body + media. Tapping media
  opens a full-screen viewer with a swipe-to-dismiss gesture.
- Images: `AsyncImage` with an aspect-ratio placeholder derived from `width`/`height` when
  present, so the feed doesn't jump as images land.
- Video: `AVPlayer`, **muted + looping + autoplay when on screen**, tap to unmute, and it
  must pause when scrolled off screen and when the app backgrounds. A feed that keeps six
  players alive is the failure mode to avoid here.
- Filter by project via a native `Menu` in the toolbar, sourced from `/api/progress/projects`.
- Pull-to-refresh, plus a refresh when the tab is selected. No SSE.
- Empty state that explains how a post gets here (`hiboss progress post "…"`).
- Run `xcodegen generate` after adding files, and make sure the app builds.

## Out of scope for v1 (do not build)

Reactions/likes, comments, editing a post, SSE live updates, the web console surface,
the macOS client surface, server-side transcoding, and any push notification for a post.
