# hiboss Roadmap History

All versions through v1.0 are complete and shipped.

## Current Unreleased — Convergent Options and Native macOS Client

### Option Contract and CLI
- `hiboss ask` uses repeatable singular `--option "TEXT"` and
  `--action "LABEL=COMMAND"` flags.
- Options containing commas are preserved verbatim; the removed plural flags emit
  migration guidance instead of restoring ambiguous comma splitting.
- The server accepts only arrays of one to five non-empty, unique option strings.

### Multi-Client Resolution
- Every connected Boss client independently receives each active option message.
- The first valid selection atomically changes the parent message to `replied`;
  concurrent later selections receive HTTP 409.
- Boss SSE streams emit a `resolved` event to every client after selection or
  expiry, so all local option pickers withdraw.
- API, Discord, and Telegram selections remove outstanding Discord components and
  Telegram inline keyboards.

### HiBoss Island for macOS
- The signed native app has a main History/Settings window and fetches the latest
  100 Boss-visible messages without maintaining a second local database.
- The option UI supports top-screen island and standard window presentation.
- Closing the main window leaves the SSE listener running; reopening the app
  restores the same process and window.
- The optional menu bar icon uses native `NSStatusItem`, avoiding SwiftUI scene
  loops when hidden. Keychain reads run asynchronously after launch.

## v0.1 — Core
Rust CLI (send, ask, inbox, read, reply, status, agent, bot, watch, init, config, channel). Cloudflare Worker server with D1. Discord + Telegram adapters. Multi-agent support. MCP server.

## v0.2 — Reliability Fixes
Channel fallback. Reply delivery to Telegram/Discord. Short ID prefix matching. Typing indicator.

## v0.3 — Real-time Push & Agent Awareness
SSE streaming. Agent webhook callbacks. CLI watch/bot with SSE. MCP SSE listener. SessionStart/PostToolUse hooks. Priority filter. Telegram reactions.

## v0.4 — Rich Telegram & Claude Code Integration
HTML formatting. Reply threading. Inline keyboards. Callback query handler. Agent config (priority, rate limiting). CLAUDE.md prompt injection. Escape sequences.

## v0.5 — Smart Routing & Multi-Agent
Multi-channel delivery (critical/high → all channels). Regex routing rules. Agent groups with broadcast.

## v0.5.1 — Structured Types & Action Callbacks
Message `type` field. Action buttons with shell command callbacks.

## v0.5.2 — File Attachments
R2 upload/serve. CLI `--file` flag. Telegram document delivery.

## v0.6 — Reliability & Polish
Code split (client modules, delivery extraction). Retry delivery. Idempotency keys. `hiboss doctor`. Exit codes. Discord webhook support.

## v0.7 — Discord Bidirectional
Discord Interactions API. `/msg` slash command. Button clicks. Ed25519 verification. Options expiry.

## v0.8 — Smart Channel Routing
Per-priority channel defaults via `channel_routing` JSON column.

## v0.9 — Multi-boss & Teams
Boss management (admin/manager/viewer). Access control. Webhook auth (Telegram/Discord identity). Audit log.

## v0.10 — Agent-as-Boss & Session Isolation
Agent-as-boss (`agent_id` on bosses). Boss inbox/reply API. Session-scoped messages.

## v0.10.1 — Channel Routing Fix
CLI no longer overrides server routing. Action result feedback. Doctor shows routing.

## v0.10.4 — Full Reaction Support + Message Isolation
Discord reactions (discord_message_id tracking). Telegram reactions. Telegram Topics (per-agent forum topics). Discord setup improvements.

## v0.11 — Cross-Session Agent Communication
First-class sessions table. Agent-to-agent messaging (`--to`). Smart resolution (name → ID → label → session). Dual TTL polling. Session hooks.

## v0.12 — Session-Scoped SSE Streaming
SSE includes a2a messages. Session param on stream. Watch/bot session-scoped.

## v0.13 — Background SSE Daemon & MCP Server
Daemon (start/stop/status). Local file delivery (0ms). MCP send_to_peer/list_sessions tools.

## v0.14 — Session Status Tracking & Dashboard
Session status (working/blocked/waiting/idle/completed). Auto-inference. `hiboss ss` kanban CLI. Web dashboard (messages, sessions, agents tabs).

## v0.15 — Boss Authentication Tokens
Boss tokens (`hb_boss_*`). Boss auth/dual auth middleware. Boss API (`/api/boss/*`). Dashboard boss mode.

## v0.16 — Session-Scoped Messages
Per-session inbox isolation. Session filter on queries.

## v0.17 — Comprehensive Audit Logging
29 audit points on all mutations.

