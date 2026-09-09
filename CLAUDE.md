# hiboss — AI Agent ↔ Boss Communication Tool

CLI tool for AI agents to send messages to their boss (human or AI) and receive replies. Supports Discord and Telegram channels.

## Agent Instructions

Run `hiboss setup hooks` to install Claude Code hooks. This configures SessionStart (unread messages + daemon start), PostToolUse (local message drain + async bg-check), and Stop (session cleanup).

### Session Start
1. Handle unread messages first — reply with `hiboss reply <id> "response"` before other work.
2. Report your plan: `hiboss send "Starting work on X. Plan: 1) ... 2) ... 3) ..."`
3. If peer sessions are active, broadcast your work plan: `hiboss send --broadcast "Working on X in files Y"`

### During Work
- `hiboss send "message"` for progress updates on major milestones.
- `hiboss send --priority high "message"` for blockers or decisions needed urgently.

### Progress Feed
`hiboss progress` posts to the project's timeline, which the boss browses in the iOS 进展
tab. It is a **low-noise** surface: a post sends no notification and never enters the inbox.

- `hiboss progress post "<what shipped>" [--image <path>]… [--video <path>]… [--tag <t>]…`
- `hiboss progress list [--project <name>] [--limit <n>] [--json]`, `hiboss progress rm <id>`

Use it for something worth *showing* — a shipped feature, a screenshot, a short clip — not
for routine status, which belongs in `hiboss send`. Repeat the singular flags; there is no
plural form. Up to 4 media items, images ≤ 10 MB and video ≤ 50 MB. A `.gif` is converted to
a muted looping MP4 when `ffmpeg` is present (iOS shows a still frame otherwise), and
`ffprobe`/`sips` fill in dimensions when available — all of them degrade with a warning
rather than failing the post.

### Live Panels

`hiboss panel` gives a long-running task a **persistent visual surface** on the boss's
wall — a chart that keeps updating, a test run with per-test status, a benchmark sweep.
It is not a message and not a timeline post: use `hiboss send` for something the boss
should read, `hiboss progress` for something worth showing once, and a panel for
something worth **watching** while the task runs.

Publication may set `lifecycle.ttlSeconds` from 60 to 604800 seconds; it defaults to
3600. Publication stores `expiresAt`; observations and lease renewal do not move it.
A long-running producer must renew deliberately with `hiboss panel renew <id> [--ttl
<seconds>]`. Streaming data alone does not keep a card alive. A lapsed running or
paused card leaves the wall, not the task: task state is untouched, and renewal brings
it back. A boss pin keeps it visible. `hiboss panel show <id>` prints the stored expiry.

```bash
hiboss panel validate <file>            # local pre-check; prints the JSON Pointer path on failure
hiboss panel publish <file> [--run-id]  # prints panelId; stable retry key includes the run
hiboss panel update <panel-id> [JSON]   # one merge/ack/release; stdin or --file also work
hiboss panel stream <panel-id>          # NDJSON on stdin; releases after final ack
hiboss panel renew <id> [--ttl <seconds>] # explicitly renew visibility; prints expiry
hiboss panel complete|fail|cancel <id>  # finish with live CAS fields and retry-safe key
hiboss panel pause|resume <id>          # lifecycle shortcuts with live CAS fields
hiboss panel doctor                     # auth, v2, session/boss, ticket, subscribe
hiboss panel list [--json] [--cursor]
hiboss panel show <id> [--json]
hiboss panel state <id>
```

Start from a reference in `panel-runtime/fixtures/examples/` — download progress, an
end-to-end suite, a benchmark sweep, a continuous monitor, an intake questionnaire.
They are **reference points, not templates**: the catalog is the space you compose in,
and a panel resembling none of them is a success. `docs/live-panels/authoring-examples.md`
says where the real limits are.

Two rules are contract, not style, because both mislead the boss when broken:

- **A gap in a series is an explicit `null`, never a zero.** Zero draws a cliff to the
  baseline and reads as an outage that did not happen.
- **No completion percentage without a real denominator.** A continuous task shows stage,
  duration, observed values and freshness instead. `service-monitor.json` demonstrates
  that this still looks finished — the instinct to invent a percentage because a progress
  bar looks tidy is the thing to resist.

`stream` prints `ack <sequence>` per accepted update and **exits non-zero if the stream
ends with unacknowledged work** — an update that was sent but not acknowledged has not
landed. If another producer takes the lease, it stops and says so rather than fighting.

Not yet available: iOS shows no panels, and structured questionnaires with typed answers
are designed but unbuilt. Panels today are display surfaces plus a form that reports what
it would submit.

### Cross-Session Coordination
When peer sessions are active on the same project:
- **Broadcast before starting**: `hiboss send --broadcast "Working on X"` — prevents conflicts
- **Broadcast on completion**: `hiboss send --broadcast "Done with X, files Y changed"` — keeps peers informed
- **Direct message**: `hiboss send --to <target> "message"` — for targeted coordination
- **Check peer status**: `hiboss ss` — see what other sessions are doing

**Addressing (`--to`)** resolves in this order: agent name or id prefix, then session label or
id prefix. The project name alone works — `--to smart-router` resolves to the one live session
whose label starts with it. An exact label (`smart-router/main`) always wins outright, even when
several sessions share it; the most recently active non-self one is picked. A 409 means a genuine
choice between two or more *live* sessions, and a 404 lists reachable targets with their idle
times — both errors name valid targets, so correct the command from the error rather than
guessing. Idle sessions are still deliverable (you get a staleness warning); they read the
message when they resume.

