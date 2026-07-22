# HiBoss System Whitepaper — Business Logic & Security Audit

Audited at commit `05a8dd0` (2026-07-22). Scope: server (Cloudflare Worker), CLI + hooks + daemon,
MCP plugin, HibossKit, macOS, iOS, web console, ESP32 terminal. Method: four parallel read-only
code audits (identity/authz, sessions/lifecycle, agent-side, boss-side clients), synthesized here.
All claims carry `file:line` evidence from the audited tree.

---

## 1. Executive summary

HiBoss is an agent ↔ boss communication system: AI coding agents send progress and blocking
questions ("asks") through a Cloudflare Worker; a human (or agent) boss answers via Discord,
Telegram, a macOS menu-bar app, an iOS app, or a web console. The core value loop is the
**blocking ask with options**: the agent pauses, the boss picks an option (or the marked default
auto-resolves on timeout), and the agent proceeds.

State of the system:

- The **core loop is sound**: atomic option claiming, idempotent channel callbacks, Ed25519-verified
  Discord interactions, admin-gated key minting on every channel, and boss-write scoping are all
  correctly implemented.
- The **trust model is flat**: it is built for one operator's fleet. Any agent key can read the
  global audit log, message any other agent, and reconfigure the shared Discord gateway. This is
  acceptable single-tenant, but must be stated (and eventually fixed) before open-sourcing.
- The **top risks** are secret handling (live boss token in the terminal working tree, plaintext
  keys in config files and localStorage), a local `/tmp` prompt-injection path into the agent's
  context, unauthenticated attachment downloads, and unbounded data growth (no retention anywhere).
- The **client fleet is uneven by design**: macOS/iOS are answer-focused; the web console is the
  only admin surface; the terminal is a hardware scaffold with no firmware yet.

Findings: 1 critical, 7 high, 15 medium, ~18 low/info — consolidated in §8.

---

## 2. Architecture overview

```
Claude Code ←stdio→ mcp/ (Bun MCP plugin) ──SSE + REST──┐
Claude Code ←hooks→ cli/ (Rust) ── REST ──────────────── hiboss-server (CF Worker, Hono)
        └─ daemon (SSE → /tmp spool)                      ├─ D1 (messages, sessions, keys, bosses…)
                                                          ├─ R2 (attachments)
boss surfaces:                                            ├─ Durable Object (Discord gateway WS)
  Discord / Telegram (webhooks + buttons)                 └─ cron */5 (option expiry, delivery queue)
  macOS HiBoss Island · iOS app (+APNs/Live Activity)
  web console (Cloudflare Pages SPA) · ESP32 terminal (scaffold)
```

- One Worker, one D1 database, cron every 5 minutes (`wrangler.toml:28`).
- Outbound delivery: Discord (webhook or bot token) and Telegram (with per-session forum topics /
  Discord threads). Inbound: three webhook endpoints + an optional Discord Gateway Durable Object.
- Agent-side real-time: SSE (`GET /api/messages/stream`) consumed by the daemon and the MCP plugin.
- Boss-side real-time: SSE (`GET /api/boss/stream`) consumed by HibossKit (macOS/iOS); the web
  console loads once per page (no live stream — see F-M12).

---

## 3. Identity model

Three principal types, all authenticated by unsalted SHA-256 hash lookup of a bearer token
(`auth.ts:15-20`).

| Principal | Table | Token format | Created by |
|---|---|---|---|
| Agent | `api_keys` (`schema.sql:5-18`) | `hb_` + 32 hex (128-bit) | bootstrap, join flow, boss approval, admin-agent `POST /api/keys` |
| Boss | `bosses` (`schema.sql:116-131`) | `hb_boss_` + 48 hex (192-bit) | admin boss `POST /api/bosses`, token minted via `POST /api/bosses/:id/token` |
| Session | `sessions` (`schema.sql:171-188`) | client-supplied UUID id | agent `POST /api/sessions` |

Provisioning flows:

- **Bootstrap** (`bootstrap.ts:12-28`): creates `default-agent` only while `api_keys` is empty.
  Open to the network if `BOOTSTRAP_SECRET` is unset (`bootstrap.ts:41-44`) — see F-M4.
- **Join** (`join.ts:31-77`): unauthenticated `POST /api/join` creates a pending `join_request`;
  a boss approves it (HTTP `boss-api.ts:390-414`, Discord button, or Telegram action — all
  admin-gated). The first join on an empty database auto-approves itself. The cleartext key is
  stored in `join_requests.api_key` until the requester polls it (`join.ts:48-50,99-102`).
