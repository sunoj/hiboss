# Message Delivery Architecture

## Delivery Layers

Messages reach the agent through four layers:

| Layer | Trigger | Scope | Latency |
|-------|---------|-------|---------|
| **SSE Daemon** | Background process, reads local file | All messages (boss + peer) | ~2s SSE + next tool call |
| **PostToolUse hook** | Every tool call | Local file drain (~4ms); spawns bg-check if TTL expired | ~4ms |
| **BgCheck** | Spawned by PostToolUse when TTL expired | Heartbeat + inbox count via HTTP (detached process) | Async |
| **MCP SSE push** | Real-time SSE background listener | All messages (terminal-visible) | Real-time* |
| **SessionStart hook** | New session start | All unread + starts daemon | Session gap |

*MCP `notifications/message` is displayed in terminal but NOT injected into agent context by Claude Code.

**With daemon** (default): SSE daemon writes messages to local file → PostToolUse drains file on every tool call → near-instant delivery into agent context.

**Without daemon** (fallback): PostToolUse spawns a detached `bg-check` process when TTL expires — 30s for peer messages, 5min for boss urgent. The bg-check runs HTTP calls asynchronously without blocking the hook. Results are written to a local urgent file, picked up on the next PostToolUse call.

## Key Design Decisions

- MCP `notifications/message` is filtered by Claude Code — displayed in terminal for human but NOT injected into agent context. Server→client push via MCP is not viable for agent notification.
- All boss→agent notification must go through hooks (stdout injection as `<system-reminder>`) or tool call responses.
- Hook stdout output enters agent context; MCP notifications do not.
- hiboss core users are Claude Code main agents orchestrating via aid CLI.
- Sub-agents (codex, gemini, etc.) report to main agent via aid, not hiboss.

## Channel Resolution Order

When a message is sent, the channel is resolved with this precedence:

1. **CLI `--channel` flag** — explicit override, always wins
2. **Server `channel_routing`** — per-priority routing (e.g. `normal=discord, high=telegram`), used when no `--channel` is given
3. **Server channel config fallback** — picks the most recently configured channel if no routing matches

The CLI no longer sends `config.channel` on every request (as of v0.10.1) — it only sends a channel when `--channel` is explicitly used.

## Multi-Channel Delivery

Critical/high priority messages are delivered to ALL configured channels simultaneously. Normal/low priority uses single channel per resolution order above.

## Reactions

Agents set reaction emojis via `hiboss react <id> <emoji>` (works on both Discord and Telegram). Boss reactions are captured via webhooks. Conventions:
- 👀 → message seen
- 🔨 → working on it
- ✅ → done/replied

## Boss Option Fan-Out

`GET /api/boss/stream?options=true` is intentionally different from a work queue.
Each connected macOS or API client receives the same active option messages. The
server tracks delivery independently inside each SSE connection and does not mark
an option as owned by a client.

When a client replies with an exact option value, an atomic status update chooses
the first winner. Other clients receive a `resolved` SSE event and withdraw their
local UI. The same resolution path removes Discord buttons and Telegram inline
keyboards, regardless of whether the winning selection came from the API, Discord,
or Telegram. Expiry produces the same withdrawal behavior with status `expired`.
