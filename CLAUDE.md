# hiboss — AI Agent ↔ Boss Communication Tool

CLI tool for AI agents to send messages to their boss (human or AI) and receive replies. Supports Discord and Telegram channels.

## Agent Instructions

Run `hiboss setup hooks` to install Claude Code hooks. This configures SessionStart (unread messages), PostToolUse (urgent message check), and Stop (session cleanup).

### Session Start
1. Handle unread messages first — reply with `hiboss reply <id> "response"` before other work.
2. Report your plan: `hiboss send "Starting work on X. Plan: 1) ... 2) ... 3) ..."`

### During Work
- `hiboss send "message"` for progress updates on major milestones.
- `hiboss send --priority high "message"` for blockers or decisions needed urgently.

### Before Finishing (CRITICAL)
1. Summarize what you accomplished
2. Propose 2-4 concrete next directions
3. Send via `hiboss ask --options` (**never** `hiboss send` for completion messages):
   ```bash
   hiboss ask --options "Short A,Short B,Short C" "Summary.\n\nNext options:\n1. Short A — details\n2. Short B — details\n3. Short C — details" --timeout 300
   ```
4. Run with `run_in_background: true` and **wait for the boss's reply**
5. Only stop if: boss says stop, OR ask times out

## Architecture

```
hiboss CLI (Rust/clap) ←HTTP→ hiboss-server (Cloudflare Worker + Hono)
                                    ↕ D1 (messages)
                                    ↕ Channel Adapters (Discord, Telegram)
                                    ↕ Boss (human or AI)
```

## Project Structure

- `cli/` — Rust CLI binary (clap for args, reqwest for HTTP, serde for JSON)
- `server/` — Cloudflare Worker (Hono framework, D1 database)

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
- **Roadmap History** — version history v0.1 through v1.0
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
