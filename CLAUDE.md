# hiboss — AI Agent ↔ Boss Communication Tool

CLI tool for AI agents to send messages to their boss (human or AI) and receive replies. Supports Discord, Telegram, and Email channels.

## Architecture

```
hiboss CLI (TypeScript) ←HTTP→ hiboss-server (Cloudflare Worker + Hono)
                                    ↕ D1 (messages)
                                    ↕ Channel Adapters (Discord, Telegram, Email)
                                    ↕ Boss (human or AI)
```

## Project Structure

- `cli/` — TypeScript CLI package (commander.js, published as `hiboss` on npm)
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

## Code Conventions

- TypeScript strict mode everywhere
- Files ≤ 300 lines, functions ≤ 50 lines
- ESM modules (type: "module")
- Error handling: throw typed errors, CLI catches and prints user-friendly messages
- Server: Hono framework, use `c.json()` for responses
- CLI: commander.js for argument parsing, `conf` for config storage
- No `any` types at module boundaries