- **Agent-as-boss**: `bosses.agent_id` links an agent to a boss identity; that agent then drives
  `/api/boss/inbox` with the linked boss's role (`boss-inbox.ts:20-47`). Linking is admin-only
  (`bosses.ts:105-109`), so escalation requires an existing admin.
- **Boss roles**: `admin | manager | viewer` (`schema.sql:120`). Admin sees all agents;
  manager/viewer see only rows in `boss_agent_access` (`boss-api.ts:51-61`). Viewer is read-only
  (enforced per-route, not by middleware).
- `api_keys.role` for agents: self-service config allows only `orchestrator|worker|reviewer`
  (`agents.ts:88-97`); the `admin` agent role (needed for `POST /api/keys`) can only be set
  directly in the database — effectively dormant.

Session identity on the agent side is derived locally: FNV-1a hash of the project directory keys a
`/tmp/hiboss-session-<hash>` file holding a UUIDv4 (`cli/src/session.rs:39-54`); the label is
`repo/branch` from git (`hook.rs:79-83`). The MCP plugin mints its **own** unrelated session UUID
(`mcp/server.ts:238-244`) — the same Claude session can appear as two hiboss sessions (F-M9).

---

## 4. Authentication & authorization

Middleware (`server/src/middleware/auth.ts`): `apiAuth` (agents), `bossAuth` (bosses), `dualAuth`
(sessions router only). Context getters fail safe (`getBossRole` defaults to `viewer`,
`auth.ts:38-40`). No rate limiting or lockout on authentication anywhere; token entropy is the only
brute-force defense.

Permission matrix (✓ allowed, ✗ denied, — n/a):

| Operation | Unauth | Agent | Boss viewer | Boss manager | Boss admin |
|---|---|---|---|---|---|
| `POST /api/join`, `GET /api/join/status` | ✓ | ✓ | — | — | — |
| `GET /api/attachments/:key` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `POST /api/messages` (incl. `--to` any agent) | ✗ | ✓ | — | — | — |
| `GET /api/agents` (list all), `GET /api/audit` (global) | ✗ | ✓ | — | — | — |
| Discord gateway connect/disconnect | ✗ | ✓ | — | — | — |
| `GET /api/boss/messages` | ✗ | — | ✓ scoped | ✓ scoped | ✓ all |
| Reply / react / forward / boss writes | ✗ | — | ✗ | ✓ | ✓ |
| Mark message read, edit own preferences | ✗ | — | ✓ (no viewer guard) | ✓ | ✓ |
| Boss CRUD, token mint, join approval | ✗ | — | ✗ | ✗ | ✓ |
| `GET /api/bosses` (all bosses + contact ids) | ✗ | — | ✓ | ✓ | ✓ |
| Agent-as-boss inbox | ✗ | ✓ if linked | ✗ | ✓ | ✓ |

Unauthenticated surface and its defenses:

- **Discord interactions**: Ed25519 signature + 300 s timestamp window
  (`discord-interactions.ts:21-39`) — the strongest inbound path.
- **Discord/Telegram content webhooks**: static shared-secret headers, fail closed when unset, but
  compared with non-constant-time `!==` (`webhooks.ts:33,83`).
- **Sender resolution**: if zero bosses exist, `resolveBossForChannel` treats any channel member as
  authorized (`webhook-helpers.ts:88`) — a bootstrap convenience that becomes a hole if bosses are
  never registered.
- **Attachments**: capability-URL only, no auth, `Cache-Control: public, immutable`
  (`attachments.ts:54-69`). Required so Discord/Telegram can fetch, but URLs leak with messages.
- **CORS**: allowlist of the Pages console + localhost (`index.ts:50-64`); native clients send no
  Origin and are unaffected.

Verified-correct controls worth preserving: atomic option claim (`boss-option-reply.ts:24-44`),
channel callbacks restricted to offered options (no free-text injection from channel viewers),
boss-write target scoping (`boss-writes.ts:54,85,130`), secrets stripped from boss channel reads
(`boss-writes.ts:277-285`), session upsert bound to the owning agent (`sessions.ts:49-58`),
admin-gated key minting on every approval channel.

---

## 5. Sessions & context

