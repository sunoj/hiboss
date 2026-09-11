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
| `api_keys` | **phase 3a: done** — unique agent names with a duplicate guard; exact-name addressing precedes the retained ID-prefix path. **phase 3a: deferred** — removing `session_info` and splitting keys/agents | No identity changes |
| `bosses` | **phase 2b: done** — external accounts backfilled; inbound lookup reads them first, with legacy-column fallback until 2c. Admin identity edits synchronize both stores. Removed `preferred_channel`/`notify_priorities` validation and CLI/dashboard controls; quiet hours stay. Old stored preference keys are pruned when admin preferences are updated | Copy both provider IDs into `boss_external_accounts`; deleting an account clears its matching legacy fallback |
| `boss_tokens` | **phase 1a: done** — nullable `client_id`; existing bearer hashes remain valid | One client per non-revoked token; kind from bound signing key `client_kind` else `web`; token label and usage timestamps retained |
| `boss_signing_keys` | **phase 1a: done** — nullable `client_id`; **phase 1a: deferred** — removing `boss_token_id` until native follow-up | Via token → client; keys of revoked tokens remain unbound |
| `boss_pairing_codes` | **phase 1a: done** — redemption atomically creates client, token, and optional signing key | Kind from signing registration, otherwise `web`; label from `device_label` |
| `boss_devices` | **phase 1a: done** — nullable `client_id`, stamped from bearer; delete on client revoke. **phase 1a: deferred** — rename to `boss_push_devices` (churn for 3 rows) | Attach to newest ios client by creation time, then ID; create one `migrated-push` ios client per boss if absent |
| `boss_agent_access` | **phase 1a: done** — panels adopt admin-sees-all; manager/viewer retain explicit grants and target ownership (decision A) | No grant backfill needed |
| `channel_configs` | **phase 2a: done** — additive providers, boss destinations, and route backfill; off/shadow retain legacy delivery. **phase 2b: done** — boss Notifications replaces Channels in console navigation; the old route remains reachable. Config removal waits for the parity week | Distinct bot token/webhook providers; destinations per accessible boss/provider/chat; mixed enabled flags collapse with OR |
| `routing_rules` | **phase 2a: done** — `inbound_routes` take precedence with deterministic priority/ID ordering. **phase 2a: deferred** — removing legacy fallback in 2b | 0 existing rules; no arbitrary default inbound agent chosen for shared chats |
| `delivery_queue` | **phase 2a: done** — flagged `message_deliveries` fan-out, quiet deferral, retry cron, and shadow mismatch audits. **phase 2a: deferred** — drain/drop legacy queue after parity | Shadow rows are observations, never retried; existing legacy queued work is retained |
| `sessions` | **phase 3a: done** — nullable project FK, alias resolution on registration, CLI project object/full cwd/slug labels, owner validation for messages/progress. **phase 3a: deferred** — agent-qualified local slots, removing stored labels and legacy thread writes | Label prefix (whole label when no slash) → alias → project; existing route semantics retained |
| `session_events` | Keep; fix `actor_agent_id` for boss-originated events (write NULL + boss in provenance) | — |
| `agent_groups`, `agent_group_members` | Keep | — |
| `messages` | **phase 2a: done** — migration leaves columns and rows untouched; on mode records external send state in `message_deliveries`. **deferred beyond 2b** — universal seen-status semantics and legacy receipt consumer removal; messages remain untouched | No message backfill |
| `progress_posts` | **phase 3a: done** — project FK, auto-create and legacy text resolution; feeds and Home read projects. **phase 3a: deferred** — removing text column in 3b | Distinct text values become aliases |
| `progress_teams` | **phase 3a: done** — profiles copied into projects; PUT writes projects; legacy table is an application-level read-only snapshot. **phase 3a: deferred** — drop in 3b | Preserve profile fields, creator attribution and timestamps |
| `destination_routes` | **phase 3a: done** — nullable project FK backfill. **phase 3a: deferred** — ID-based routing and removal of text scope in 3b; flag semantics unchanged | Text alias, then session project |
| `progress_likes` | Keep (boss-owned is right) | — |
| `join_requests` | Keep; rename in docs from "device onboarding" to "agent enrolment" | — |
| `audit_log` | **phase 1a: done** — atomic `client.revoke`. **phase 2a: done** — `destination_shadow` records external-chat set mismatches without credentials | Compare new shadow observations for one week before cutover |
| `panels` + 4 panel tables + 4 interaction tables | **phase 1a: done** — admin access across panels, lifecycle, and relay; stored `target_boss_id` unchanged; schema remains truthful | — |
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

Phase 1a delivers the server and console Devices inventory. Any authenticated boss can
mint and revoke their own other clients; even admins cannot revoke another boss's client
through this route, matching the individual token routes' ownership boundary. The current
client uses the existing token self-revoke endpoint. Connect validates the pasted bearer,
mints a web client labelled with browser/platform, and stores only the fresh token. Native
request formats and existing tokens remain unchanged; native adoption is phase 1b.
Client activity is refreshed at most once per minute with a database-guarded update.
The additive nullable links also allow tokens issued by existing admin rotation to remain
unbound until exchanged. Revoked clients stay visible as inventory history.

Phase 2a delivers the additive server model, boss destination/provider APIs, and
`DESTINATIONS_MODE=off|shadow|on` (default `off`). The rollout and comparison queries
are in [destinations-rollout.md](destinations-rollout.md). Native destination inventory
is backfilled; client notification settings/receipt adoption, removal of legacy tables,
and CLI channel-management changes remain phase 2b. No cutover is implied by merging 2a.

Phase 3a delivers additive project identity, aliases, server/CLI resolution, unique agent
names, and session-owner checks. The [projects rollout guide](projects-rollout.md) records
legacy-client behavior, collision/conflict handling, and the phase 3b cleanup boundary.
No destination cutover or deployment is implied by this implementation.

Immediate items, independent of the redesign (this week): the unscoped
`/api/sessions?all=true`, and the APNs upsert that can re-parent a device token.

## 7. Out of scope

Panel runtime internals (definitions, operations, outbox, interactions) beyond FKs;
provenance JSON shape; multi-tenant or organisation concepts (self-hosted, single boss set);
renames for taste.
