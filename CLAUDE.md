# hiboss — AI Agent ↔ Boss Communication Tool

CLI tool for AI agents to send messages to their boss (human or AI) and receive replies. Supports Discord, Telegram, and Email channels.

## Agent Instructions

These are the recommended instructions for AI agents using hiboss. Copy this section into your project's CLAUDE.md and adjust as needed.

### Setup

Run `hiboss setup hooks` to install Claude Code hooks automatically. This configures:
- **SessionStart**: injects unread boss messages into context at session start
- **PostToolUse**: checks for urgent (critical/high) messages every 5 minutes
- **Stop**: reminds you of unread messages before session ends

### Session Start

1. The SessionStart hook will show unread messages from your boss. **Handle them first** — reply with `hiboss reply <id> "response"` before starting other work.
2. **Report your plan**: After handling inbox and understanding the task, send your plan to the boss:
   ```bash
   hiboss send "Starting work on X. Plan: 1) ... 2) ... 3) ..."
   ```
   The boss should know what you intend to do before you start.

### During Work

- Use `hiboss send "message"` for progress updates on major milestones.
- Use `hiboss send --priority high "message"` for blockers or decisions needed urgently.
- The PostToolUse hook will interrupt you if the boss sends a critical/high priority message — check and respond.

### Before Finishing (CRITICAL)

When your current task is complete and you have no more work to do, you MUST follow this exact flow — **never just stop**:

1. Summarize what you accomplished
2. Propose 2-4 concrete next directions based on context (roadmap items, open issues, improvements)
3. Send via `hiboss ask --options` (**never** `hiboss send` for completion messages):
   ```bash
   hiboss ask --options "Option A,Option B,Option C" "Summary of what was done. What should I do next?" --timeout 300
   ```
4. Run the ask command with `run_in_background: true` in Bash
5. **Wait for the boss's reply** — do not stop while the background task is pending
6. When the reply arrives, continue working on the selected direction
7. Only stop if: the boss explicitly says to stop, OR the ask times out with no reply

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
- `priority`: comma-separated filter, e.g. `critical,high` (optional)
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

#### POST /api/messages/:id/react
Set a reaction emoji on a Telegram message. Agent decides what emoji to use.

Request:
```json
{
  "emoji": "👀"
}
```

Response (200): `{ "ok": true }`

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
hiboss init https://hiboss-server.<user>.workers.dev  # bootstrap first key
hiboss config set server https://hiboss-server.<user>.workers.dev
hiboss config set key <api-key>
hiboss config set channel discord   # default channel
hiboss setup hooks                  # configure Claude Code hooks
hiboss setup hooks --remove         # remove hiboss hooks

# Send (async)
hiboss send "Deployment complete. 3 tests failed."
hiboss send --priority high "Build failed, need help."
hiboss send --channel telegram "Quick update via TG."

# Ask (blocking, waits for reply)
hiboss ask "Option A or B for the migration?"
hiboss ask --timeout 60 "Quick question: proceed with deploy?"

# Inbox
hiboss inbox                              # unread messages from boss
hiboss inbox --all                        # all messages
hiboss inbox --limit 5                    # last 5
hiboss inbox --priority critical,high     # urgent only
hiboss inbox --priority critical --count  # count of urgent unread

# Read a message
hiboss read <msg-id>

# Reply to boss message
hiboss reply <msg-id> "Done, deployed to staging."

# React to a message with emoji
hiboss react <msg-id> "👀"
hiboss react <msg-id> "✅"

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

## Message Delivery Architecture

Boss messages reach the agent through three layers:

| Layer | Trigger | Scope | Latency |
|-------|---------|-------|---------|
| **PostToolUse hook** | Every tool call (5min TTL cache) | critical/high only | ≤5min |
| **MCP SSE push** | Real-time SSE background listener | All messages (terminal-visible) | Real-time* |
| **SessionStart hook** | New session start | All unread | Session gap |

*MCP `notifications/message` is displayed in terminal but NOT injected into agent context by Claude Code.

Normal/low priority messages wait for SessionStart or manual `hiboss inbox`. Only urgent messages interrupt the agent via PostToolUse hook.

### Telegram Reactions
Agents can set reaction emojis on Telegram messages via `hiboss react <id> <emoji>`. The server exposes the capability; agents decide what reactions to use and when. Example conventions:
- 👀 → message seen
- 🔨 → working on it
- ✅ → done/replied

## Roadmap

### v0.1 — Core (Done)
- Rust CLI: send, ask, inbox, read, reply, status, agent, bot, watch, init, config, channel
- Cloudflare Worker server with D1, Discord + Telegram adapters
- Multi-agent support (API key per agent, agent_name in messages)
- MCP server for Claude Code / Cursor integration

### v0.2 — Reliability Fixes (Done)
- Channel fallback: auto-selects configured channel
- Reply delivery: replies deliver back to Telegram/Discord
- Short ID prefix matching: 8-char IDs work everywhere
- Typing indicator on Telegram

### v0.3 — Real-time Push & Agent Awareness (Done)
- SSE streaming: `GET /api/messages/stream` for real-time message delivery
- Agent webhook callbacks: `PUT /api/agents/me/callback`
- CLI `watch` and `bot` commands use SSE with auto-reconnect
- MCP server background SSE listener with `notifications/message` push
- SessionStart hook: injects unread messages at session start
- PostToolUse hook: checks for urgent (critical/high) messages with 5min TTL
- Priority filter: `hiboss inbox --priority critical,high --count`
- Telegram reactions: agent-driven via `POST /api/messages/:id/react`

### v0.4 — Rich Telegram & Claude Code Integration (Done)
**Goal**: Native Telegram chat experience + deeper Claude Code integration.

#### Telegram Enhancements
- MarkdownV2 formatting in outgoing messages (with plain-text fallback)
- Reply threading via `reply_to_message_id`
- Inline keyboards for quick-reply (`hiboss ask --options "A,B,C"`)
- `callback_query` handler for button presses
- Telegram reactions: generic react API, agent decides emoji/timing

#### Claude Code Integration
- `last_used_at` tracking: server records agent's last API call timestamp
- Agent status dashboard: `hiboss agent list` shows online/idle/offline status
- Built-in hooks: `hiboss hook <event>` + `hiboss setup hooks`
- Agent Instructions template in CLAUDE.md for configuring agent behavior

### v0.5 — Smart Routing & Multi-Agent
- Priority-based routing: critical messages → all channels simultaneously
- Message routing rules: keyword/regex → specific agent
- Agent-level config: system prompts, default priority, rate limits
- Agent groups: broadcast messages to multiple agents

### v0.6 — Multi-boss & Teams
- Multiple bosses per agent with role-based permissions
- Group channels (one message → multiple recipients)
- Boss roles: admin, manager, viewer
- Audit log

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
