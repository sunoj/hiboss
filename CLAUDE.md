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

### Cross-Session Coordination
When peer sessions are active on the same project:
- **Broadcast before starting**: `hiboss send --broadcast "Working on X"` — prevents conflicts
- **Broadcast on completion**: `hiboss send --broadcast "Done with X, files Y changed"` — keeps peers informed
- **Direct message**: `hiboss send --to <label> "message"` — for targeted coordination
- **Check peer status**: `hiboss ss` — see what other sessions are doing

### After Receiving Boss Reply (CRITICAL)
- When `hiboss ask` returns a boss reply, **always acknowledge via `hiboss send "your ack"`** — never just print text in conversation.
- The reply output includes a reminder: `[reply <id>] Acknowledge via: hiboss send "..." or hiboss react <id> 👍`

### Before Finishing (CRITICAL)
1. Summarize what you accomplished
2. Propose 2-4 concrete next directions
3. Send via repeatable `hiboss ask --option` flags (**never** `hiboss send` for completion messages):
   ```bash
   hiboss ask --option "Short A" --option "Short B" --option "Short C" "Summary.\n\nNext options:\n1. Short A — details\n2. Short B — details\n3. Short C — details" --timeout 300
   ```
   Never use the removed plural `--options` / `--actions` flags or comma-join choices.
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
- `ios/` — native iOS boss client (SwiftUI, XcodeGen project). Inbox, Live Activity (Dynamic Island decision card + App Intents), APNs push. Bundle `ai.hiboss.ios` + widget extension. `xcodegen generate` builds the Xcode project
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