## v0.18 — Dashboard Reply UI
Boss can reply from web dashboard.

## v0.19 — Guided Setup Wizards
`hiboss setup telegram` and `hiboss setup discord`.

## v0.20 — Per-Boss Preferences
Boss preferences (channel, quiet hours, timezone, notify priorities). Dashboard settings.

## v0.21 — Full-Text Message Search
`?search=` on messages API. Dashboard search. CLI `--search`.

## v1.0 — Production Ready
Interactive session kanban with message view. Session reply from dashboard. Agent config panel. 360+ tests. Published to crates.io. Auto-link boss messages to blocking polls.

## v1.1.0 — Security Hardening
Comprehensive security audit and fixes across the server codebase.

### Webhook Security
- Add `apiAuth` to Discord `register-commands` endpoint (was unauthenticated)
- Add Telegram webhook secret token validation (`TELEGRAM_WEBHOOK_SECRET` env var)
- Add Discord webhook secret validation (`DISCORD_WEBHOOK_SECRET` env var)
- Validate `msgPrefix` format in callback handlers (hex-only, prevents LIKE injection)

### Authorization Fixes
- Boss-inbox PATCH: add agent scope check (was missing `getAccessibleAgentIds` verification)
- `fetchReplies`: add `agentId` ownership filter (was returning all replies regardless of agent)
- Reply endpoint: add `canReply` ownership check (prevent cross-agent reply injection)
- `buildFilters`: conditional `target_session_id` clause (prevent cross-agent session leakage)
- Routing rules: scope to owning agent via `owner_id` filter

### Input Validation
- `escapeLike` helper for all LIKE queries (prevent `%`/`_` wildcard injection)
- Applied to `findBoss`, boss-api message lookups, boss-inbox lookups

### Reliability
- `insertMessageWithRecovery`: handle idempotency key race condition via UNIQUE constraint catch
- SSE stream: change `>` to `>=` with `seenMessageIds` dedup (prevent message drops at same timestamp)

## v1.2.0 — Deep Audit, Performance & Dashboard

### Dashboard Rewrite
- Full rewrite with Vue 3 + Tailwind CSS (CDN-only, no build step)
- Messages, sessions, and agents tabs with real-time updates

### Options Expiry
- Poll timeout automatically expires and recycles stale option buttons
- Options persisted in message metadata for reliable display

### Core Business Logic Audit (16 Critical+High fixes)

**Auth & Isolation**
- Boss API endpoints switched from `apiAuth` to `bossAuth` (bosses no longer need agent keys)
- Sessions endpoint uses `dualAuth` with cross-agent upsert protection
- `?all=true` on sessions restricted to boss callers only
- Groups scoped by `owner_id` (new column via migration 0017) — agents cannot see/modify other agents' groups
- A2A replies now correctly set `target_agent_id` and `target_session_id`

**Webhook Hardening**
- `enabled=1` filter on channel config lookups (disabled channels no longer receive messages)
- Channel validation on webhook message creation (prevents channel spoofing)
- Idempotency dedup via `idempotency_key` column (prevents duplicate webhook messages)
- New helpers: `findEnabledChannelConfig()`, `findMessageByIdempotencyKey()`

**Input Validation & SQL Safety**
- `ESCAPE` clause added to all LIKE queries (prevents backslash injection)
- Boss-inbox uses exact ID matching only (removed prefix LIKE)
- Bootstrap uses atomic INSERT with `WHERE NOT EXISTS` (prevents race conditions)
- Optional `BOOTSTRAP_SECRET` env var for bootstrap endpoint protection

**Delivery Reliability**
- `persistDeliveryFailure()` helper saves delivery errors to message metadata
- Discord timestamp freshness check (300s window) prevents replay attacks

**Removed Vulnerabilities**
- Removed shell execution (`sh -c`) from `ask` command action handling (was arbitrary code execution risk)

### CLI Performance
- PostToolUse hook: 600ms → 4ms (150x speedup)
- Architecture change: PostToolUse is now pure local I/O (file reads only, no HTTP)
- Background HTTP checks (heartbeat, inbox polling) run in detached `bg-check` subprocess
- Dual TTL caching: 30s for agent-to-agent, 300s for boss urgent checks
- Direct HTTP client methods (`inbox_count`, `inbox_count_a2a`) replace subprocess spawning
- HTTP client split: 30s timeout for normal requests, 120s for long-poll

## v1.3.0 — Claude Code Channel Plugin (MCP)

New local MCP server that runs as a Claude Code plugin/channel, replacing hook-based polling with real-time SSE-driven notifications. Inspired by Anthropic's official Telegram plugin pattern.

