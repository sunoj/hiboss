# hiboss — AI Agent ↔ Boss Communication Tool

CLI tool for AI agents to send messages to their boss (human or AI) and receive replies. Supports Discord, Telegram, and Email channels.

## Agent Instructions

These are the recommended instructions for AI agents using hiboss. Copy this section into your project's CLAUDE.md and adjust as needed.

### Setup

Run `hiboss setup hooks` to install Claude Code hooks and inject agent instructions. This configures:
- **SessionStart hook**: injects unread boss messages into context at session start
- **PostToolUse hook**: checks for urgent (critical/high) messages every 5 minutes
- **CLAUDE.md prompt**: appends concise agent instructions (with user confirmation)

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
   hiboss ask --options "Short A,Short B,Short C" "Summary of what was done.\n\nNext options:\n1. Short A — full description of option A\n2. Short B — full description of option B\n3. Short C — full description of option C" --timeout 300
   ```
   **Important**: Option labels in `--options` must be short (Telegram buttons have length limits). Put full descriptions in the message body so the boss can read details before choosing.
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
  "priority": "critical | high | normal | low (default: agent's default_priority)",
  "channel": "discord | telegram | email (optional, uses default)",
  "options": ["Option A", "Option B"] ,
  "file_url": "string (optional, sends as photo/document on Telegram)",
  "type": "string (default: 'text', e.g. task_update, approval_request, steer_command)",
  "to": "string (optional, target agent name or ID for agent-to-agent messaging)",
  "idempotency_key": "string (optional, prevents duplicate sends)",
  "metadata": {}
}
```

Response (201, or 200 if idempotency_key matches existing message):
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
- `direction`: `agent_to_boss | boss_to_agent | agent_to_agent` (optional)
- `status`: `sent | delivered | read | replied` (optional)
- `priority`: comma-separated filter, e.g. `critical,high` (optional)
- `unread`: `true` — shortcut for incoming unread (boss_to_agent + agent_to_agent targeting self)
- `from`: filter by sender agent name or ID (optional)
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
Discord message webhook (bot API mode). Receives forwarded messages, creates boss_to_agent messages.

#### POST /api/webhooks/telegram
Telegram bot webhook. Receives messages from Telegram, creates boss_to_agent messages.

#### POST /api/webhooks/discord-interactions
Discord Interactions endpoint. Handles slash commands (`/msg`) and button clicks. Requires Ed25519 signature verification via `DISCORD_PUBLIC_KEY` env var.

Interaction types:
- Type 1 (PING): responds with `{ type: 1 }` (required by Discord)
- Type 2 (APPLICATION_COMMAND): handles `/msg <message>` slash command
- Type 3 (MESSAGE_COMPONENT): handles button clicks (same format as Telegram callback)

#### POST /api/webhooks/discord-interactions/register-commands
Register Discord slash commands. Called by CLI during setup.

Request:
```json
{
  "app_id": "string",
  "bot_token": "string"
}
```

### Attachment Endpoints

#### POST /api/attachments/upload
Upload a file. Supports multipart form (`file` field) or raw binary (with `Content-Type` and `X-Filename` headers). Max 10MB.

Response (201):
```json
{
  "key": "uuid",
  "url": "https://server/api/attachments/uuid",
  "filename": "string",
  "content_type": "string",
  "size": 12345
}
```

#### GET /api/attachments/:key
Serve an uploaded file. Public (no auth required). Returns file with correct content-type and cache headers.

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

### Agent Endpoints

#### GET /api/agents/me
Get current agent profile including config.

Response: `{ id, name, callback_url, default_priority, rate_limit, last_used_at, created_at }`

#### GET /api/agents
List all agents with online/idle/offline status.

#### PUT /api/agents/me/config
Update agent configuration.

Request:
```json
{
  "default_priority": "high",
  "rate_limit": 10
}
```

Both fields optional. `rate_limit` is messages per minute (null = unlimited).