- **Registration**: agent-owned upsert with cross-agent collision → 409 (`sessions.ts:32-62`).
  Heartbeat via `PATCH` bumps `last_seen_at` and optionally status (`sessions.ts:81-108`).
- **Status**: `working | blocked | waiting | idle | completed` (`schema.sql:177`). Auto-inference on
  agent sends: blocking or high/critical priority → `waiting`, else `working`
  (`message-helpers.ts:175-200`). `blocked`/`idle` are reachable only via explicit `hiboss ss set`
  — dashboards should not expect them organically.
- **Visibility**: an agent lists only its own key's sessions; bosses list all with `?all=true`
  (`sessions.ts:65-78`). Sessions unseen for 15 min are filtered out (not deleted).
- **Context per session**: Discord thread and Telegram forum topic are auto-created per session and
  stored on the row (`message-options.ts:244-298`, `session-channels.ts:23-52`); inbound Telegram
  messages route back to the session by `(chat_id, topic_id)`.
- **Peer coordination**: SessionStart hook lists active peers and auto-broadcasts a `session_start`
  agent-to-agent message; `hiboss send --broadcast` fans out client-side to each peer session.
- **Lifecycle gap**: `DELETE /api/sessions/:id` is the only hard delete in the system; a crashed CLI
  leaves a `working`/`waiting` row forever (F-H7). The Stop hook best-effort marks `completed`.

Agent-side session context lives in predictable world-writable `/tmp` files (session id, asked/
replied markers, daemon spool, urgent flags — `session.rs`), wiped at the next SessionStart. Two
concurrent Claude sessions in the same repo share all of them (F-M10).

---

## 6. Message lifecycle

**Data model** (`schema.sql:21-50`): status `sent → delivered → read → replied | expired`;
direction `agent_to_boss | boss_to_agent | agent_to_agent` (broadcast = N individual rows);
`mode async|blocking`; priority `critical|high|normal|low`; threading via `reply_to`; idempotency
via unique `(agent_id, idempotency_key)`. Status transitions are validated only on the agent PATCH
route (`messages.ts:48-52`); channel callbacks, cron, and streams write status directly.

**Metadata contract** (JSON text column): `options` (≤5), `actions` (label → shell command string),
`default_option`, `options_resolved` + `selected_option`, `options_expired`, `auto_default: true`
(marks a server-generated default reply), channel message ids, `file_url`, `reactions`,
`delivery_error`. Agent-supplied metadata is not filtered, so reserved keys like `boss_name` can be
spoofed by the sender (F-M5).

**Ask / option / default flow** (the core loop):

1. Agent: `hiboss ask --option A --option B [--default A] [--timeout N]` → blocking message with
   `metadata.options` (+ validated `default_option`, `ask_support.rs:40-56`); server sets
   `expires_at`; a new ask auto-expires older open asks in the same session
   (`message-options.ts:189-210`).
2. Delivery renders Telegram inline keyboards / Discord buttons; `callback_data` =
   12-char message-id prefix + option label (`message-options.ts:40-42`).
3. Any resolution path — Discord button, Telegram button, boss API, macOS/iOS/web — funnels into
   the atomic claim `UPDATE … WHERE status IN (sent,delivered,read) AND expires_at > now RETURNING`
   (`boss-option-reply.ts:24-44`). First writer wins; losers get "already selected". Channel
   callbacks may only pick offered options; free text is boss-API only.
4. On resolve: keyboards withdrawn on both channels; agent notified via long-poll return, SSE,
   and optional `callback_url` POST.
5. On expiry (cron, ≤50 per 5-min tick): with a valid `default_option`, the server atomically claims
   the message and inserts a `boss_to_agent` reply flagged `auto_default` (`message-options.ts:44-105`)
   — the agent proceeds with the default. Without one, the message becomes `expired` and channel
   messages are edited to "⏰ Options expired".
6. Client-side, the CLI long-polls `POST /api/messages/:id/poll` (not SSE) and on timeout prints the
   default label to stdout (`ask.rs:241-287`). `--action` commands are **never executed by the CLI**
   — they are printed for the LLM to act on (a deliberate trust boundary; see F-M6).

**Delivery**: critical/high fan out to all configured channels; normal picks the routed or most
recent one (`messages.ts:141-146`, `message-queries.ts:9-27`). Per-priority routing from
`api_keys.channel_routing`. Quiet hours enqueue into `delivery_queue`, drained by cron with
3-attempt exponential backoff; failures land in `metadata.delivery_error` and stay in the queue
forever (no dead-letter cleanup).

