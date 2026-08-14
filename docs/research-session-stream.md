# iOS session stream research and decision

## Recommendation

Build a purpose-built, append-only session event stream and a native transcript view. Keep SSE for the first transport, but give every event a per-session ordered cursor and make the stream replayable after disconnect. Add terminal rendering only for event payloads that genuinely contain terminal bytes or ANSI control sequences.

This is a hybrid in the narrow sense that a transcript row may embed a terminal-output region; it is not a terminal emulator as the primary model. The product goal is a conversation among agent, boss, and peer agents. A terminal emulator can render bytes, colors, cursor movement, scrollback, and selection, but it cannot provide the missing conversation semantics: direction, sender, session membership, message identity, replies, or resumable server history.

The deciding question is: does “reads like watching a terminal” mean exact terminal behavior, including cursor movement and screen rewriting, or does it mean a dense, monospace, append-only live log? The stated requirement (“complete P2P conversation”, every direction, and phone reading) favors the latter. If exact terminal behavior becomes a requirement, use SwiftTerm inside a separate output pane, not as the transport or persistence design.

### What to build first

1. Define and test the event contract before changing the view: `event_id`, `session_id`, a per-session `sequence`, ingest timestamp with fractional precision, direction, source/target agent, event kind, message id, and payload. Include message-created events and a separate chunk/output event if agents can stream partial text.
2. Persist those events append-only, with a unique `(session_id, sequence)` and an index that supports `session_id + sequence > cursor`. Keep the existing `messages` table as the message projection; do not pretend it is a transcript log.
3. Add a session history endpoint plus SSE that accepts a cursor, replays events after it, then tails new events. Send standard SSE `id:` values and support `Last-Event-ID` or an explicit `after` cursor. A cursor older than retained history must produce an explicit “resync required” response.
4. Add an iOS session-stream store that consumes events directly, batches UI updates, keeps a bounded rendered window, and backfills on foreground/reconnect. Implement bottom-following with an explicit scroll lock and “jump to live” affordance.
5. Only then decide whether any payload needs SwiftTerm. Start with ordinary transcript rows and a raw-output renderer; add a terminal surface when a real producer emits terminal control sequences.

Confidence: high for the recommendation; medium for the exact event schema because the agent producer contract was not inspected in this task.

## Honest gap analysis

### What the repository does today

The inspected implementation is a message inbox, not a session stream:

| Area | Verified behavior | Consequence |
|---|---|---|
| `/api/boss/stream` default | `bossStreamLoop` is SSE. It polls D1 every 3 seconds, sends a 15-second keepalive, runs for at most five minutes, selects only `agent_to_boss` rows with `status = 'sent'`, and changes each delivered row to `delivered`. [`boss-api.ts`](../server/src/routes/boss-api.ts#L489-L540) | The iOS stream is a decision-notification channel, not a full session feed. |
| `/api/boss/stream?feed=true` | `streamBossFeed` is passive SSE over all message directions visible through `agent_id` or `target_agent_id`; it also polls every 3 seconds, keeps alive every 15 seconds, and caps the connection at five minutes. [`boss-feed-stream.ts`](../server/src/routes/boss-feed-stream.ts#L1-L67) | This is closer to the needed feed, but it is not session-specific, not resumable, and still only emits whole message rows. |
| Stream cursor | Both loops initialize an in-memory timestamp cursor using `YYYY-MM-DD HH:MM:SS`, order only by `created_at`, and keep a process-local `Set` of seen ids. There is no SSE `id`, `Last-Event-ID`, or durable offset. | Ties are not deterministically ordered; reconnecting after a dropped connection cannot ask for “everything after event N”. The five-minute cap is followed by a reconnect with no durable resume point. |
| Persisted granularity | `messages.body` is one `TEXT` value per row. `created_at` and `updated_at` default to SQLite `datetime('now')`; there is no sequence, chunk, byte offset, or event table. [`schema.sql`](../server/schema.sql#L20-L50) | Token deltas, terminal output fragments, edits, and precise interleaving are not recoverable after the fact. |
| Session persistence | `sessions` stores registration metadata, status, `started_at`, and `last_seen_at`; it has no event history or cursor. [`schema.sql`](../server/schema.sql#L170-L188) | A session is currently a grouping key and heartbeat record, not a durable stream. |
| iOS history | `HibossAPI.fetchHistory()` asks for `direction=all` but only the configured history limit of 100. [`HibossAPI.swift`](../HibossKit/Sources/HibossKit/HibossAPI.swift#L73-L84), [`AppConstants.swift`](../HibossKit/Sources/HibossKit/AppConstants.swift#L7-L12) | A long session is truncated before the session screen sees it. |
| iOS live path | `HibossAPI.messageStream()` connects with `options=true`, not `feed=true`. `InboxStore` reacts to a message by refetching history rather than appending the streamed payload. [`HibossAPI.swift`](../HibossKit/Sources/HibossKit/HibossAPI.swift#L47-L59), [`InboxStore.swift`](../ios/App/Inbox/InboxStore.swift#L145-L183) | Session UI does not receive live all-direction events and pays for a full refresh per notification. |
| Session screen | `SessionMessagesView` filters the shared 100-row history, sorts by parsed timestamps, and renders a native `List` of two-line-ish `HistoryRow` cells. [`MessageDetailView.swift`](../ios/App/Inbox/MessageDetailView.swift#L240-L274), [`HistoryRow.swift`](../ios/App/Inbox/HistoryRow.swift#L8-L48) | It is a coarse message list. It has no live-tail state, scroll lock, line-level selection, terminal styling, or bounded transcript window. |
| Lifecycle | On foreground, the shell refreshes history because SSE may have been dropped. [`RootTabView.swift`](../ios/App/Shell/RootTabView.swift#L74-L78) | The existing recovery is snapshot refresh, not cursor-based gap recovery. |

There is one important ambiguity to preserve: the server already has an all-direction passive feed, so “the server emits nothing in the other directions” would be false if referring to `feed=true`. The precise finding is that the iOS client does not consume that feed, the default stream is agent-to-boss only, and neither path emits sub-message events or provides resumability.

### Required server changes

**Granularity.** Add an append-only event projection. A message-created event is enough for the first useful milestone; it will make all three directions visible. A terminal-like stream additionally needs producer-side chunks or terminal frames. A database trigger cannot invent token timing or terminal control bytes that were never persisted. Do not overload `messages.updated_at` to represent deltas.

**Ordering.** Use a server-assigned sequence, preferably per session, rather than wall-clock ordering. If one screen can combine several sessions, either use a global ingest order or define that the screen merges per-session sequences with an explicit tie policy. Keep the timestamp for display only. D1 serializes a single database's queries, which makes a transactional sequence allocation feasible, but the contract still has to make the allocation explicit.

**Resume.** The read path should be: bounded history `after=cursor`, then live SSE from the same cursor. The server must deduplicate replay/live overlap by event id, and the client must persist the last applied cursor in memory (and optionally a short-lived local cache). A reconnect must not start “now”. If retention has deleted the cursor range, return a resync marker and reload a fresh snapshot.

**Transport.** SSE is adequate for a boss screen that only receives events. The current Swift client already consumes SSE through `URLSession.bytes(for:)` and an incremental line decoder. [`HibossAPI.swift`](../HibossKit/Sources/HibossKit/HibossAPI.swift#L169-L187) WebSocket is justified if the same connection must carry commands, presence, acknowledgements, or many bidirectional live interactions. Durable Objects are useful as a per-session fan-out/coordinator, not as a substitute for the durable event log.

**Retention.** Define two policies separately: how long the durable transcript remains queryable, and how much live/replay buffer is held for reconnect. Current `expires_at`/`expired` behavior is for expiring option messages, not transcript retention; the scheduled job only sweeps due options and drains delivery work. [`scheduled.ts`](../server/src/scheduled.ts#L29-L50) A session viewer needs an explicit retention horizon, deletion behavior, and a “history no longer available” response. If long raw output is retained, consider cold archival in R2 while keeping a queryable index in D1.

### Cloudflare fit

| Requirement | Workers + D1 assessment |
|---|---|
| Stream an HTTP response | Easy. Workers supports `ReadableStream`/`TransformStream` response bodies, and the existing route already uses that pattern. [Workers Streams](https://developers.cloudflare.com/workers/runtime-apis/streams/) |
| Append events and query after a cursor | Easy at this scale with a table, composite index, and prepared statements. D1 explicitly recommends indexes for predicate columns. [D1 indexes](https://developers.cloudflare.com/d1/best-practices/use-indexes/) |
| Atomic event + message projection | Feasible with D1 `batch()`/transaction semantics; keep the write set small. [D1 database API](https://developers.cloudflare.com/d1/worker-api/d1-database/#batch) |
| Thousands of clients polling one D1 database | Harder. Each D1 database is single-threaded, and polling consumes queries even when no event arrives. [D1 limits](https://developers.cloudflare.com/d1/platform/limits/) |
| Push/fan-out without polling | Not provided by D1 itself. Add a Durable Object or another broker if low-latency fan-out becomes necessary. Durable Objects can coordinate WebSockets and hibernate while idle. [DO WebSockets](https://developers.cloudflare.com/durable-objects/best-practices/websockets/) |
| Global read latency | Possible but not automatically safe for a live cursor. D1 read replicas are asynchronous; use the primary or D1 Sessions consistency behavior for a cursor-sensitive replay. [D1 read replication](https://developers.cloudflare.com/d1/best-practices/read-replication/) |
| Durable retention | D1 is adequate for bounded text events, subject to database/storage limits; R2 is a better cold archive. Neither D1 nor Durable Objects supplies the product's retention policy automatically. |

The practical first step is therefore D1 event persistence plus replayable SSE. A Durable Object should be introduced only when measured D1 polling cost/latency or fan-out requirements justify it.

## Mobile-specific hard parts

### Incremental append at thousands of lines

The current design refetches and replaces a `[HistoryMessage]` snapshot. A live transcript needs an append-oriented store, event batching, and a rendering window. Updating SwiftUI once per token will cause layout and main-actor churn; coalesce events for a short interval and append immutable batches. Keep older events in a paged model or local store while rendering only the visible range plus a bounded tail. Test with synthetic sessions containing thousands of short lines and a few very long lines, not only with normal inbox data.

SwiftTerm's engine is designed around a terminal buffer/scrollback model and advertises optional Metal rendering, Unicode/grapheme handling, and fuzz/compliance tests. That is evidence that a terminal surface can be made fast, but not evidence that it solves this app's transcript model. [SwiftTerm README](https://github.com/migueldeicaza/SwiftTerm/blob/main/README.md#features)

### Autoscroll and scroll lock

“Always scroll to the last row” is wrong as soon as the reader drags upward. Use a bottom proximity threshold, a locked/unlocked state, and a visible “jump to live” button. Incoming batches may update the unread count without moving the viewport while locked. Exyte Chat exposes a scroll-to-bottom button, content-offset observation, programmatic scrolling, load-more callbacks, and an update transaction that can preserve a stable offset. Those are the right interaction primitives even if its message UI is not adopted. [Exyte Chat README](https://github.com/exyte/Chat#modifiers)

### Selection and copy

The existing app enables selection only in the single-message detail view; the session rows themselves are not a selectable transcript surface. A purpose-built view should support long-press copy for one event, copy-all-visible, and copy-all-session without forcing the user to select thousands of rows. SwiftTerm has a selection engine, but its README explicitly calls out selection/accessibility as an area where it is not equivalent to all terminal peers. [SwiftTerm README](https://github.com/migueldeicaza/SwiftTerm#history)

### Monospace, Dynamic Type, and narrow widths

Terminal grids prefer fixed columns; a phone transcript prefers readable wrapping. These are different layout contracts. Choose a user-controlled monospace size or a Dynamic Type-aware text style for transcript rows, wrap long paths/URLs, and test portrait, landscape, large accessibility sizes, and right-to-left text. An exact terminal pane should remeasure columns on width changes and accept that wrapping/reflow differs from ordinary text. SwiftTerm's Unicode, grapheme, bidirectional-text, and CoreText claims make it a strong renderer for that pane; they do not remove the need to choose a narrow-screen policy.

### ANSI and colour

The current `body` column has no documented ANSI or terminal-byte contract. If future producers send ANSI, either parse it into safe attributed spans or pass it to a terminal engine. SwiftTerm verifies support for ANSI, 256-colour, TrueColor, and common text attributes. [SwiftTerm README](https://github.com/migueldeicaza/SwiftTerm#features) A transcript renderer should strip unsupported cursor/control operations rather than display escape bytes or allow them to mutate unrelated rows.

### Backgrounding, reconnect, and battery

The app already cancels/restarts its inbox stream and uses capped exponential backoff; it also refreshes history when active. [`InboxStore.swift`](../ios/App/Inbox/InboxStore.swift#L145-L173), [`RootTabView.swift`](../ios/App/Shell/RootTabView.swift#L74-L78) Extend that behavior with the last applied event cursor. On foreground, request `after=cursor`; do not rely on the stream having survived background suspension.

For battery, pause the live session subscription when the screen is not visible or the app is backgrounded, coalesce UI updates, and let the server push rather than making every connected client issue a D1 query every three seconds. A Durable Object's hibernating WebSocket API is specifically designed to keep clients connected while the object sleeps, but it adds a new coordination path and does not remove the need for D1/R2 retention. [Cloudflare DO WebSockets](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)

## Distinct implementation directions

### A. Real terminal emulator

Adopt SwiftTerm's engine and iOS `TerminalView`, wrapped for SwiftUI as needed. It is MIT licensed, has a long public history (over 1,000 commits in the inspected repository), bundled iOS/UIKit and macOS/AppKit front ends, compliance/fuzzing work, and is named by its README as being used in Secure Shellfish, La Terminal, and CodeEdit. [README](https://github.com/migueldeicaza/SwiftTerm), [license](https://github.com/migueldeicaza/SwiftTerm/blob/main/LICENSE), [package manifest](https://github.com/migueldeicaza/SwiftTerm/blob/main/Package.swift)

It buys exact terminal parsing, ANSI colour, cursor movement, scrollback, terminal selection, and a renderer already exercised beyond this app. The adoption cost is substantial: UIKit integration into a SwiftUI screen, a byte/frame protocol from the server, terminal resize/reflow decisions, direction/sender overlays outside the terminal, accessibility validation, and a separate transcript/history model. It would be the wrong primary model if the producer emits messages rather than terminal bytes.

### B. Purpose-built streaming transcript

Keep the product model as ordered events and implement a native dense transcript with a virtualized list or a UIKit-backed collection/table view. Exyte Chat is a useful reference rather than a drop-in: it is MIT licensed, has about 700 commits in the inspected repository, supports pagination, scroll-to-bottom, content-offset control, stable update transactions, and long-press menus; its README identifies a `UITableView`-oriented API in the scrolling modifiers. [README](https://github.com/exyte/Chat), [license](https://github.com/exyte/Chat/blob/main/LICENSE), [package manifest](https://github.com/exyte/Chat/blob/main/Package.swift)

This buys correct direction/sender/session semantics, Dynamic Type-friendly rows, copy/search/filter features, and control over the retention/window policy. The cost is building and testing ANSI handling if it later appears, append performance, selection, bottom-following, and the server event contract. This is the recommended direction because it solves the actual product object.

### C. Hybrid transcript plus terminal subviews

Use the purpose-built event stream and transcript for the conversation. Render selected event kinds—tool output, shell output, or a raw terminal attachment—in a SwiftTerm-backed region with copy/fullscreen affordances. This preserves sender/direction/timestamp metadata while offering terminal fidelity where it is useful.

It buys the broadest future coverage, but costs two renderers, two sets of performance/accessibility tests, a routing rule for which event kinds use terminal semantics, and more complicated persistence. Choose it if agents demonstrably emit terminal control sequences or continuously updating tool panes. Do not choose it merely because the desired visual density resembles a terminal.

## Survey: agent transcripts and log viewers

### Claude Code JSONL: verified facts and limits

Anthropic's current Agent SDK documentation verifies that session transcripts are JSONL under `~/.claude/projects/`, that a `SessionStore` mirrors batches through `append` and reloads them through `load`, that a session key contains `projectKey`, `sessionId`, and optional `subpath`, and that subagent transcripts use subpaths. It also says the SDK does not delete from a custom store; retention is the adapter's responsibility. [Anthropic session storage](https://code.claude.com/docs/en/agent-sdk/session-storage)

The exact on-disk line schema is not presented as a stable official public contract in the inspected documentation. Anthropic's public issue requesting a documented schema records observed top-level types such as `user`, `assistant`, `system`, `attachment`, `custom-title`, and `queue-operation`, while explicitly warning that additions and stability are uncertain. [Claude Code issue #53516](https://github.com/anthropics/claude-code/issues/53516)

Community parsers converge on a useful observed shape: JSONL records with `user`/`assistant` envelopes, typed `message.content` blocks such as text, thinking, tool use, and tool results, plus metadata/system records. This is verified as the behavior documented by the surveyed viewers, not as an Anthropic stability guarantee. It is a good analogy for HiBoss's need for an append-only event contract, but it is not a format to copy blindly.

### Open viewers and parsers

| Implementation | Licence and maturity observed | What it buys | Adoption cost / warning |
|---|---|---|---|
| [Claude Code Viewer](https://github.com/d-kimuson/claude-code-viewer) | MIT; full web client with real-time log viewing, historical JSONL discovery, mobile/PWA support, and a built-in xterm terminal. The repository README describes a substantial React/TypeScript application and explicitly says it reads the standard files. [README](https://github.com/d-kimuson/claude-code-viewer#data-source), [package.json](https://github.com/d-kimuson/claude-code-viewer/blob/main/package.json) | Progressive disclosure for tool calls, session search, mobile layout, live tailing, and a proven separation between conversation view and terminal panel. | Not an iOS library; brings a web stack and a parser tied to a changing private format. It also inherits Claude's local cleanup behavior; its README says deleted JSONL means deleted viewer history. |
| [Claude Code Trace](https://github.com/delexw/claude-code-trace) | MIT; desktop/web/TUI app, with live tailing, expandable tool calls, timestamps, token counts, and MCP detection. Its README notes that the TUI has UX rough edges, so maturity is broad but not uniform. [README](https://github.com/delexw/claude-code-trace#features), [license](https://github.com/delexw/claude-code-trace/blob/main/LICENSE) | A strong inspection model: chronological session items, expandable detail, debug view, and live tail rather than chat bubbles. | Tauri + React + Rust, not reusable SwiftUI components; parser and viewer must be rebuilt or ported. |
| [cc_transcript_viewer](https://github.com/tim-hua-01/cc_transcript_viewer) | MIT; small, zero-dependency Python/vanilla-web viewer with a 56-commit history and no reported issues at inspection time. It polls an open transcript about three times per second, caches by file mtime, preserves scroll position, and has characterization/security tests. [README](https://github.com/tim-hua-01/cc_transcript_viewer), [`claude_parser.py`](https://github.com/tim-hua-01/cc_transcript_viewer/blob/main/claude_parser.py), [`event_schema.py`](https://github.com/tim-hua-01/cc_transcript_viewer/blob/main/event_schema.py) | Direct evidence for live tailing, event normalization, pairing tool calls/results, branch folding, subagent labels, and a separate frontend event schema. | It is explicitly dependent on undocumented on-disk formats and self-describes as quickly built with rough edges. The polling approach is an analogy, not a server architecture to copy. |
| [tjsonl](https://github.com/coo-labs/tjsonl) | MIT; 31 commits and 9 issues at inspection time. It is a community-maintained observed schema/spec plus zero-dependency validator, not a viewer. [README](https://github.com/coo-labs/tjsonl), [spec directory](https://github.com/coo-labs/tjsonl/tree/main/spec) | A useful discipline: characterize unknown records, validate drift, and make parser assumptions visible. | No UI, no streaming transport, and no stable upstream guarantee. Adopt the technique—versioned contract and drift tests—not the Claude-specific schema. |
| [AgentsView](https://github.com/kenn-io/agentsview) | MIT; 1,000+ commits in the inspected repository and a local-first binary/web UI. It supports Claude Code, Codex, and many other agent stores, syncs into local SQLite, and offers search/analytics. [README](https://github.com/kenn-io/agentsview), [license](https://github.com/kenn-io/agentsview/blob/main/LICENSE) | Comparable agent-log UI ideas: normalize heterogeneous sources, use a local indexed projection, provide search and cost/session views instead of one giant chat list. | Go/desktop/web application, not an embeddable iOS component; its adapters track several private or semi-private source formats. |

The common lesson is not “use chat bubbles.” The strongest viewers preserve a lossless-ish event source, normalize it into display events, progressively disclose tool detail, and tail the source without disturbing the reader's scroll position.

## Survey: terminal and high-volume Apple UI building blocks

### SwiftTerm

SwiftTerm is a MIT-licensed VT100/Xterm engine with iOS UIKit and macOS AppKit front ends. Its README lists ANSI/256/TrueColor, attributes, selection, search, Unicode/graphemes, hyperlinks, terminal resizing, session recording/playback, fuzzing, and optional Metal rendering. It says the library is used by Secure Shellfish, La Terminal, and CodeEdit. [README](https://github.com/migueldeicaza/SwiftTerm), [iOS source tree](https://github.com/migueldeicaza/SwiftTerm/tree/main/Sources/SwiftTerm), [LICENSE](https://github.com/migueldeicaza/SwiftTerm/blob/main/LICENSE)

Maturity is high relative to the alternatives surveyed: the repository exposes a test suite, benchmarks, compliance fixtures, and more than 1,000 commits. The limitation is equally important: the bundled iOS control is UIKit, so a SwiftUI integration is an adapter project, and the library's terminal semantics are not message semantics. It is a strong renderer to borrow selectively, not proof that a terminal is the right session data model.

### Exyte Chat

Exyte Chat is MIT-licensed and mature enough to be a useful performance reference: its README documents pagination, custom cells, large-message handling, scroll-to-bottom controls, content-offset observation, load-more, and stable update transactions. It targets iOS 17/Xcode 15 and uses a table-oriented scrolling surface behind its SwiftUI API. [README](https://github.com/exyte/Chat), [model sources](https://github.com/exyte/Chat/tree/main/Sources/ExyteChat/Model)

It would buy a conversation-grade viewport, but not terminal parsing, server replay, or HiBoss direction/session rules. Adopting it also imports its message model and iOS baseline; a custom transcript may be smaller because HiBoss needs only text, metadata, and live-tail behavior.

### Pulse

Pulse is a MIT-licensed Apple-platform logging system built with SwiftUI. It records app/network events locally and provides `PulseUI` views; the README describes real-time remote logging, local storage, and iOS 15+ support for its current major line. [README](https://github.com/kean/Pulse), [source tree](https://github.com/kean/Pulse/tree/main/Sources)

Pulse is useful as a log-product reference—local persistence, filtering, and a console embedded in an app—but it is not a session-conversation or terminal emulator. Adoption would add a logger/storage model that still needs a HiBoss event adapter, direction/session presentation, and cursor-aware network code. It is better inspiration than a direct dependency.

### Platform baseline

Apple's documented SwiftUI guidance recommends lazy stacks when a non-lazy stack would load too many child views, and recommends profiling with Instruments. [Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks) That is a baseline, not a guarantee for thousands of frequently changing, variably sized transcript rows. For this workload, benchmark `List`/`LazyVStack` against a UIKit-backed virtualized surface with real event rates before committing to a rendering dependency.

## Decision summary

Choose the purpose-built transcript direction now, with SSE + D1 event persistence and replay as the first vertical slice. The server event contract is the irreversible dependency; the renderer can remain replaceable. Add SwiftTerm only when a producer and test fixture demonstrate terminal control sequences that a transcript row cannot represent cleanly.

Confidence: high for the current-code findings; high for the transport/storage constraints cited from Cloudflare; medium for performance projections until an iOS benchmark fixture exists; low for any claim that Claude Code's JSONL schema will remain stable.