#### PUT /api/agents/me/callback
Set webhook callback URL for push notifications.

#### DELETE /api/agents/me/callback
Remove webhook callback URL.

### Routing Rules Endpoints

#### GET /api/routing-rules
List routing rules owned by this agent.

#### POST /api/routing-rules
Create a routing rule.

Request:
```json
{
  "channel": "telegram | discord",
  "pattern": "regex string",
  "target_agent_id": "string",
  "priority": 0
}
```

#### DELETE /api/routing-rules/:id
Delete a routing rule (must be owned by this agent).

### Group Endpoints

#### GET /api/groups
List all groups with member count.

#### POST /api/groups
Create a group.

Request: `{ "name": "string", "description": "string (optional)" }`

#### GET /api/groups/:id
Get group detail with member list. Supports lookup by ID or name.

#### DELETE /api/groups/:id
Delete a group.

#### POST /api/groups/:id/members
Add a member. Request: `{ "agent_id": "string" }`

#### DELETE /api/groups/:id/members/:agentId
Remove a member.

#### POST /api/groups/:id/broadcast
Broadcast a message to all group members.

Request: `{ "body": "string", "priority": "normal" }`
Response: `{ "messages": [{ "agent_id", "message_id" }], "count": number }`

### Boss Endpoints

#### GET /api/bosses
List all bosses with agent access.

Response: `{ bosses: [{ id, name, role, telegram_user_id, discord_user_id, created_at, agent_ids }] }`

#### POST /api/bosses
Create a boss.

Request: `{ "name": "string", "role": "admin|manager|viewer", "telegram_user_id": "string", "discord_user_id": "string", "agent_id": "string (optional, links boss to an agent)" }`

#### GET /api/bosses/:id
Get boss detail with agent access list.

#### PATCH /api/bosses/:id
Update boss fields.

#### DELETE /api/bosses/:id
Delete a boss (cascades access entries).

#### POST /api/bosses/:id/access
Grant agent access. Request: `{ "agent_id": "string" }`

#### DELETE /api/bosses/:id/access/:agentId
Revoke agent access.

#### POST /api/bosses/:id/token
Generate or regenerate a boss auth token. Requires agent API key.

Response: `{ "id", "name", "token": "hb_boss_..." }` (token shown once)

### Boss Inbox Endpoints (Agent-as-Boss)

#### GET /api/boss/inbox
List messages from sub-agents. Requires boss-agent API key (agent linked to a boss via `agent_id`).

Query params: `unread`, `priority`, `limit`, `offset`, `count` (returns total only).

#### GET /api/boss/inbox/:id
Read a specific sub-agent message with replies.

#### POST /api/boss/inbox/:id/reply
Reply to a sub-agent message as boss. Notifies sub-agent via callback.

Request: `{ "body": "string" }`

#### PATCH /api/boss/inbox/:id
Update message status (mark as read).

Request: `{ "status": "read" }`

### Boss API Endpoints (Boss Token Auth)

Authenticated with boss token (`hb_boss_*`). Role-based access control.

#### GET /api/boss/me
Boss profile with list of accessible agent IDs.

#### GET /api/boss/agents
List agents the boss has access to.

#### GET /api/boss/messages
Messages from accessible agents. Params: `limit`, `offset`, `unread`, `priority`, `agent`.

#### GET /api/boss/messages/:id
Message detail with replies.

#### POST /api/boss/messages/:id/reply
Reply to an agent message. Request: `{ "body": "string" }`. Viewer role blocked.

#### GET /api/boss/sessions
Active sessions for accessible agents.

### Session Endpoints

#### POST /api/sessions
Register or update a session.

Request: `{ "id": "string", "branch": "string", "cwd": "string", "label": "string", "status": "working|blocked|waiting|idle|completed", "status_text": "string" }`

Response (201): `{ "id", "label", "branch", "cwd", "status", "status_text" }`

#### GET /api/sessions
List active sessions (within 15 min). Param: `all=true` for all agents.