**Agent-to-agent**: `--to` resolves against all agents by name/id-prefix, then sessions by label
(most-recently-active wins); delivered via SSE/callback only (`channel='api'`). Groups let any agent
add any agent and broadcast (`groups.ts:100-103`) — both unscoped (F-H2).

---

## 7. Client surfaces

**CLI (Rust)** — the full agent contract: send/ask/inbox/reply/react/edit/forward/status, agent
config, routes, groups, boss management, session board, channel setup wizards, doctor. Identity in
a plaintext global config (macOS: `~/Library/Application Support/hiboss/config.json` — the docs say
`~/.config`, F-L*). Claude Code integration via three hooks:

- **SessionStart**: cleans `/tmp` markers, registers the session, silently marks all prior messages
  read (F-M11), starts the SSE daemon, injects the MANDATORY instruction block, broadcasts to peers,
  prints unread inbox.
- **PostToolUse**: local-only drain of the daemon spool into the conversation (`[boss]`/`[peer]`
  lines), urgent-flag surfacing, and periodic detached `bg-check` (read-marking, heartbeat,
  urgent counting).
- **Stop**: blocks the first stop attempt with exit 2 ("ask boss first") unless an ask was sent this
  session; one-shot — the second stop passes (F-L*).

**Daemon**: reconnecting SSE consumer appending raw events to the `/tmp` spool that PostToolUse
drains. This spool is the trust boundary that F-H4 (local prompt injection) crosses.

**MCP plugin (Bun)**: same REST/SSE bridge as tools (`send, ask, reply, inbox, …`) plus push
notifications into Claude. Diverges from the CLI: own session id (F-M9), comma-split options
(F-M13), 300 s vs 1800 s ask timeout, no `--action`/`--default` support.

**HibossKit (Swift)**: shared domain models (metadata incl. `default_option`), `HibossAPI`
(Bearer boss token, SSE stream with `message`/`resolved` events), `OptionFlowStore` (2 s reconnect,
reactive history refresh, client-side expiry timers), session grouping, Keychain token storage.

**macOS HiBoss Island**: answer-focused menu-bar app — Dynamic-Island-style option picker (default
option gets return-glyph + "default" pill), free-text reply, session-grouped History with
answerable past asks, Settings for notification routing/quiet hours/sounds. No admin surfaces
(agents/groups/bosses/rules/audit are web-only — by design, worth keeping deliberate).

**iOS**: Inbox (SSE + optimistic reply), Live Activity / Dynamic Island decision card with App
Intents, APNs with actionable categories (Approve/Reject map positionally to options[0]/[1] —
F-M14), Keychain shared with extensions. Sessions tab is a visible stub; out-of-app reply failures
are silently swallowed (F-M15).

**Web console** (SvelteKit SPA on Cloudflare Pages): the only full admin surface — dashboard,
messages (reply/react/forward), sessions, agents config, groups + broadcast, bosses + access +
token rotation, routing rules, channels, audit, system doctor. Boss token in `localStorage`
(F-H5b), no client-side role gating (viewer sees every write control and gets server 403s, F-M16),
and no live updates (SSE helpers exist but are unwired, F-M12).

**Terminal (ESP32)**: hardware scaffold only — vendored LVGL/LCD/touch components and sdkconfig;
no application firmware exists yet. Its working-tree `sdkconfig` holds live secrets (F-C1).

Capability matrix (✓ implemented, — absent):

| Capability | macOS | iOS | Web | CLI (agent) |
|---|---|---|---|---|
| Answer options / free text | ✓ | ✓ | ✓ | — |
| Default-option marking | ✓ | ✓ (LA) | data only | ✓ author |
| Live updates | SSE | SSE+APNs | — | SSE daemon |
| History / messages | ✓ | ✓ | ✓ | ✓ |
| Session board | grouped history | stub | ✓ | ✓ `ss` |
| Notification prefs / quiet hours | ✓ | — | — | — |
| Agents / groups / bosses / rules / audit | — | — | ✓ | ✓ (API parity) |

---

## 8. Consolidated audit findings

Deduplicated across the four audits; ranked. Severity reflects the current single-tenant,
pre-open-source posture.

### Critical