### Architecture
- `mcp/server.ts`: Single-file MCP server (292 lines, Bun runtime)
- Bridges Claude Code ↔ hiboss server via SSE + REST API
- Real-time delivery via `notifications/claude/channel` protocol
- Replaces old `mcp-server/` (v0.13) which used `sendLoggingMessage` (logs, not channel)

### MCP Tools (5)
- `send`: Send messages to boss or peer agents
- `ask`: Blocking question with options + poll for reply
- `reply`: Reply to specific message by ID
- `react`: Add emoji reaction to a message
- `inbox`: List unread boss messages

### Plugin Packaging
- `.claude-plugin/plugin.json`: Plugin manifest for CC discovery
- `.mcp.json`: Startup config (`bun start`)
- `skills/configure/SKILL.md`: `/hiboss:configure` skill for credential management
- Shares config with CLI (`~/.config/hiboss/config.json`)

### Key Patterns
- SSE reconnection with exponential backoff (1s → 30s)
- Graceful shutdown on stdin EOF (CC process management)
- Session registration + cleanup on exit
- Messages marked as delivered after MCP notification
- `experimental: { 'claude/channel': {} }` capability declaration

### Supersedes
- `mcp-server/` (v0.13): Deprecated. Old MCP used logging notifications, not channel protocol. New `mcp/` is lighter (1 file vs 7), needs no build step, and integrates as a proper CC channel plugin.
- Hook-based integration (SessionStart/PostToolUse): Hooks become fallback. MCP channel provides real-time delivery without polling.

### Migration Path
1. Phase 1 (current): MCP server ships as standalone plugin
2. Phase 2: CLI `setup hooks --plugin` installs MCP channel instead of hooks
3. Phase 3: Plugin is the default; hooks are fallback for non-CC environments

## v1.4.0 — Discord Session Threads & Reply Acknowledgment

### Discord Per-Session Thread Isolation
- Each agent session automatically creates a Discord thread on first message
- Thread name derived from session label/branch (e.g. `hiboss/main`)
- Subsequent messages from the same session route to its thread
- Boss replies within a thread route back to the correct agent+session
- Enable with `use_threads: true` in Discord channel config
- New `createDiscordThread()` in discord adapter
- `ensureThreadForSession()` mirrors Telegram's `ensureTopicForAgent()` pattern
- Inbound routing: Gateway DO + webhook-helpers resolve thread channel_id → session
- Migration 0020: `discord_thread_id` column + index on sessions table

### Reply Acknowledgment Enforcement (CLI)
- `hiboss ask` now outputs reply message ID + stderr reminder after receiving boss reply
- SessionStart hook injects rule: "acknowledge boss replies via hiboss, not conversation text"
- Stop hook detects unacknowledged replies (STOP VIOLATION if `has_asked()` but not `has_replied()`)
- `send`, `reply`, `react` commands set `mark_replied()` marker
- New session markers: `replied_marker_path()`, `mark_replied()`, `has_replied()`

## v1.5.0 — Channel Parity & Feature Completeness

### Discord Improvements
- **File Attachments**: Proper multipart form-data upload for non-image files, embed images via Discord embeds (instead of appending URL as text)
- **Typing Indicator**: `sendDiscordTyping()` fires before every Discord message delivery, matching Telegram's behavior
- **Boss Reaction Capture**: Gateway DO now handles `MESSAGE_REACTION_ADD` and `MESSAGE_REACTION_REMOVE` events via new `GUILD_MESSAGE_REACTIONS` intent
- New `discord-gateway-reactions.ts` module with `lookupDiscordAgentId()` and `persistDiscordReaction()` helpers
- Reactions stored in message metadata matching Telegram's `{ emoji, user }` format

