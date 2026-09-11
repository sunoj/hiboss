# Entity model redesign — proposal for review

Status: **approved 2026-09-11 — scope L (phases 0–4)**. Decisions A–F stand as written. Companion to `investigation-entity-model.md` (facts, 2026-09-11).
Where this document says "today", it cites that inventory. Production row counts on 2026-09-11:
messages 29,006 · sessions 3,873 · api_keys 7 · bosses 2 · boss_tokens 5 · boss_devices 3 ·
channel_configs 7 · panels 13 · progress_posts 16 · routing_rules 0.

## 1. Why

The boss's own words: boss identity, the client a boss logs in from, devices, the boss's
third-party notification channels, agent identity, an agent's projects and its sessions are
tangled. The inventory confirms three structural causes:

| Cause | Today | Symptom this week |
| --- | --- | --- |
| **Delivery destinations hang off the sender** | `channel_configs` is per agent and holds bot credentials, the chat/channel to post into, and the enabled flag together | "Turn off Discord" meant flipping four agent rows; `bosses.preferences` is written but never read at delivery |
| **No client-instance entity** | Token label, signing key `client_kind`, APNs row and relay tickets each describe "a device" with no shared id | "Turn on Mac notifications" could only be a local app setting; revoking a token leaves its APNs row alive |
| **Project is text, not an entity** | `progress_posts.project`, `progress_teams.project`, session label prefix and Home cards all use strings derived three different ways | Same repo shows up under different names; nothing links sessions to projects |

## 2. Target model

Principals own credentials and clients. Bosses own destinations. Agents own sessions.
Projects group sessions and posts. Work objects point at principals with real FKs.

```
boss ──< boss_clients ──< boss_tokens (1 per client)
  │            ├──< boss_signing_keys
  │            └──< boss_push_devices
  ├──< boss_external_accounts   (telegram/discord user id → boss)
  ├──< boss_destinations ──> channel_providers (bot creds, server-level)
  │            └──< destination_routes (project/session → channel/thread)
  └──< boss_agent_access >── agents

agents ──< agent_keys (phase 4, deferred)
agents ──< sessions ──> projects ──< project_aliases
messages ──< message_deliveries ──> boss_destinations
progress_posts ──> projects ;  panels ──> sessions, target boss (unchanged)
```

### 2.1 Entities

| Entity | Owner | Purpose | Key fields |
| --- | --- | --- | --- |
| `bosses` | — | Human identity and role | id, name, role admin/manager/viewer, `agent_id` (kept, see §5), preferences (quiet hours only) |
| `boss_external_accounts` | boss | Recognise the boss when they type in a chat | boss_id, provider, provider_user_id (unique per provider) |
| `boss_clients` | boss | **New.** One installed client: iPhone, Mac, browser, CLI | id, boss_id, kind ios/macos/web/cli, label, created_at, last_seen_at, revoked_at |
| `boss_tokens` | client | Bearer credential; exactly one live token per client | + `client_id` FK; label moves to client |
| `boss_signing_keys` | client | Device-held ES256 key | `client_id` replaces `boss_token_id` |
| `boss_push_devices` | client | APNs registration (rename of `boss_devices`) | + `client_id`; unique device_token; delete on client revoke |
| `channel_providers` | server | Bot/app credentials, one row per Telegram bot or Discord app | id, provider, credentials JSON, label |
| `boss_destinations` | boss | Where a boss wants to be reached, and when | id, boss_id, provider_id or client_id, kind telegram_chat/discord_channel/apns/native_live, target JSON (chat_id, channel_id, webhook), enabled, min_priority, honours_quiet_hours |
| `destination_routes` | destination | Where a project's or session's traffic lands inside a destination | destination_id, project_id or session_id, external_channel_id, external_thread_id. Replaces `sessions.discord_thread_id`, `sessions.telegram_topic_id`, and the topic ids inside config JSON |
| `inbound_routes` | destination | External chat → which agent receives a message typed there (regex optional) | destination_id, pattern, target_agent_id, priority. Replaces `routing_rules.owner_id = agent` |
| `projects` | — | **New.** Real identity for a codebase | id, slug (unique), display name, repo_url, profile fields (absorbs `progress_teams`) |
| `project_aliases` | project | Absorb the three naming paths | project_id, alias (unique): origin basename, cwd basename, explicit `--project` |
| `sessions` | agent | One CLI run | + `project_id` FK; `cwd` becomes full path; label derived `slug/branch`, not stored |
| `message_deliveries` | message | Per-destination fan-out state | message_id, destination_id, status sent/delivered/read/failed, external_message_id, attempts, next_attempt_at. Replaces `delivery_queue` and the per-channel meaning of `messages.status` |
| `agents` / `agent_keys` | — | Identity split from credential | **Phase 4, deferred** — see §6 |

### 2.2 Disposition of every current table

