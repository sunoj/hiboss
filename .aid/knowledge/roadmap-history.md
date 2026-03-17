# hiboss Roadmap History

All versions through v1.0 are complete and shipped.

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
