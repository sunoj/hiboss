# hiboss MCP Channel — Design Spec

## Problem

hiboss currently integrates with Claude Code via hooks (SessionStart, PostToolUse, Stop).
This is polling-based — messages only arrive when hooks fire, not in real-time.
Claude sees hook stdout, not native `<channel>` tags. Tools are called via `Bash("hiboss ...")`.

## Goal

Add a **local MCP server** that runs as a Claude Code plugin/channel, providing:
1. Real-time message delivery via `notifications/claude/channel`
2. Native MCP tools (send, ask, reply, react, inbox)
3. Plugin install + skill-based configuration
4. Clean lifecycle management (CC manages start/stop)

## Architecture

```
Claude Code ←stdio/MCP→ hiboss-mcp (local, Bun)
                              ↕ SSE (existing /api/messages/stream)
                         hiboss-server (Cloudflare Worker)
                              ↕ D1 + Channel Adapters
                         Boss (Telegram/Discord)
```

The MCP server is a **thin bridge** — it does NOT duplicate server logic.
It connects to the existing SSE endpoint for real-time inbound messages,
and wraps the existing REST API for outbound tools.

## Directory Structure

```
mcp/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── .mcp.json                # How CC starts the server
├── package.json             # bun + deps
├── server.ts                # MCP server (~250 lines)
├── skills/
│   └── configure/
│       └── SKILL.md         # /hiboss:configure skill
└── README.md
```

## MCP Server (server.ts)

### Startup

1. Load config from `~/.config/hiboss/config.json` (same as CLI)
2. Validate server_url + api_key exist
3. Start SSE connection to `{server_url}/api/messages/stream?session={session_id}`
4. Connect MCP via StdioServerTransport

### Shutdown

- stdin EOF/close → disconnect SSE, exit cleanly (same pattern as Telegram plugin)
- SIGTERM/SIGINT → graceful shutdown

### Inbound (SSE → MCP notification)

When SSE delivers a message event:

```typescript
mcp.notification({
  method: 'notifications/claude/channel',
  params: {
    content: message.body,
    meta: {
      source: 'hiboss',
      message_id: message.id,
      direction: message.direction,
      from: message.agent_name || message.agent_id,
      priority: message.priority,
      type: message.type,
      reply_to: message.reply_to,
      session_id: message.session_id,
      // spread any metadata fields
      ...parsedMetadata,
    },
  },
});
```

### MCP Tools

5 tools, wrapping existing REST endpoints:

#### 1. `send`
Send a message to boss or peer agent.
```
POST /api/messages
```
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| body | string | yes | Message text |
| to | string | no | Target agent/session (peer messaging) |
| priority | string | no | critical/high/normal/low |
| options | string | no | Comma-separated options for ask-style |
| session_id | string | no | Auto-set from config |

#### 2. `ask`
Send a blocking message with options and wait for reply.
Combines POST /api/messages (mode=blocking) + POST /api/messages/:id/poll.
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| body | string | yes | Question text |
| options | string | no | Comma-separated options |
| timeout | number | no | Seconds to wait (default 300) |

#### 3. `reply`
Reply to a specific message.
```
POST /api/messages/:id/reply
```
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| message_id | string | yes | ID of message to reply to |
| body | string | yes | Reply text |

#### 4. `react`
Add an emoji reaction to a message.
```
POST /api/messages/:id/reactions
```
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| message_id | string | yes | Message ID |
| emoji | string | yes | Emoji to react with |

#### 5. `inbox`
List recent messages (primarily for checking unread).
```
GET /api/messages?unread=true
```
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| unread | boolean | no | Only unread messages (default true) |
| limit | number | no | Max messages (default 10) |

### MCP Instructions

```
Messages from your boss arrive as <channel source="hiboss" message_id="..." from="..." priority="...">.
Reply using the reply tool with the message_id. Use send for new messages to boss.
Use ask (with options) when you need boss input — it blocks until reply or timeout.
For peer agents, use send with the 'to' parameter.
```

### SSE Reconnection

- Auto-reconnect on disconnect with exponential backoff (1s → 2s → 4s → max 30s)
- Reset backoff on successful connection
- Log reconnection attempts to stderr

### Session Management

- On startup, register session via `POST /api/sessions` (or reuse existing)
- Include session_id in all outbound messages
- Session label from env or auto-generated

## Plugin Manifest

`.claude-plugin/plugin.json`:
```json
{
  "name": "hiboss",
  "description": "Boss communication channel — send messages, ask questions, receive real-time replies via hiboss server",
  "version": "1.3.0",
  "source": "hiboss"
}
```

`.mcp.json`:
```json
{
  "mcpServers": {
    "hiboss": {
      "command": "bun",
      "args": ["start"],
      "cwd": "${pluginRoot}"
    }
  }
}
```

## Configure Skill

`/hiboss:configure [server_url] [api_key]`

- No args: show current config status (server URL, key masked, connection state)
- With args: save to `~/.config/hiboss/config.json`
- Reads same config file as CLI — shared config

## Migration Path

1. **Phase 1**: Ship MCP server as standalone (install via plugin)
2. **Phase 2**: CLI `setup hooks` gains `--plugin` flag that installs the MCP channel instead of hooks
3. **Phase 3**: Hooks become fallback — plugin is the default
4. CLI remains for non-CC environments (other AI agents, scripts, CI)

## Dependencies

- `@modelcontextprotocol/sdk` ^1.0.0
- `eventsource` (or native fetch + SSE parsing) for SSE client

No grammy, no bot — the MCP server is a pure bridge to hiboss's HTTP API.

## Open Questions

1. Should the MCP server also handle `hiboss hook` events (PostToolUse drain), or fully replace hooks?
   → Recommendation: Fully replace. SSE provides real-time delivery, hooks are redundant.

2. Should we keep the Rust CLI's SSE client (`sse.rs`) as-is?
   → Yes. CLI and MCP server are independent entry points to the same server API.

3. How to handle `ask --timeout` blocking in MCP? The tool call blocks until reply.
   → MCP tool calls can take arbitrary time. Use poll endpoint server-side.