| Today | Disposition | Backfill |
| --- | --- | --- |
| `api_keys` | Keep as-is until phase 4; conceptually "agent + its one key" | — |
| `bosses` | Keep; drop `telegram_user_id`/`discord_user_id` after `boss_external_accounts` is read everywhere; drop `preferences.preferred_channel`/`notify_priorities` (never read) | Copy the two provider ids into external accounts |
| `boss_tokens` | Keep; add `client_id` | One client per existing token; kind from signing key `client_kind` else `web`; label from token label |
| `boss_signing_keys` | Keep; point at client | Via token → client |
| `boss_pairing_codes` | Keep; redemption creates the client, then token | — |
| `boss_devices` | Rename `boss_push_devices`; add `client_id` | Attach to the boss's most recent ios client; ambiguity flagged for manual fix (3 rows) |
| `boss_agent_access` | Keep — the access boundary (decision A) | — |
| `channel_configs` | **Split** into `channel_providers` + `boss_destinations` + `destination_routes`; then drop | One provider per distinct bot token; one destination per (boss with access, chat id); the agent's channel becomes a route for that agent's projects |
| `routing_rules` | Becomes `inbound_routes` | 0 rows |
| `delivery_queue` | Becomes `message_deliveries` with `next_attempt_at` | Drain then drop |
| `sessions` | Keep; add nullable `project_id`; stop writing thread/topic columns | Project from label prefix via aliases; nullable stays for old rows |
| `session_events` | Keep; fix `actor_agent_id` for boss-originated events (write NULL + boss in provenance) | — |
| `agent_groups`, `agent_group_members` | Keep | — |
| `messages` | **Additive only** (29k rows, D1 CPU limit): no column rewrite; `status` becomes "boss has seen it" only | — |
| `progress_posts` | Add `project_id` FK; keep `project` text one phase for old clients | Via aliases |
| `progress_teams` | Merge into `projects` (profile fields) and drop | 1 row |
| `progress_likes` | Keep (boss-owned is right) | — |
| `join_requests` | Keep; rename in docs from "device onboarding" to "agent enrolment" | — |
| `audit_log` | Keep | — |
| `panels` + 4 panel tables + 4 interaction tables | Keep; only add them to `schema.sql` (phase 0); `target_boss_id` unchanged | — |
| `interaction_submissions.boss_id` | Add `client_id` alongside for provenance | — |

## 3. Acceptance scenarios

| Scenario | Today | Target |
| --- | --- | --- |
| Boss turns off Discord | 4 agent rows via new console toggle | `UPDATE boss_destinations SET enabled=0 WHERE id=?` — one row, one switch on the boss's own Notifications page |
| Boss wants Mac banners for messages | App-local setting, no server knowledge | `boss_destinations(kind=native_live, client_id=<mac>)`; the server knows the Mac is a destination and can show it next to Telegram |
| New iPhone paired | token + signing key + separate APNs row | Redemption creates one `boss_clients` row; token, key and push device attach to it |
| Lost phone revoked | Token revoked, APNs row keeps sending | `boss_clients.revoked_at` cascades: token dead, push row deleted, signing key revoked |
| Boss types in Telegram chat C | `channel_configs` `LIMIT 1` finds an agent; provider user id finds boss | `boss_external_accounts` → boss; `inbound_routes` for the destination that owns C → target agent, deterministic |
| Which sessions touched project P | Label-prefix string match | `sessions WHERE project_id=?`; Home cards read `projects` |
| Agent posts progress from a renamed checkout | New project string, split timeline | Alias lookup lands on the same project; unknown alias auto-creates (decision B) |
| High-priority ask at 02:00 | Quiet hours per boss, queue per agent channel | Destination `honours_quiet_hours=0` for the phone, `1` for Discord; deferral is a row in `message_deliveries` |
| Same repo, two agents, two Discord channels | Two `channel_configs` | Two `destination_routes` under one destination, or two destinations — the boss decides where each project lands |

## 4. Inventory smells → disposition

| Smell (§6 of inventory) | Disposition |
| --- | --- |
| schema.sql incomplete | **Phase 0** |
| Agent identity = key row | Phase 4 (deferred) |
| Admin vs workflow role share `api_keys.role` | Phase 4 |
| Boss general access vs panel explicit access | **Phase 1**: panels adopt "admin sees all" (decision A) |
| `/api/sessions?all=true` unscoped | **Security fix now**, outside this redesign |
| No project identity / three naming defaults / team ownership | Phase 3 |
| Local session slot keyed by directory only | Phase 3 (CLI adds agent id to the slot key) |
| `api_keys.session_info` free JSON | Drop in phase 3 (unused by clients) |
| Unequal session FK enforcement | Phase 3: messages/progress validate session owner like panels do |
| "Device" in three places / APNs upsert can move a token between bosses | **Phase 1** (`boss_clients`); the upsert bug is fixed now |
| Boss-owned identity, agent-owned destination | **Phase 2** |
| Telegram topic at two scopes | Phase 2 (`destination_routes`) |
| Persisted preferences never read | Phase 2 deletes `preferred_channel`/`notify_priorities`; quiet hours stay |
| Preference validation differs | Phase 2: one validator |
| Channel validators disagree; `email` accepted, `api` pseudo-channel | Decision D |
| Global delivery status vs fan-out | Phase 2 (`message_deliveries`) |
| Addressing uniqueness | Phase 3: `api_keys.name` UNIQUE (7 rows, all distinct today); session label stays non-unique, ambiguity keeps returning 409 |
| Boss provenance duplicated in JSON | Kept deliberately (audit trail), out of scope |
| Event actor column = recipient for boss messages | Phase 2 fix |