- **F-C1 · Live boss token + Wi-Fi password in the terminal working tree.**
  `terminal/sdkconfig:601-604` holds a real boss key (`hb_boss_… (redacted; rotated 2026-07-22)`), Wi-Fi credentials, and
  the production server URL; the file is gitignored but the token is live and would be baked into
  extractable firmware. **Rotate the token now**; provision via NVS/encrypted storage later.

### High

- **F-H1 · Global audit log readable by any agent.** `GET /api/audit` returns the entire audit
  log to any agent key with no scoping (`audit.ts:12-20`).
- **F-H2 · No agent-to-agent isolation.** Any agent can message/spam any agent or session
  (`messages.ts:159-193`) and add arbitrary agents to its groups for broadcast
  (`groups.ts:100-103`) — a peer-to-peer instruction-injection channel with no rate limit by
  default.
- **F-H3 · Unauthenticated attachment downloads.** `GET /api/attachments/:key` serves any R2 object
  to URL holders, publicly cacheable, forever (`attachments.ts:54-69`).
- **F-H4 · Local prompt injection via /tmp spool.** Any local process can append lines to the
  predictable world-writable `/tmp/hiboss-daemon-<hash>.pending` (or the urgent file); PostToolUse
  prints them into Claude's context as trusted `[boss]` messages (`hook.rs:157-196`). No ownership
  or permission checks.
- **F-H5 · Plaintext long-lived tokens at rest.** (a) Agent key in cleartext config JSON with
  default file perms (`config.rs:38-46`); (b) web console boss token in `localStorage`
  (`web/src/lib/api/auth.ts:7,34-36`) — full-admin token exposed to any XSS. Native clients
  correctly use Keychain.
- **F-H6 · No data retention anywhere.** `messages`, `audit_log`, `delivery_queue`,
  `join_requests`, and R2 grow forever; the only hard delete in the system is explicit session
  deregistration (`sessions.ts:119`). D1 size and latency degrade unboundedly.
- **F-H7 · Stale sessions never reaped.** Crashed CLIs leave permanent `working`/`waiting` rows
  that still create channel threads and can be `--to` targets (`sessions.ts:70`,
  `messages.ts:181-189`).

### Medium

- **F-M1 · Shared Discord Gateway controllable by any agent** — connect/disconnect with an
  arbitrary `bot_token` (`discord-gateway-api.ts:19-27`): DoS or bot substitution.
- **F-M2 · Cleartext keys in `join_requests`** until polled; boss tokens returned in the clear on
  mint; unsalted single-round SHA-256 hashing (`join.ts:48-50`, `bosses.ts:291`, `auth.ts:15-20`).
- **F-M3 · Non-constant-time secret compares** on both webhooks and bootstrap
  (`webhooks.ts:33,83`, `bootstrap.ts:51`).
- **F-M4 · Open bootstrap / join flooding.** Bootstrap open when `BOOTSTRAP_SECRET` unset
  (`bootstrap.ts:41-44`); first join on an empty DB self-approves; no rate limit on `/api/join`.
- **F-M5 · Metadata impersonation.** Sender-supplied metadata is not filtered; reserved fields
  (`boss_id`, `boss_name`, channel message ids) can be spoofed (`message-helpers.ts:47-52`).
- **F-M6 · Boss-mediated command injection via `--action`.** Action strings round-trip as data and
  the agent is prompted to execute them; a compromised boss channel hands the agent arbitrary shell
  (`ask.rs:251-277`). Mitigated by the CLI never exec-ing itself.
- **F-M7 · Option expiry race window.** Buttons are rejected as "already selected" for up to 5 min
  between `expires_at` and the cron sweep, before the default even applies
  (`boss-option-reply.ts:39-41`, `wrangler.toml:28`).
- **F-M8 · callback_data truncation.** Long option labels truncated by Telegram's 64-byte /
  Discord's 100-char limits fail as `invalid_choice` (`message-options.ts:41`, `delivery.ts:151`).
- **F-M9 · CLI/MCP session divergence.** MCP mints its own session id (`mcp/server.ts:238-244`);
  one Claude session appears as two hiboss sessions with disjoint scoping.
- **F-M10 · Parallel sessions in one repo collide** — per-directory hash shares session file,
  daemon, and markers (`session.rs:39-56`).
- **F-M11 · SessionStart silently marks all prior messages read** (`hook.rs:97-98`).
- **F-M12 · Web console is not live** — SSE helpers unwired; time-boxed asks can be missed
  (`client.ts:220-228`).
