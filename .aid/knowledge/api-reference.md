# hiboss API Reference

Base URL: configured via `hiboss config set server <url>`
Auth: `Authorization: Bearer <api-key>` header on all requests.

## Message Endpoints

### POST /api/messages
Send a message from agent to boss.

Request:
```json
{
  "body": "string (required)",
  "mode": "async | blocking",
  "priority": "critical | high | normal | low (default: agent's default_priority)",
  "channel": "discord | telegram | email (optional, uses default)",
  "options": ["Option A", "Option B"],
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
  "reply": { "id": "string", "body": "string", "created_at": "ISO8601" }
}
```

If timeout, returns 202 with `status: "sent"` (agent can poll later).

### GET /api/messages
List messages for this agent.

Query params: `direction` (agent_to_boss|boss_to_agent|agent_to_agent), `status` (sent|delivered|read|replied), `priority` (comma-separated), `unread` (true), `from` (agent name/ID), `search` (full-text), `limit` (default 20), `offset` (default 0).

Response (200): `{ "messages": [Message], "total": number }`

### GET /api/messages/:id
Get a single message with its reply chain. Response includes `replies: Message[]`.

### POST /api/messages/:id/reply
Reply to a message. Request: `{ "body": "string" }`. Response (201): message object.

### PATCH /api/messages/:id
Update message status. Request: `{ "status": "read" }`.

### POST /api/messages/:id/react
Set a reaction emoji. Request: `{ "emoji": "👀" }`. Response: `{ "ok": true }`.

### POST /api/messages/:id/poll
Long-poll for reply to a blocking message. Query: `timeout` (default 300, max 300).

### GET /api/messages/stream
SSE stream for real-time messages. Optional `?session=` param for session-level filtering.

## Channel Webhook Endpoints

### POST /api/webhooks/discord
Discord message webhook (bot API mode). Creates boss_to_agent messages.

### POST /api/webhooks/telegram
Telegram bot webhook. Creates boss_to_agent messages.

### POST /api/webhooks/discord-interactions
Discord Interactions endpoint (Ed25519 verified). Handles `/msg` slash command and button clicks.

### POST /api/webhooks/discord-interactions/register-commands
Register Discord slash commands. Request: `{ "app_id": "string", "bot_token": "string" }`.

## Attachment Endpoints

### POST /api/attachments/upload
Upload a file. Multipart form (`file` field) or raw binary (with `Content-Type` and `X-Filename`). Max 10MB.

Response (201): `{ "key": "uuid", "url": "...", "filename": "...", "content_type": "...", "size": 12345 }`

### GET /api/attachments/:key
Serve uploaded file. Public (no auth). Correct content-type and cache headers.

## Admin Endpoints

### POST /api/keys
Create API key. Request: `{ "name": "string" }`. Response: `{ "id", "name", "key" }` (key shown once).

### GET /api/channels
List channel configs for this agent.

### PUT /api/channels/:channel
Set channel config. Discord: `{ "channel_id", "bot_token" }`. Telegram: `{ "chat_id", "bot_token" }`.

## Agent Endpoints

### GET /api/agents/me
Agent profile: `{ id, name, callback_url, default_priority, rate_limit, last_used_at, created_at }`.

### GET /api/agents
List all agents with online/idle/offline status.

### PUT /api/agents/me/config
Update agent config. Request: `{ "default_priority": "high", "rate_limit": 10 }`.

### PUT /api/agents/me/callback
Set webhook callback URL.

### DELETE /api/agents/me/callback
Remove webhook callback URL.

## Routing Rules Endpoints

### GET /api/routing-rules
List routing rules.

### POST /api/routing-rules
Create rule. Request: `{ "channel", "pattern", "target_agent_id", "priority" }`.

### DELETE /api/routing-rules/:id
Delete a routing rule.

## Group Endpoints

### GET /api/groups
List groups with member count.

### POST /api/groups
Create group. Request: `{ "name", "description" }`.

### GET /api/groups/:id
Group detail with members. Supports ID or name lookup.

### DELETE /api/groups/:id
Delete group.

### POST /api/groups/:id/members
Add member. Request: `{ "agent_id" }`.

### DELETE /api/groups/:id/members/:agentId
Remove member.

### POST /api/groups/:id/broadcast
Broadcast. Request: `{ "body", "priority" }`. Response: `{ "messages": [...], "count" }`.

## Boss Endpoints

### GET /api/bosses
List bosses with agent access.

### POST /api/bosses
Create boss. Request: `{ "name", "role", "telegram_user_id", "discord_user_id", "agent_id" }`.

### GET /api/bosses/:id
Boss detail with agent access list.

### PATCH /api/bosses/:id
Update boss fields.

### DELETE /api/bosses/:id
Delete boss (cascades access).

### POST /api/bosses/:id/access
Grant agent access. Request: `{ "agent_id" }`.

### DELETE /api/bosses/:id/access/:agentId
Revoke agent access.

### POST /api/bosses/:id/token
Generate boss auth token (`hb_boss_*` prefix). Token shown once.

## Boss Inbox Endpoints (Agent-as-Boss)

Requires boss-agent API key (agent linked to a boss via `agent_id`).

### GET /api/boss/inbox
List sub-agent messages. Params: `unread`, `priority`, `limit`, `offset`, `count`.

### GET /api/boss/inbox/:id
Read message with replies.

### POST /api/boss/inbox/:id/reply
Reply as boss. Request: `{ "body" }`.

### PATCH /api/boss/inbox/:id
Mark as read. Request: `{ "status": "read" }`.

## Boss API Endpoints (Boss Token Auth)

Authenticated with `hb_boss_*` tokens. Role-based access control.

### GET /api/boss/me
Boss profile with accessible agent IDs.

### GET /api/boss/agents
Agents the boss can access.

### GET /api/boss/messages
Messages from accessible agents. Params: `limit`, `offset`, `unread`, `priority`, `agent`, `search`, `direction`.

### GET /api/boss/messages/:id
Message detail with replies.

### POST /api/boss/messages/:id/reply
Boss replies to agent. Viewer role blocked.

### GET /api/boss/sessions
Active sessions for accessible agents.

### GET/PUT /api/boss/me/preferences
Boss preferences (preferred_channel, quiet_hours, timezone, notify_priorities).

## Session Endpoints

### POST /api/sessions
Register/upsert session. Request: `{ "id", "branch", "cwd", "label", "status", "status_text" }`.

### GET /api/sessions
List active sessions (15 min window). Param: `all=true` for all agents.

### PATCH /api/sessions/:id
Heartbeat with optional status/status_text.

### DELETE /api/sessions/:id
Deregister session.

## Audit Endpoints

### GET /api/audit
Query audit log. Params: `actor_type`, `action`, `limit` (default 50), `offset`.
