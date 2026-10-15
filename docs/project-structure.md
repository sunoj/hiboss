# Project architecture and structure

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
- `HibossKit/` — shared Swift package (domain models, boss API client, option flow, keychain) used by both
  native clients
- `macos/` — native macOS boss client "HiBoss Island" (SwiftUI + AppKit, menu-bar app, Dynamic-Island-style
  option picker); depends on HibossKit. `History/` and `Settings/` hold the two window surfaces. **Read
  `docs/macos-design-v2.md` and `docs/ui-stability.md` before changing this UI** — it is a native-first
  contract (system controls, semantic colours, no hex in views, no `.system(size:)`), written after a
  palette-driven first attempt shipped something that read as a web page in a window
- `ios/` — native iOS boss client (SwiftUI, XcodeGen project). Four tabs: Home, Activity (sessions and
  messages), Progress, Settings. Live Activity (Dynamic Island decision card + App Intents), APNs push. Bundle
  `ai.hiboss.app` + widget extension. `xcodegen generate` builds the Xcode project. **Before changing iOS UI,
  read** `docs/ios-design-contract.md` (native-first rules), `docs/ui-stability.md` (no layout jumps on
  refresh), `docs/ios-design-v3.md` (navigation and Home), `docs/ios-intermediate-states.md` (loading, waiting
  and escalation rules) and `docs/ios-settings-v2.md` (Settings hierarchy)
- Session dots (unread / needs-you / working) and every recorded-time label follow
  `docs/session-unread-and-timestamps.md` on both native clients
- `terminal/` — ESP32 hardware terminal (ESP-IDF + LVGL round LCD), separate device firmware
- `mcp-server/` — Removed (was v0.13 MCP server, replaced by `mcp/`)