- **F-M13 · MCP splits options on commas** — reintroduces the ambiguity the CLI removed
  (`server.ts:276-279`).
- **F-M14 · iOS Approve/Reject are positional** (`options[0]`/`options[1]`,
  `PushManager.swift:114-116`) — wrong semantics for non-binary asks.
- **F-M15 · iOS out-of-app replies swallow failures** (`RespondIntent.swift:25`,
  `PushManager.swift:122`) — the boss thinks they answered; the agent keeps waiting.
- **F-M16 · Web console has no role gating** — viewer sees every destructive control; server 403s
  are the only guard (`bosses/+page.svelte:64-103`).

### Low / informational (grouped)

- SSE `delivered`-marking races and second-granularity cursor (`stream.ts:44-68,121-130`); brief
  `expires_at` NULL window after insert (`messages.ts:224-229`); expiry batch limit 50/5 min.
- Admin bosses receive **all** agents' notifications regardless of `boss_agent_access`
  (`notify.ts:50-53`) — intended for admins, but bypasses scoping on the notification path.
- Superseding asks auto-answer the older ask's default silently (`messages.ts:317-319`).
- Viewer can mark-read and edit own preferences (no guard, `boss-api.ts:432`, `:96`); any boss can
  enumerate all bosses' contact identifiers (`bosses.ts:72-90`).
- SSRF-lite: `callback_url` is unvalidated worker egress (`notify.ts:20-37`); prefix-match id
  resolution can bind to unintended rows (`bosses.ts:296-300` et al.).
- Audit gaps: attachments, devices, sessions, gateway ops, and agent-as-boss replies are unlogged;
  webhook messages from unresolved senders logged as `system`.
- Hooks: PATH-based `hiboss` invocation (`hook.rs:147`) vs `current_exe()` elsewhere; one-shot Stop
  gate; non-atomic read-queue appends; `.expect()`/`.unwrap()` in client/daemon startup paths
  despite the no-unwrap rule; no `https://` scheme enforcement on the server URL.
- Docs drift: config path is `~/Library/Application Support/hiboss` on macOS, not `~/.config`
  (`config.rs:18-23`); ask timeout defaults differ (CLI 1800 s, MCP 300 s); dead session statuses
  `blocked`/`idle` nothing emits; SSE parsers differ on multi-line `data:`.
- HibossKit drops server error bodies (`HibossAPI.swift:158-165`); Keychain items use default
  accessibility (not `ThisDeviceOnly`); fixed 2 s SSE reconnect with no backoff; iOS Sessions tab
  is a shipped stub; terminal is scaffold-only.

---

## 9. Recommendations

Ordered by leverage; the first block should land before any public/open-source push.

1. **Rotate the exposed boss token** (`hb_boss_… (redacted; rotated 2026-07-22)`) and sweep the tree with a secret scanner
   (F-C1). Add the scan to CI.
2. **Scope the agent surface**: restrict `GET /api/audit` to the requesting agent (or boss-only),
   gate agent-to-agent targeting and group membership behind an explicit allowlist or at least the
   boss's access map, and require an admin credential for Discord-gateway connect/disconnect
   (F-H1, F-H2, F-M1).
3. **Harden tokens at rest**: chmod 600 the CLI config (or keychain), move the web console to a
   short-lived session token, stop persisting cleartext keys in `join_requests` (deliver-once
   pattern), and add constant-time compares (F-H5, F-M2, F-M3).
4. **Close the local injection path**: create the daemon spool with 0600 and verify ownership
   before draining; tag drained lines as untrusted if the file fails the check (F-H4).
5. **Add retention + reaping**: cron jobs for message/audit/queue TTLs, R2 lifecycle, and
   stale-session sweep (auto-`completed` after N hours) (F-H6, F-H7).
6. **Fix the expiry race**: let `claimOptionReply` accept presses when `expires_at` has passed but
   the message is still unclaimed, or run expiry more often than 5 min (F-M7).
7. **Client polish round**: wire SSE (or polling) into the web console + role-gate its UI; replace
   iOS positional Approve/Reject with explicit option intents and surface reply failures; unify
   MCP session identity and option parsing with the CLI (F-M9, F-M12–F-M16).
8. **Decide the multi-tenant story explicitly.** Most High findings are "flat trust model" issues
   that are tolerable for one operator. The README/whitepaper for the open-source release should
   either document the single-tenant assumption prominently or the fixes in (2) should land first.