## 5. Decisions

Taken by the architect (stated so they can be overruled, not so they can be re-asked):

| # | Decision | Why |
| --- | --- | --- |
| A | Access is agent ownership (`boss_agent_access`); admin sees all, including panels | Two bosses, seven agents, one operator. Project-level ACL adds a table and UI for a case that does not exist; the panel "admin must be granted" exception is a bug, not a feature |
| B | Projects auto-create on first sight; slug = origin repo basename; cwd names become aliases | Explicit registration breaks every hook on the two remote boxes until someone runs a command there |
| C | Agent identity/credential split deferred to phase 4 | Every installed CLI holds a key; highest blast radius, lowest daily value |
| D | `email` deleted everywhere; `api` becomes the explicit destination kind `native_live` | "No built-in email" is already a recorded decision; `api` is a pseudo-channel nobody can configure |
| E | `bosses.agent_id` (agent-as-boss) unchanged | Recorded architecture decision with three live uses; nothing here needs it |
| F | Phase 2 ships behind a flag with dual-write and a one-week parity comparison | 29k messages and live Telegram traffic; a silent cut-over has no rollback signal |

**The one decision that is the boss's — how far to go:**

| Option | Delivers | Cost (dispatch rounds, rough) | Risk | Trade-off |
| --- | --- | --- | --- | --- |
| **S — fix the pain** (phases 0–2) | Truthful schema; client entity with cascade revoke; boss-owned destinations (Discord/Telegram/phone/Mac switches on one page); per-destination delivery state | ~8–10 rounds over 2–3 weeks | medium, concentrated in phase 2 | Projects stay text; Home cards keep the label-prefix hack; renamed checkouts still split timelines |
| **M — pain + projects** (phases 0–3) — **recommended** | S plus real projects, sessions linked to projects, one naming path, unique agent names, session-owner validation | ~12–14 rounds over 4–5 weeks | S's risk plus low-medium; phase 3 is additive and old CLIs keep working | Agent keys stay one-per-agent; re-enrolment avoided |
| **L — everything** (phases 0–4) | M plus agents split from keys, multiple revocable keys, admin role separated | ~16+ rounds, 6+ weeks | high in phase 4: every CLI, both remote boxes, re-enrol | Only worth it before open-sourcing to strangers who will rotate keys; for one operator it is churn |

## 6. Phases

Each phase ships alone, with dual-read until parity is observed, and never breaks a CLI
that has not been upgraded. D1 rule: additive migrations only on `messages`; check
`meta.rows_read` with `--remote` before and after.

| Phase | Content | Risk | Old-client impact |
| --- | --- | --- | --- |
| **0** Truthful schema | Regenerate `schema.sql` from migrations 0001–0038 (five panel tables, interaction tables); CI check that applying migrations to an empty D1 equals schema.sql | none | none |
| **1** Boss clients | `boss_clients`; tokens/keys/push devices attach; pairing creates a client; console "Devices" page lists clients with revoke; APNs upsert no longer moves tokens between bosses; panels adopt admin-sees-all | low | none (tokens unchanged) |
| **2** Destinations | `channel_providers`, `boss_destinations`, `destination_routes`, `inbound_routes`, `message_deliveries`; delivery reads destinations behind a flag, dual-write both paths, compare for a week, then drop `channel_configs` + `delivery_queue`; console/iOS/macOS "Notifications" page per boss replaces the Channels page and the unread preferences; native `native_live` destinations make Mac/iOS banners a server-known choice | medium — this is the payoff and the largest change | `hiboss channel set` becomes a boss-side action; CLI keeps a shim that prints where to do it |
| **3** Projects | `projects`, `project_aliases`, `sessions.project_id`, `progress_posts.project_id`; CLI sends slug + aliases; Home and progress read projects; `api_keys.name` UNIQUE; session-owner validation on messages/progress | low-medium | old CLIs keep sending text; server resolves via aliases |
| **4** Agent split (deferred) | `agents` + `agent_keys`, multiple revocable keys, admin role separated from workflow role | high | every CLI re-enrols |

Immediate items, independent of the redesign (this week): the unscoped
`/api/sessions?all=true`, and the APNs upsert that can re-parent a device token.

## 7. Out of scope

Panel runtime internals (definitions, operations, outbox, interactions) beyond FKs;
provenance JSON shape; multi-tenant or organisation concepts (self-hosted, single boss set);
renames for taste.
