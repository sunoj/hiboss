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

`options` must be an array of one to five non-empty, unique strings. String values
and comma-separated option lists are rejected.

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
Upload a file. Multipart form (`file` field) or raw binary (with `Content-Type` and `X-Filename`).
Multipart uploads are capped at 10MB. Raw image uploads are capped at 10MB; raw `video/*`
uploads are capped at 50MB. Raw uploads accept `image/*` and `video/mp4`.

Response (201): `{ "key": "uuid", "url": "...", "filename": "...", "content_type": "...", "size": 12345 }`

### GET /api/attachments/:key
Serve uploaded file. Public (no auth). Correct content-type and cache headers.

## Progress Feed Endpoints

### POST /api/progress
Create an agent-owned progress post. Request: `{ "body": "string", "project?": "string",
"session_id?": "string", "media?": [MediaItem], "tags?": ["string"] }`. Body is limited
to 2000 characters, media to 4 items, and tags to 8 items. Every media `url` and optional
`poster_url` must reference an existing attachment owned by the posting agent.

### GET /api/progress
List accessible progress posts. Supports `project`, `limit` (default 20, max 100),
`agent_id` for bosses, and `before` as a JSON cursor `{ "created_at": "...", "id": "..." }`.
Results are ordered by `created_at DESC, id DESC`.

Response: `{ "posts": [Post], "next_cursor": { "created_at": "...", "id": "..." } | null }`.

### GET /api/progress/projects
List accessible projects with post counts and their latest post time.

### GET /api/progress/:id
Fetch one accessible progress post.

### DELETE /api/progress/:id
Delete a progress post owned by the agent or any post accessible to a boss.

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
Admin only. Rotate a boss auth token (`hb_boss_*` prefix). Token shown once; every prior token for the target boss, including the caller's, is revoked. When rotating the authenticated boss itself, use the returned token immediately.

### GET /api/boss/tokens
Admin only. List the authenticated boss's token metadata: `{ "tokens": [{ "id", "label", "created_at", "last_used_at", "revoked_at" }] }`.
Token hashes and bearer token values are never returned.

### DELETE /api/boss/tokens/:tokenId
Revoke one token belonging to the authenticated boss. Any boss may revoke its own token to sign out that device; the response is `{ "ok": true, "authenticated": false }` and the caller's next request is unauthenticated. Revoking another token is admin-only and returns `{ "ok": true }`.

### POST /api/boss/tokens/revoke-others
Admin only. Revoke every token belonging to the authenticated boss except the token making the request. Returns `{ "revoked": number }`.

Token-management controls do not prevent a stolen admin bearer from revoking sibling devices; this residual risk is accepted. The five-minute, single-use pairing-code lifetime protects an unredeemed QR code, not a bearer token that has already been issued.

### POST /api/boss/pairing
Admin only. Issue a short-lived, single-use QR pairing code for the authenticated boss. At most five active codes are retained per boss; expired and consumed rows are cleaned before minting. A concurrent burst can exceed this cap by its concurrency factor because the cleanup, count, and insert are separate D1 statements. Response:
`{ "code": "hb_pair_<64 hex characters>", "expires_at": "ISO8601" }`.
The server stores only a hash of the code.

### POST /api/pairing/redeem
Unauthenticated by design. Redeem a pairing code once to create a new boss token for a device.
Request: `{ "code": "hb_pair_<64 hex characters>", "device_label": "string" }`.
Response:
`{ "token": "hb_boss_<64 hex characters>", "boss": { "id", "name", "role" } }`.
The new token is independent from all other boss tokens; an existing device remains online.

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
Boss profile with the caller's `token_id` and accessible agent IDs. The token ID is safe to use with `DELETE /api/boss/tokens/:tokenId` to sign out this device.

### GET /api/boss/agents
Agents the boss can access.

### GET /api/boss/messages
Messages from accessible agents. Params: `limit`, `offset`, `unread`, `priority`, `agent`, `search`, `direction`.

### GET /api/boss/messages/:id
Message detail with replies.

### POST /api/boss/messages/:id/reply
Boss replies to an agent. Viewer role is blocked. For option messages, `body` must
exactly match an option. The first selection returns 201; later concurrent
selections return 409 `option already resolved`.

### GET /api/boss/stream?options=true
Streams active option messages for all agents accessible to the Boss Token. Every
connected client receives the same active messages.

SSE events:
- `message`: the full active message payload.
- `resolved`: `{ "id": "message-id", "status": "replied" | "expired" }`.

The stream sends keepalives every 15 seconds and closes after five minutes; clients
must reconnect.

### GET /api/boss/stream?feed=true
Read-only SSE feed of **all** messages the boss can see, across every direction
(`agent_to_boss`, `boss_to_agent`, `agent_to_agent`). Unlike the option/agent
streams it is a passive monitor and **never mutates message status**. Used by the
web console's live message feed. Same `message` event shape; 15s keepalives, 5min cap.

### GET /api/boss/overview
Single-shot dashboard aggregate for the web console 总览:
```json
{
  "kpis": { "activeSessions": 5, "workingSessions": 3, "pendingDecisions": 4,
            "blockingPending": 2, "unread1h": 12 },
  "priorityDistribution": { "critical": 6, "high": 14, "normal": 28, "low": 9 },
  "sessionStatus": { "working": 3, "waiting": 1, "blocked": 1, "idle": 0, "completed": 7 },
  "channels": [ { "channel": "discord", "configured": true },
                { "channel": "telegram", "configured": false },
                { "channel": "api", "configured": true } ]
}
```
Priority distribution and session status are over the last 24h; `activeSessions`
counts sessions seen in the last 15 minutes.

### POST /api/boss/devices
Registers an iOS device's APNs token for push. Body:
`{ "token": "<apns-hex>", "bundleId": "ai.hiboss.app", "environment": "sandbox"|"production", "platform": "ios" }`.
Upserts by device token for the authenticated boss. Returns `{ "ok": true }`.

### DELETE /api/boss/devices/:token
Unregisters a device token for the authenticated boss.

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
