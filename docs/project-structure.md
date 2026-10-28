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
- `web/` — web console for bosses (SvelteKit static build); see `web/README.md`
- `panel-runtime/` — shared live-panel definition schema, validation and fixtures (npm workspace)
- `site/` — static public website

## Shared implementations

- `cli/src/client/mod.rs` defines the private `client_endpoints!` declarations for standard JSON
  requests and empty-response deletes. Signing, long polling, uploads and encoded URL segments keep
  their endpoint-specific implementations. `cli/src/commands/message_text.rs` shares optional message
  metadata construction.
- `web/src/lib/stores/load-state.svelte.ts` owns the loading and error state for standard authenticated
  page loads. Pages retain their request bodies, data updates and operation-specific guards.
  `web/src/lib/api/types.ts` supplies the common API error text. Shared scoped CSS lives in
  `web/src/lib/design/`.
- `HibossKit/Sources/HibossKit/BoxMedia/` shares native Box thumbnail caches, backfill sessions and
  concurrency limits. Platform-specific cache paths and file-protection options remain explicit.
- `server/migrations/` defines the SQLite schema. `server/schema.template.sql` groups documented
  objects, and `server/scripts/check-schema.sh` renders their complete definitions from the migrations.
- `site/partials/` contains the English and Chinese navigation fragments. `site/render.py` expands
  them into standalone public HTML; templates and build scripts are excluded from the output.