### Telegram Per-Session Forum Topics
- Each session creates its own Telegram forum topic (mirrors Discord's per-session threads)
- Migration 0021: `telegram_topic_id` column + index on sessions table
- New `session-channels.ts` with `ensureTopicForSession()` and `fetchTelegramTopicIdForSession()`
- Delivery functions use session topic ID instead of per-agent `message_thread_id`
- Webhook inbound routes messages from topics to correct session via `telegram_topic_id` lookup

### Message Editing
- Server: PATCH `/api/messages/:id` now accepts `{ body }` for body updates (agent_to_boss only)
- Channel propagation: edits propagate to Discord (via `editDiscordMessage`) and Telegram (via new `editTelegramMessageText`)
- Propagation runs via `waitUntil` (fire-and-forget, best-effort)
- Audit logging for `message.edit` events
- CLI: new `hiboss edit <id> "body"` command
- MCP: existing `edit_message` tool now works end-to-end

### MCP Tool Additions
- `search`: Full-text search across messages via `?search=` query param
- `list_sessions`: List active sessions with id, label, status, agent_name
- Refactored tool helpers into `mcp/tool-helpers.ts`

### Dashboard Enhancements
- **Reaction Display**: Messages show reaction pills (`👍 boss`) from metadata
- **File Attachment Viewer**: Inline image thumbnails for photos, download links for documents
- **Edited Indicator**: "(edited)" badge when `updated_at` differs from `created_at`
- **Options/Poll Display**: Option buttons with selected state highlighting, expired dimming
- **Session Filter**: Messages tab can filter by session ID
- **Session Thread Links**: Discord thread IDs and Telegram topic IDs shown as badges in session cards

## v1.6.0 — Full Feature Expansion

### Telegram Bot Commands
- `/msg <text>` command for Telegram — matches Discord's /msg slash command
- `/status` command shows active session status inline
- Bot command entity detection in webhook handler
- `hiboss setup telegram-commands` CLI subcommand to register commands via BotFather API
- `POST /api/webhooks/telegram/register-commands` API endpoint
- Refactored webhook handlers: `telegram-webhook-actions.ts` for callback + reaction handlers

### Discord Join/Onboard Flow
- Discord button click callbacks now handle `join:approve` and `join:reject`
- Shared join logic extracted to `join-helpers.ts` (used by both Telegram and Discord handlers)
- Discord interactions handler detects `join:` prefix and routes to join callback
- Complete feature parity with Telegram's approve/reject join flow

### MCP File Attachment Tool
- New `send_file` tool in MCP server
- Reads local file, uploads to R2 via `/api/attachments/upload`
- Sends message with `file_url` for channel delivery
- File size validation (10MB limit), error handling
- Separate module: `mcp/send-file.ts` with tests

### Quiet Hours Server-Side Enforcement
- Server queues normal/low priority messages during boss quiet hours
- Migration 0022: `delivery_queue` table with scheduling
- `quiet-hours.ts` module: timezone-aware quiet hours check, overnight range support
- Scheduled worker drains delivery queue when quiet hours end
- Critical/high priority messages always deliver immediately
- `agent-delivery.ts` helper for consolidated delivery logic

### Channel Health Diagnostics
- `GET /api/channels/stats` endpoint: per-channel delivery counts, failure rates, timestamps
- `hiboss doctor` now shows "Channel Health" section with delivery success rates
- `--verbose` flag shows last errors, delivery queue status
- `admin-channel-stats.ts` server module with SQL aggregation queries

### Dashboard PWA
- Service worker (`sw.js`) with cache-first CDN strategy, network-first API
- Web app manifest for "Add to Home Screen" on mobile
- SVG icon served inline
- Mobile bottom navigation bar on small screens
- Pull-to-refresh gesture on messages tab
- Touch-friendly 44px tap targets

### Message Forwarding Between Channels
- `POST /api/messages/:id/forward` endpoint with target channel
- CLI: `hiboss forward <id> --channel <target>` command
- MCP: `forward` tool
- Dashboard: forward button on messages with channel dropdown
- Forwarded messages linked via `reply_to` with `type: 'forwarded'`

### Decision Alerts Opt-Out (iOS)
- New boss preference `decision_alerts` (default ON). A message carrying options (a
  blocking `ask`) force-alerts the iOS lock screen + Dynamic Island even at normal
  priority; setting it false demotes decisions to normal per-priority tiering and
  suppresses the Live Activity.
- Server gate in `notify.ts` (`decisionAlertsEnabled`); client gate in
  `DecisionActivityManager.sync(alertsEnabled:)`; toggle in iOS Settings.

### Project-Forward Notifications + `--content`
- Boss push/Live-Activity headers now lead with the PROJECT (session label
  `repo/branch`), demote the agent name to a faint body prefix, and show a new
  agent-supplied context line.
- New `--content "<text>"` flag on `hiboss send`/`ask` → `metadata.content` →
  rendered as the APNs `aps.alert.subtitle` (private-mode pushes unchanged).
- APNs title = project, subtitle = content, body = `agent · message`. Server joins
  `sessions` in `boss-option-stream` so macOS also shows the project.
- iOS Live Activity + macOS Island headers re-ordered project-forward.

### Message Detail Attribute Icons (iOS)
- iOS message-detail "Details" rows lead with SF Symbols (`MessageAttributeStyle`).
  Priority + Status glyphs carry semantic color; structural rows are monochrome.

### Not Merged (pending re-implementation)
- **Delivery Retry Queue**: WS5 had merge conflicts with quiet-hours infrastructure. The delivery_queue table exists (from quiet hours). Retry logic with exponential backoff needs re-implementation on the merged codebase.
