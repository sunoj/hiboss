# hiboss — AI Agent ↔ Boss Communication Tool

CLI tool for AI agents to send messages to their boss (human or AI) and receive replies. Supports Discord, Telegram, and Email channels.

## Agent Instructions

When this project's Claude Code session starts, the SessionStart hook checks for unread boss messages via `hiboss inbox`. If `HIBOSS_UNREAD_COUNT` is set and > 0, you have pending messages from the boss. Read them with `hiboss inbox` and address them before starting other work. Use `hiboss reply <id> "response"` to reply, or `hiboss send "message"` to send new messages. Always notify the boss of major progress via `hiboss send`.

## Architecture

```
hiboss CLI (Rust/clap) ←HTTP→ hiboss-server (Cloudflare Worker + Hono)
                                    ↕ D1 (messages)
                                    ↕ Channel Adapters (Discord, Telegram, Email)
                                    ↕ Boss (human or AI)
```

## Project Structure

- `cli/` — Rust CLI binary (clap for args, reqwest for HTTP, serde for JSON)
- `server/` — Cloudflare Worker (Hono framework, D1 database)

## API Contract

Base URL: configured via `hiboss config set server <url>`
Auth: `Authorization: Bearer <api-key>` header on all requests.

### Endpoints

#### POST /api/messages
Send a message from agent to boss.

Request:
```json
{
  "body": "string (required)",
  "mode": "async | blocking",
  "priority": "critical | high | normal | low",
  "channel": "discord | telegram | email (optional, uses default)",
  "metadata": {}
}
```

Response (201):
```json
{
  "id": "string",
  "status": "sent",
  "created_at": "ISO8601"
}
```

For `mode: "blocking"`, the server holds the connection (long-poll, up to 5 minutes) and returns when boss replies:
```json
{
  "id": "string",
  "status": "replied",
  "reply": {
    "id": "string",
    "body": "string",
    "created_at": "ISO8601"
  }
}
```

If timeout, returns 202 with `status: "sent"` (agent can poll later).

#### GET /api/messages
List messages for this agent.

Query params:
- `direction`: `agent_to_boss | boss_to_agent` (optional)
- `status`: `sent | delivered | read | replied` (optional)
- `unread`: `true` — shortcut for direction=boss_to_agent&status=sent (optional)
- `limit`: number (default 20)
- `offset`: number (default 0)

Response (200):
```json
{
  "messages": [
    {
      "id": "string",
      "direction": "agent_to_boss | boss_to_agent",
      "mode": "async | blocking",
      "channel": "discord | telegram | email",
      "body": "string",
      "status": "sent | delivered | read | replied",
      "reply_to": "string | null",
      "priority": "critical | high | normal | low",
      "metadata": {},
      "created_at": "ISO8601",
      "updated_at": "ISO8601"
    }
  ],
  "total": "number"
}
```

#### GET /api/messages/:id
Get a single message with its reply chain.

Response (200): single message object (same shape as above, plus `replies: Message[]`)

#### POST /api/messages/:id/reply
Reply to a message (used by boss-side or agent replying to boss).

Request:
```json
{
  "body": "string (required)"
}
```

Response (201): message object of the reply.

#### PATCH /api/messages/:id
Update message status (mark as read, etc.).

Request:
```json
{
  "status": "read"
}
```

#### POST /api/messages/:id/poll
Long-poll for reply to a blocking message. Returns when reply arrives or timeout.

Query params:
- `timeout`: seconds (default 300, max 300)

Response: same as GET /api/messages/:id but waits for reply.

### Channel Webhook Endpoints

#### POST /api/webhooks/discord
Discord interaction webhook. Receives messages from Discord, creates boss_to_agent messages.

#### POST /api/webhooks/telegram
Telegram bot webhook. Receives messages from Telegram, creates boss_to_agent messages.

### Admin Endpoints

#### POST /api/keys
Create a new API key.

Request:
```json
{
  "name": "string"
}
```

Response (201):
```json
{
  "id": "string",
  "name": "string",
  "key": "string (only shown once)"
}
```

#### GET /api/channels
List channel configs for this agent.

#### PUT /api/channels/:channel
Set channel config.

Request (discord):
```json
{
  "channel_id": "string",
  "bot_token": "string"
}
```

Request (telegram):
```json
{
  "chat_id": "string",
  "bot_token": "string"
}
```

## CLI Commands

```bash
# Setup
hiboss config set server https://hiboss-server.<user>.workers.dev
hiboss config set key <api-key>
hiboss config set channel discord   # default channel

# Send (async)
hiboss send "Deployment complete. 3 tests failed."
hiboss send --priority high "Build failed, need help."
hiboss send --channel telegram "Quick update via TG."

# Ask (blocking, waits for reply)
hiboss ask "Option A or B for the migration?"
hiboss ask --timeout 60 "Quick question: proceed with deploy?"

# Inbox
hiboss inbox                 # unread messages from boss
hiboss inbox --all           # all messages
hiboss inbox --limit 5       # last 5

# Read a message
hiboss read <msg-id>

# Reply to boss message
hiboss reply <msg-id> "Done, deployed to staging."

# Status of sent message
hiboss status <msg-id>
```

