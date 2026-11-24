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
| **Session wake** | Daemon gets a boss message addressed to an idle Claude Code session | One fixed notice per idle period | ~2s |

*MCP `notifications/message` is displayed in terminal but NOT injected into agent context by Claude Code.

**With daemon** (default): SSE daemon writes messages to local file → PostToolUse drains file on every tool call → near-instant delivery into agent context. An idle Claude Code session is woken through its messaging socket (see below).

**Without daemon** (fallback): PostToolUse spawns a detached `bg-check` process when TTL expires — 30s for peer messages, 5min for boss urgent. The bg-check runs HTTP calls asynchronously without blocking the hook. Results are written to a local urgent file, picked up on the next PostToolUse call.

## Waking an idle session

Claude Code exports `CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN` to a
session's hooks and commands. A line pair written to that socket (`{"type":"auth","token":…}`
then `{"type":"user","message":{"role":"user","content":…}}`) starts a turn in an idle session.
Mid-turn it is added to the running turn. Claude Code labels it as a message from another
session, not as user input. aid uses the same socket to report a settled task.

- **Stop keeps the daemon when the session has a socket.** Stop fires at every turn
  boundary, so it marks the session `idle` instead. A session without a socket (Codex, an
  aid-dispatched agent, older Claude Code) cannot be woken, so Stop still stops its daemon.
- **What wakes it.** Only a `boss_to_agent` message whose `target_session_id` is exactly this
  session: a reply to an ask carries the asking session, so an untargeted boss message or a
  peer message only goes to the spool. The first such message in an idle period consumes the
  `idle` marker; PostToolUse clears it, and the next Stop sets it again.
- **What the notice says.** Fixed fields only: the reply id, the ask id, and the command
  that reads it (`hiboss status <ask>`). The body still reaches the agent through the
  labelled PostToolUse spool. A server auto-default is named as such, never as a decision.
- **Stop checks the spool.** A boss message spooled after the turn's last tool call was never
  shown, so Stop pushes its notice immediately.
- **Socket lifecycle.** The daemon records the socket path (never the token) in
  `daemon.socket`. SessionStart replaces a daemon that holds another process's socket, as
  after a resume. The daemon exits when connecting to the socket returns `ENOENT` or
  `ECONNREFUSED`, because the Claude Code process is gone.
- **Reconnects.** The server ends each stream after five minutes, and a new stream carries
  only messages created after it opens. A clean end therefore reconnects after 250 ms. Only
  a failed connect backs off from 5 s up to 60 s.
- **Cost.** An idle session now keeps its stream open, and the stream polls D1 every 2 s:
  about 43k polls a day for each open Claude Code session, idle or not.

## Key Design Decisions

- MCP `notifications/message` is filtered by Claude Code — displayed in terminal for human but NOT injected into agent context. Server→client push via MCP is not viable for agent notification.
- All boss→agent notification must go through hooks (stdout injection as `<system-reminder>`) or tool call responses.
- SessionStart plain stdout enters agent context. PostToolUse plain stdout only enters the
  transcript; model-visible text must be JSON in `hookSpecificOutput.additionalContext` with
  `hookSpecificOutput.hookEventName` set to `PostToolUse`. An idle PostToolUse emits nothing.
  The Codex adapter passes PostToolUse JSON through unchanged; MCP notifications do not enter context.
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

Agents set reaction emojis via `hiboss react <id> <emoji>`: stored on every channel and forwarded
to Discord or Telegram when the message has a copy there. Boss reactions come from the boss API,
the Discord gateway and the Telegram webhook; each source adds or removes only its own actor's
entries. The macOS and iOS clients show them as emoji chips. Conventions:
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