Response: `{ sessions: [{ id, agent_id, agent_name, label, branch, cwd, status, status_text, started_at, last_seen_at }] }`

#### PATCH /api/sessions/:id
Heartbeat with optional status update. Accepts JSON body with `status` and/or `status_text`.

#### DELETE /api/sessions/:id
Deregister a session.

### Audit Endpoints

#### GET /api/audit
Query audit log. Params: `actor_type`, `action`, `limit` (default 50), `offset`.

Response: `{ entries: [...], total: number }`

## CLI Commands

```bash
# Setup
hiboss init https://hiboss-server.<user>.workers.dev  # bootstrap first key
hiboss config set server https://hiboss-server.<user>.workers.dev
hiboss config set key <api-key>
hiboss config set channel discord   # default channel
hiboss setup hooks                  # configure Claude Code hooks (project)
hiboss setup hooks --global         # configure for all Claude Code sessions
hiboss setup hooks --remove         # remove hiboss hooks

# Send (async)
hiboss send "Deployment complete. 3 tests failed."
hiboss send --priority high "Build failed, need help."
hiboss send --channel telegram "Quick update via TG."
hiboss send --file-url "https://example.com/screenshot.png" "See attached"
hiboss send --type task_update "Build v2.1 deployed successfully"
hiboss send --file ./screenshot.png "See attached"
hiboss send --to worker-1 "Implement OAuth2 login"                    # agent-to-agent
hiboss send --to worker-1 --task "Implement OAuth2" --files src/auth/ # with context

# Ask (blocking, waits for reply)
hiboss ask "Option A or B for the migration?"
hiboss ask --timeout 60 "Quick question: proceed with deploy?"
hiboss ask --options "A,B,C" "Pick one:\n1. A — details\n2. B — details\n3. C — details"
hiboss ask --actions "Approve:aid merge t-123,Reject:echo rejected" "Deploy to prod?"
hiboss ask --to reviewer "Review feat/oauth branch"                   # ask another agent

# Inbox
hiboss inbox                              # unread messages (boss + agent)
hiboss inbox --all                        # all messages
hiboss inbox --limit 5                    # last 5
hiboss inbox --priority critical,high     # urgent only
hiboss inbox --priority critical --count  # count of urgent unread
hiboss inbox --from lead-agent            # from specific agent

# Read a message
hiboss read <msg-id>

# Reply to boss message
hiboss reply <msg-id> "Done, deployed to staging."

# React to a message with emoji
hiboss react <msg-id> "👀"
hiboss react <msg-id> "✅"

# Status of sent message
hiboss status <msg-id>

# Reply with task status
hiboss reply <msg-id> --status accepted "Starting now"
hiboss reply <msg-id> --status completed "Done. PR ready."
hiboss reply <msg-id> --status blocked "Need DB schema decision"

# Agent config
hiboss agent config                          # view current config
hiboss agent config --default-priority high  # set default priority
hiboss agent config --rate-limit 10          # set rate limit (msg/min)
hiboss agent config --rate-limit 0           # disable rate limit
hiboss agent config --role orchestrator      # set session role

# Routing rules
hiboss route list                            # list routing rules
hiboss route add --channel telegram --pattern "deploy.*" --target <agent-id>
hiboss route add --channel discord --pattern "urgent" --target <agent-id> --priority 10
hiboss route remove <rule-id>

# Agent groups
hiboss group list                            # list groups
hiboss group create dev-team --description "Development agents"
hiboss group show dev-team                   # view group + members
hiboss group add-member <group-id> <agent-id>
hiboss group remove-member <group-id> <agent-id>
hiboss group broadcast <group-id> "Stop all work" --priority high
hiboss group delete <group-id>

# Discord bidirectional setup
hiboss channel discord-setup --app-id <id> --bot-token <token>  # register /msg slash command

# Boss management
hiboss boss list                                     # list bosses
hiboss boss add "Ming" --role admin --telegram-user-id 123
hiboss boss show <boss-id>                           # view boss + accessible agents
hiboss boss update <boss-id> --discord-user-id 456   # update boss fields
hiboss boss grant <boss-id> <agent-id>               # grant agent access
hiboss boss revoke <boss-id> <agent-id>              # revoke agent access
hiboss boss remove <boss-id>                         # delete boss

# Agent-as-boss
hiboss boss add "Manager" --agent-id <agent-id>      # create agent-boss
hiboss boss inbox                                     # list sub-agent messages
hiboss boss inbox --priority critical,high            # urgent only
hiboss boss inbox --count                             # count unread
hiboss boss reply <msg-id> "Your reply here"          # reply as boss

# Session status board
hiboss ss                                             # kanban board of session statuses
hiboss ss set working "implementing feature X"        # set session status manually
hiboss ss set waiting "need boss approval"            # mark as waiting
hiboss ss set blocked "external dependency"           # mark as blocked
hiboss ss set completed                               # mark as done

# Background SSE daemon
hiboss daemon start                                   # start background SSE listener
hiboss daemon stop                                    # stop background SSE listener
hiboss daemon status                                  # check if daemon is running
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

Messages reach the agent through four layers:

| Layer | Trigger | Scope | Latency |
|-------|---------|-------|---------|
| **SSE Daemon** | Background process, reads local file | All messages (boss + peer) | ~2s SSE + next tool call |
| **PostToolUse hook** | Every tool call | Daemon: local file (0ms); Fallback: a2a 30s TTL, boss 5min TTL | 0ms–5min |
| **MCP SSE push** | Real-time SSE background listener | All messages (terminal-visible) | Real-time* |
| **SessionStart hook** | New session start | All unread + starts daemon | Session gap |

*MCP `notifications/message` is displayed in terminal but NOT injected into agent context by Claude Code.

**With daemon** (default): SSE daemon writes messages to local file → PostToolUse drains file on every tool call → near-instant delivery into agent context.

**Without daemon** (fallback): PostToolUse polls server via HTTP with dual TTL — 30s for peer messages (only delivery mechanism), 5min for boss urgent (also have Telegram/Discord).

### Channel Resolution Order

When a message is sent, the channel is resolved with this precedence:

1. **CLI `--channel` flag** — explicit override, always wins
2. **Server `channel_routing`** — per-priority routing (e.g. `normal=discord, high=telegram`), used when no `--channel` is given
3. **Server channel config fallback** — picks the most recently configured channel if no routing matches

Note: `hiboss config set channel` sets a **local CLI default** that was previously sent on every request. As of v0.10.1, the CLI no longer sends this — it only sends a channel when `--channel` is explicitly used. This allows server-side `channel_routing` to work as intended.

To configure routing: `hiboss agent config --channel-routing "normal=discord,high=telegram"`
To check effective routing: `hiboss doctor`

### Reactions (Discord & Telegram)
Agents can set reaction emojis on messages via `hiboss react <id> <emoji>` (works on both Discord and Telegram). Boss reactions are captured via webhooks. Agents can read reactions with `hiboss read <id> --reactions`. Example conventions:
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
- HTML formatting in outgoing messages (with plain-text fallback)
- Reply threading via `reply_to_message_id` (bidirectional: agent→boss and boss→agent)
- Inline keyboards for quick-reply (`hiboss ask --options "A,B,C"`)
- `callback_query` handler for button presses
- Telegram reactions: generic react API, agent decides emoji/timing
- `telegram_message_id` stored in metadata for reply linking
- CLI escape sequences: `\n` and `\t` in message body converted to real characters

#### Claude Code Integration
- `last_used_at` tracking: server records agent's last API call timestamp
- Agent status dashboard: `hiboss agent list` shows online/idle/offline status
- Built-in hooks: `hiboss hook <event>` + `hiboss setup hooks`
- Agent config: default priority, rate limiting (messages/min)
- CLAUDE.md prompt injection: `setup hooks` appends agent instructions with user confirmation

### v0.5 — Smart Routing & Multi-Agent (Done)
**Goal**: Intelligent message delivery and multi-agent coordination.

#### Multi-Channel Delivery
- Critical/high priority messages delivered to ALL configured channels simultaneously
- Delivery results tracked per-channel in message metadata
- Normal/low priority unchanged (single channel)

#### Routing Rules
- Regex-based rules route incoming boss messages to specific agents
- Rules evaluated by priority (highest first), first match wins
- CRUD API: `GET/POST /api/routing-rules`, `DELETE /api/routing-rules/:id`
- CLI: `hiboss route list`, `hiboss route add`, `hiboss route remove`

#### Agent Groups
- Named groups with description and membership management
- Broadcast: send one message to all group members
- CRUD API: `GET/POST /api/groups`, group member management, broadcast
- CLI: `hiboss group list/create/show/delete`, `hiboss group add-member/remove-member`, `hiboss group broadcast`

### v0.5.1 — Structured Types & Action Callbacks (Done)
**Goal**: Typed messages for downstream automation + action buttons that trigger shell commands.

#### Structured Message Types
- `type` field on messages (default: `text`), e.g. `task_update`, `approval_request`, `steer_command`
- Server accepts `type` in POST /api/messages, stores in D1, returns in all responses
- CLI: `hiboss send --type task_update "Build deployed"`

#### Action Buttons Callback
- `hiboss ask --actions "Approve:aid merge t-123,Reject:echo nope" "Deploy?"`
- Parses `Label:command` pairs → options (Telegram buttons) + `metadata.actions` map
- Webhook callback handler copies matched action command to reply `metadata.action`
- CLI auto-executes the action command when poll reply arrives with `metadata.action`

### v0.5.2 — File Attachments (Done)
**Goal**: Upload and attach files to messages via R2 storage.

#### R2 Attachments
- `POST /api/attachments/upload` — multipart or raw binary upload (max 10MB)
- `GET /api/attachments/:key` — public file serving with correct content-type
- Files stored in R2 with metadata (agent_id, filename, uploaded_at)
- CLI: `hiboss send --file ./screenshot.png "See attached"`
- CLI: `hiboss ask --file ./report.pdf "Review this?"`
- Telegram sendDocument with fallback to text link if Telegram rejects the file

### v0.6 — Reliability & Polish (Done)
**Goal**: Production-grade reliability, code quality, and developer experience.

#### Code Cleanup
- Split `cli/src/client.rs` into modules (core, routing, groups)
- Extract delivery functions to `server/src/routes/delivery.ts`
- Enforce ≤300-line file limit across all source files

#### Delivery Reliability
- Retry failed channel deliveries (1 retry, 2s delay, server-side)
- Idempotency keys on POST /api/messages to prevent duplicate sends

#### CLI Polish
- `hiboss doctor` command: validate config, test server connectivity, check channel setup
- Consistent exit codes (0=success, 1=user error, 2=server error, 3=config error)

#### Discord Webhook Support
- Discord channel adapter supports webhook URLs (no bot required)
- Per-message username from agent name, custom avatar_url
- CLI: `hiboss channel set discord --webhook-url <url> --avatar-url <url>`

### v0.7 — Discord Bidirectional (Done)
**Goal**: Boss can send messages and click buttons from Discord, not just receive.

#### Discord Interactions API
- `POST /api/webhooks/discord-interactions` — Ed25519 verified interaction endpoint
- `/msg <message>` slash command for boss→agent messages
- Button click handling for `--options` messages (same as Telegram inline keyboard)
- Action metadata forwarding on button clicks
- Ed25519 signature verification using Web Crypto API (no external deps)

#### Discord Buttons
- `--options` messages include Discord button components (Action Rows)
- Buttons work in both webhook and bot API modes
- Same `msgPrefix:option` format as Telegram callback_data

#### CLI Setup
- `hiboss channel discord-setup --app-id <id> --bot-token <token>` registers `/msg` slash command
- Prints setup instructions for Interactions Endpoint URL and DISCORD_PUBLIC_KEY

#### Options Expiry
- Telegram inline keyboard buttons auto-removed when poll times out
- Prevents boss from clicking stale options

### v0.8 — Smart Channel Routing (Done)
**Goal**: Automatic per-priority channel routing.

#### Per-Priority Channel Defaults
- Configure default channel per priority level (e.g. normal→discord, high→telegram)
- `channel_routing` JSON column on api_keys: `{ "normal": "discord", "high": "telegram" }`
- Message creation resolves channel from routing config when no explicit `--channel` given
- CLI: `hiboss agent config --channel-routing "normal=discord,high=telegram"`

### v0.9 — Multi-boss & Teams (Done)
**Goal**: Multiple bosses with role-based permissions and audit trail.

#### Boss Management
- `bosses` table with admin/manager/viewer roles
- Boss identity via Telegram user ID and/or Discord user ID
- CRUD API: `GET/POST /api/bosses`, `GET/PATCH/DELETE /api/bosses/:id`
- Prefix matching on boss IDs (8-char short IDs work)

#### Access Control
- `boss_agent_access` table: grant/revoke per boss-agent pair
- Admin role: full access to all agents
- Manager/viewer: access only to explicitly granted agents
- Viewer: can view messages and press buttons, cannot send messages
- Backwards compatible: if no bosses exist, all messages allowed (legacy mode)

#### Webhook Auth
- Telegram webhook identifies boss by `from.id`
- Discord webhook + interactions identify boss by `member.user.id` / `author.id`
- Unknown senders blocked when boss system is active
- Boss ID and name stored in message metadata

#### Audit Log
- `audit_log` table with actor type/id, action, resource tracking
- `GET /api/audit` with actor_type and action filters
- `logAudit()` helper for fire-and-forget writes

#### CLI
- `hiboss boss list` — list bosses with roles and channel IDs
- `hiboss boss add <name> --role admin --telegram-user-id <id>`
- `hiboss boss show/update/remove <id>`
- `hiboss boss grant <boss-id> <agent-id>` / `hiboss boss revoke <boss-id> <agent-id>`

### v0.10 — Agent-as-Boss & Session Isolation (Done)
**Goal**: Allow agents to act as bosses for other agents, and isolate messages per session.

#### Agent-as-Boss
- `agent_id` column on `bosses` table: links a boss to an agent identity
- New `api` channel type: agent-to-agent messaging without external chat platforms
- Boss inbox API: `GET /api/boss/inbox` — boss-agent reads sub-agent messages
- Boss reply API: `POST /api/boss/inbox/:id/reply` — boss-agent replies
- Boss read API: `GET /api/boss/inbox/:id` — read message with replies
- Boss mark-read: `PATCH /api/boss/inbox/:id` — mark messages as read
- `notifyBossAgents()`: callback push to boss-agents when sub-agents send messages
- CLI: `hiboss boss add "Name" --agent-id <id>` to create agent-boss
- CLI: `hiboss boss inbox` / `hiboss boss reply <id> "message"`

#### Session-Scoped Messages
- `session_id` column on `messages` table
- SessionStart hook generates unique session ID per Claude Code session
- Messages tagged with session_id, inbox filters by session
- Boss-initiated messages (not replies) visible across all sessions
- CLI `send`, `ask`, `inbox` automatically attach/filter by session

### v0.10.1 — Channel Routing Fix & Docs (Done)
**Goal**: Fix CLI overriding server-side channel routing, improve discoverability.

#### Channel Routing Fix
- CLI `send`/`ask` no longer send `config.channel` — only `--channel` explicit flag
- Server-side `channel_routing` now works as intended (was always overridden by CLI default)

#### Action Result Feedback
- `--actions` button click auto-sends command result back to boss as `type=action_result`
- Captures stdout/stderr + exit code, sends last 5 lines

#### Documentation & Help Improvements
- `--channel` help text explains it overrides server routing
- `--channel-routing` help text explains precedence and `"none"` to clear
- `hiboss doctor` shows effective channel routing per priority
- CLAUDE.md: new "Channel Resolution Order" section with precedence rules

### v0.10.4 — Full Reaction Support + Message Isolation (Done)
**Goal**: Bidirectional reaction support on both Discord and Telegram, plus project-level message isolation.

#### Discord Reactions
- `discord_message_id` tracked in metadata (webhook `?wait=true` returns message ID)
- `POST /api/messages/:id/react` sends emoji via Discord bot API
- `GET /api/messages/:id/reactions` lazy-fetches reactions from Discord REST API
- Discord config accepts `bot_token` + `channel_id` alongside `webhook_url` (hybrid mode for reactions)

#### Telegram Reactions
- `message_reaction` webhook event handler stores boss reactions in message metadata
- `GET /api/messages/:id/reactions` returns stored reactions from metadata

#### Telegram Topics (Message Isolation)
- `use_topics: true` in Telegram channel config enables per-agent forum topics
- Auto-creates a Telegram forum topic named after the agent on first message
- `message_thread_id` stored in channel config after creation, reused for all subsequent sends
- Webhook routes incoming messages by `message_thread_id` to the correct agent
- Requires a supergroup with Topics enabled
- CLI: `hiboss channel set telegram --chat-id <id> --bot-token <token> --use-topics`
- CLI: `hiboss channel set telegram --chat-id <id> --bot-token <token> --topic-id <thread-id>`

#### Discord Setup Improvements
- `--app-id` is now optional in `discord-setup` (auto-detected from bot token)
- Lists available guild channels if `--channel-id` is omitted
- Auto-saves `bot_token` + `channel_id` to channel config (no separate `channel set` needed)

#### CLI
- `hiboss read <id> --reactions` fetches and displays reactions
- `hiboss react <id> <emoji>` works on both Discord and Telegram
- `hiboss channel set discord --webhook-url <url> --bot-token <token> --channel-id <id>` for hybrid mode

### v0.11 — Cross-Session Agent Communication (Done)
**Goal**: Enable direct agent-to-agent messaging across Claude Code sessions sharing the same API key.

Design principle: Agent = permanent identity (API key), Session = ephemeral workspace (Claude Code instance).

#### First-Class Sessions
- `sessions` table: id, agent_id, label, branch, cwd, started_at, last_seen_at
- `POST /api/sessions` — register/upsert session (auto-labeled as `<project>/<branch>`)
- `GET /api/sessions` — list active sessions (within 15 min staleness window)
- `PATCH /api/sessions/:id` — heartbeat (update last_seen_at)
- `DELETE /api/sessions/:id` — deregister session
- SessionStart hook auto-generates session ID, registers with server

#### Agent-to-Agent Messaging
- `target_agent_id` and `target_session_id` columns on messages table
- `POST /api/messages` accepts `to` field: resolves agent name → agent ID → session label → session ID
- `direction: agent_to_agent` — skips Telegram/Discord delivery (peer-only)
- Smart `--to` resolution: tries agent name, agent ID prefix, session label, session ID prefix
- `GET /api/messages?unread=true` includes a2a messages targeting self
- `GET /api/messages?direction=agent_to_agent` filter by direction
- `GET /api/messages?from=<agent>` filter by sender

#### Dual TTL Polling
- PostToolUse: 30-sec TTL for a2a messages (only delivery mechanism), 5-min TTL for boss urgent
- Heartbeat: session last_seen_at updated every 30 seconds via PostToolUse

#### Hooks
- SessionStart: register session, show peer sessions, show unread (boss + a2a)
- PostToolUse: dual TTL check, heartbeat session
- Clear instructions to use `hiboss reply` (not `hiboss send`) for peer message replies

### v0.12 — Session-Scoped SSE Streaming (Done)
**Goal**: Real-time message delivery for both boss and peer messages via SSE.

#### SSE Enhancements
- `GET /api/messages/stream` now includes `agent_to_agent` messages (was boss-only)
- Optional `?session=` param for session-level message filtering
- Session-scoped: boss messages + a2a targeting agent (no session) + a2a targeting specific session

#### CLI Updates
- `hiboss watch` auto-detects session ID, passes to SSE stream
- `hiboss watch` shows `[peer]`/`[boss]` labels for message origin
- `hiboss bot` also session-scoped

### v0.13 — Background SSE Daemon & MCP Server (Done)
**Goal**: Near-real-time message delivery into agent context + MCP tooling.

#### Background SSE Daemon
- `hiboss daemon start/stop/status` — manage background SSE listener process
- Daemon maintains SSE connection, writes messages to local file (`/tmp/hiboss-daemon-*.pending`)
- PostToolUse hook reads from local file (0ms) when daemon is running
- Falls back to HTTP polling when daemon not running
- SessionStart hook auto-starts daemon on new session
- Session-scoped: daemon connects with session ID for filtered streaming

#### MCP Server Updates
- SSE listener connects with session ID for scoped message streaming
- `send_to_peer` tool — send messages to peer sessions via MCP
- `list_sessions` tool — discover active peer sessions
- Handles `agent_to_agent` message notifications
- Context reads session ID from CLI's session file

### v0.14 — Session Status Tracking & Dashboard (Done)
**Goal**: Work state visibility per session with auto-inference and manual control.

#### Session Status
- `status` column on sessions: working, blocked, waiting, idle, completed
- `status_text` column: brief description of current activity
- Auto-inference from messages: send→working, ask (blocking)→waiting, high priority→waiting
- `POST /api/sessions` and `PATCH /api/sessions/:id` accept status/status_text
- Stop hook: marks session completed, kills daemon, cleans up temp files
- Stop event registered in Claude Code hooks via `hiboss setup hooks`

#### Session Status CLI
- `hiboss ss` — kanban-style terminal board grouped by status
- `hiboss ss set <status> [text]` — manual status override
- Validation: rejects invalid statuses with helpful error

#### Web Dashboard
- Self-contained HTML dashboard at `/dashboard` (inline CSS/JS, no external deps)
- Three tabs: Messages (filterable), Sessions (kanban board), Agents (status)
- Sessions tab: kanban columns for working/blocked/waiting/idle/completed
- Auto-refresh every 10s, dark theme, responsive
- Auth via URL param `?key=` → localStorage, login form fallback

### v0.15 — Boss Authentication Tokens (Done)
**Goal**: Direct API access for bosses via their own auth tokens.

#### Boss Tokens
- `token_hash` column on `bosses` table (SHA-256, same scheme as agent keys)
- `POST /api/bosses/:id/token` — generate/regenerate a boss token (`hb_boss_*` prefix)
- Token is shown once on creation (not stored in plaintext)

#### Boss Auth Middleware
- `bossAuth` middleware: authenticates boss tokens, sets boss context
- `dualAuth` middleware: accepts either agent or boss tokens
- Helpers: `getBossId()`, `getBossRole()`, `getBossName()`, `isBossAuth()`

#### Boss API (`/api/boss/*`)
- `GET /api/boss/me` — boss profile with accessible agent IDs
- `GET /api/boss/agents` — list agents the boss can access
- `GET /api/boss/messages` — messages from accessible agents (with filters)
- `GET /api/boss/messages/:id` — message detail with replies
- `POST /api/boss/messages/:id/reply` — boss replies to agent (viewer role blocked)
- `GET /api/boss/sessions` — active sessions for accessible agents
- Role-based access: admin sees all, manager/viewer sees granted agents only

#### Dashboard
- Supports both agent and boss tokens with auto-detection
- Boss mode uses `/api/boss/*` endpoints for messages, sessions, agents
- Shows "(boss)" label in header when authenticated as boss

### v1.0 — Production Ready
- Per-boss channel preferences
- Comprehensive audit logging on all mutations

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