## CLI Config

Stored in `~/.config/hiboss/config.json`:
```json
{
  "server": "https://hiboss-server.xxx.workers.dev",
  "key": "hb_xxxxxxxxxxxx",
  "channel": "discord"
}
```

## Roadmap

### v0.1 — Core (Done)
- Rust CLI with all commands: send, ask, inbox, read, reply, status, agent, bot, watch, init, config, channel
- Cloudflare Worker server with D1, Discord + Telegram adapters
- Multi-agent support from day one (API key per agent, agent_name in messages)
- MCP server for Claude Code / Cursor integration
- Bootstrap flow for first-time setup

### v0.2 — Reliability Fixes (Done)
- Channel fallback: server auto-selects configured channel when requested one is missing
- Reply delivery: `hiboss reply` now delivers back to Telegram/Discord, not just D1
- Short ID prefix matching: inbox shows 8-char IDs, all commands accept them
- Typing indicator: Telegram shows "typing..." on incoming and outgoing messages

### v0.3 — Real-time Message Push
**Problem**: Current architecture is pull-only. Agent must poll `hiboss inbox` or run `hiboss bot`. Boss messages sit in D1 until someone checks.

**Solution**: Server-Sent Events (SSE) + Agent Webhook Callbacks.

#### SSE Stream Endpoint
- `GET /api/messages/stream` — persistent SSE connection, pushes new messages in real-time
- Auth via Bearer token (same as other endpoints)
- Events: `message` (new message), `status` (delivery/read updates)
- `hiboss watch` and `hiboss bot` switch from polling to SSE (fall back to polling if SSE unavailable)
- Uses Cloudflare Workers streaming response (`ReadableStream`)

#### Agent Webhook Callbacks
- `PUT /api/agents/me/callback` — register a callback URL for the current agent
- When a boss_to_agent message arrives, server POSTs to the callback URL
- Enables serverless agents (e.g., another Cloudflare Worker that auto-replies)
- Callback payload: full message object, same as GET /api/messages/:id
- Retry with exponential backoff on failure (via Cloudflare Queue or waitUntil)

#### API Changes
```
GET  /api/messages/stream          — SSE stream of new messages
PUT  /api/agents/me/callback       — register webhook callback URL
DELETE /api/agents/me/callback     — remove callback
GET  /api/agents/me                — get agent config (including callback)
```

### v0.4 — Rich Telegram Integration
**Goal**: Leverage the full Telegram Bot API for a native chat experience.

#### Message Formatting
- Markdown/HTML support in outgoing messages (MarkdownV2 parse_mode)
- File/image attachments via Telegram sendDocument/sendPhoto
- Reply threading: use `reply_to_message_id` so Telegram shows threaded conversations

#### Interactive Elements
- Inline keyboards for quick-reply buttons (approve/reject, option A/B/C)
- `hiboss ask --options "A,B,C"` sends message with inline keyboard
- Telegram callback_query handler to capture button presses as replies
- Reactions support (boss can react; agent sees it as metadata)

#### Read Receipts
- Mark messages as read when boss views them in Telegram
- Bot tracks Telegram `message_id` → hiboss message ID mapping

### v0.5 — Smart Routing & Agent Config
- Priority-based routing: critical messages go to all channels simultaneously
- Agent-level system prompts: `hiboss agent config set prompt "You are a deployment bot..."`
- Built-in prompt templates for common agent types (reporter, approver, monitor)
- Message routing rules: keyword/regex → specific agent
- Rate limiting per agent

### v0.6 — Multi-boss & Teams
- Multiple bosses per agent (different API keys, different permissions)
- Group/team channels (one message → multiple recipients)
- Boss roles: admin (full control), manager (reply + configure), viewer (read-only)
- Audit log: who did what, when

## Code Conventions

### Server (TypeScript)
- TypeScript strict mode
- Files ≤ 300 lines, functions ≤ 50 lines
- ESM modules (type: "module")
- Hono framework, use `c.json()` for responses
- No `any` types at module boundaries

### CLI (Rust)
- Files ≤ 300 lines, functions ≤ 50 lines
- clap derive API for argument parsing
- reqwest for HTTP calls (rustls-tls, json feature)
- serde + serde_json for serialization
- Config stored in `~/.config/hiboss/config.json` (use dirs crate for path)
- colored crate for ANSI terminal output
- Error handling: anyhow-style, print friendly messages to stderr, main output to stdout
- Pipe-friendly: data to stdout, status/errors to stderr