**Reading the result is part of sending.** `--to` prints `sent -> <resolved-target> (<id>)
id=<msg-id>` on stdout, naming the target the server actually resolved, not the string you typed.
`--broadcast` prints one line per peer and **exits non-zero if any peer failed**. Never report
that you coordinated with a peer on the strength of the command returning — a send whose output
you did not read is not a sent message. Add `--wait-ack` when you need delivery confirmed before
you report anything. If a `UNACKED WARNING` appears, earlier peer messages were never picked up:
check them with `hiboss status <id>` before claiming coordination happened.

### After Receiving Boss Reply (CRITICAL)
- When `hiboss ask` returns a boss reply, **always acknowledge via `hiboss send "your ack"`** — never just print text in conversation.
- The reply output includes a reminder: `[reply <id>] Acknowledge via: hiboss send "..." or hiboss react <id> 👍`
- **A returned value that equals your `--default` is not proof the boss chose it.** On timeout the
  server auto-selects the default and returns it looking exactly like a real answer. The server
  records which it was (the auto-generated reply carries `auto_default: true` in its metadata) but
  no CLI surface shows it yet. Before acting on such a value irreversibly — a deploy, a migration,
  anything outward-facing — re-ask without `--default`, or read the reply's metadata directly.

### Before Finishing (CRITICAL)
1. Summarize what you accomplished
2. Propose 2-4 concrete next directions
3. Send via repeatable `hiboss ask --option` flags (**never** `hiboss send` for completion messages):
   ```bash
   hiboss ask --option "Short A" --option "Short B" --option "Short C" "Summary.\n\nNext options:\n1. Short A — details\n2. Short B — details\n3. Short C — details" --timeout 300
   ```
   Never use the removed plural `--options` / `--actions` flags or comma-join choices.
   Optionally add `--default <LABEL>` (equal to one of your option/action labels) to mark a fallback: the boss sees it flagged, and on timeout with no reply it is auto-selected on the server and returned to you, so you can proceed safely instead of stalling.
4. Run it using your tool call's own `run_in_background: true` parameter (NOT shell `&`/`nohup`/`disown` — those detach the process from harness tracking, so a reply can never be delivered back to you) and **wait for the boss's reply**
5. Only stop if: boss says stop, OR ask times out

## Architecture

```
Claude Code ←stdio/MCP→ hiboss-mcp (local Bun, mcp/)
                              ↕ SSE + REST
hiboss CLI (Rust/clap) ←HTTP→ hiboss-server (Cloudflare Worker + Hono, server/)
                                    ↕ D1 (messages)
                                    ↕ Channel Adapters (Discord, Telegram)
                                    ↕ Boss (human or AI)
```

## Project Structure

- `cli/` — Rust CLI binary (clap for args, reqwest for HTTP, serde for JSON)
- `server/` — Cloudflare Worker (Hono framework, D1 database)
- `mcp/` — Claude Code channel plugin (MCP server, Bun, real-time SSE bridge)
- `HibossKit/` — shared Swift package (domain models, boss API client, option flow, keychain) used by both native clients
- `macos/` — native macOS boss client "HiBoss Island" (SwiftUI + AppKit, menu-bar app, Dynamic-Island-style option picker); depends on HibossKit. `History/` and `Settings/` hold the two window surfaces. **Read `docs/macos-design-v2.md` before changing this UI** — it is a native-first contract (system controls, semantic colours, no hex in views, no `.system(size:)`), written after a palette-driven first attempt shipped something that read as a web page in a window
- `ios/` — native iOS boss client (SwiftUI, XcodeGen project). Inbox, Live Activity (Dynamic Island decision card + App Intents), APNs push. Bundle `ai.hiboss.app` + widget extension. `xcodegen generate` builds the Xcode project
- `terminal/` — ESP32 hardware terminal (ESP-IDF + LVGL round LCD), separate device firmware
- `mcp-server/` — Removed (was v0.13 MCP server, replaced by `mcp/`)

## Code Conventions

### Server (TypeScript)
- TypeScript strict mode, ESM modules (type: "module")
- Hono framework, use `c.json()` for responses
- No `any` types at module boundaries

### CLI (Rust)
- clap derive API for argument parsing
- reqwest for HTTP (rustls-tls, json feature), serde for serialization
- Config stored in `~/.config/hiboss/config.json` (dirs crate)
- colored crate for ANSI output
- Error handling: anyhow-style, friendly messages to stderr, data to stdout

### Both
- Files ≤ 300 lines, functions ≤ 50 lines

## Reference

Detailed docs moved to `.aid/knowledge/`:
- **API Reference** — all endpoints, request/response formats
- **CLI Reference** — complete command reference with examples
- **Message Delivery** — delivery architecture, channel resolution, hooks
- **Roadmap History** — version history v0.1 through v1.4
- **Architecture Decisions** — agent-as-boss, autonomy, multi-agent design

<!-- aid:start -->
## aid orchestration

This project uses [aid](https://github.com/agent-tools-org/ai-dispatch) for AI task orchestration.

- **Project**: hiboss
- **Profile**: production
- **Language**: rust, typescript
- **Budget**: $50/day
- **Verify**: `cd cli && cargo check && cd ../server && npm test`

### Rules
- All new functions must have at least one test
- No unwrap() in Rust production code
- Files ≤ 300 lines, functions ≤ 50 lines
- Code changes require review before merge

### Usage
- Dispatch work: `aid run <agent> "<prompt>" --dir .`
- Review output: `aid show <id> --diff`
- Batch dispatch: `aid batch <file> --parallel`
- Project config: `.aid/project.toml`
<!-- aid:end -->
