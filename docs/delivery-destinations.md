# Delivery destinations

HiBoss has two external delivery paths. The legacy path selects an agent's configured
channel (`channel_configs`, `routing_rules`, `delivery_queue`). The destination path
delivers to each boss's own destinations (`channel_providers`, `boss_destinations`,
`destination_routes`, `inbound_routes`, `message_deliveries`). The Worker binding
`DESTINATIONS_MODE` chooses between them.

## Modes

An absent or unrecognized value resolves to `off` (`server/src/delivery/types.ts`).

| Mode | External delivery | Destination records | Cron |
| --- | --- | --- | --- |
| `off` | Agent channel selection, quiet-hours queue and APNs notifier | None | Legacy delivery queue |
| `shadow` | Identical to `off`; destination changes have no delivery effect | Queued observations plus mismatch audits | Legacy queue only |
| `on` | Enabled destinations of every accessible boss; the channel argument is a hint | Per-destination attempts, external ID, result and quiet deferral | Destination retries only |

In `on` mode, destinations carry new sends, agent-to-boss replies and forwards.
Agent-to-agent and boss-as-agent callbacks keep their semantics; APNs is excluded from
the legacy notifier. Legacy normal/low messages select one channel and urgent ones fan
out; the destination resolver fans out across every eligible boss destination.

Shadow rows have `status='queued'`, `attempts=0` and `next_attempt_at=NULL`. They never
send, even after switching to `on`. A shadow recording error is logged without changing
the legacy response or sends. Shadow audits (`audit_log.action = 'destination_shadow'`)
contain SHA-256 fingerprints of provider credentials plus effective chat/channel and
thread IDs, never credentials or device tokens.

Switching from `on` to `off` restores legacy delivery for new messages; `on`-mode retry
rows pause until `on` is restored. Shadow rows are never replayed. `on` leaves legacy
queue rows untouched, so drain the legacy queue before enabling it.

## Providers, destinations and routing

- Providers deduplicate by provider plus webhook URL, falling back to bot token
  (`credential_hash`, unique). Provider APIs return only ID, provider, label and creation
  time; credentials stay server-side and destination targets cannot carry credentials.
- An admin boss receives destinations from every agent; managers and viewers only from
  their grants.
- Session routes keep Discord threads and Telegram topics. Route lookup prefers session,
  then project, then agent-name fallback, then an unscoped route; a missing route uses
  the destination target. `on` mode does not create threads automatically; provision
  routes explicitly. Legacy thread creation remains in `off`/`shadow`.
- `inbound_routes` are consulted only in `on` mode. Priority descending, then route ID,
  selects the first matching pattern; a NULL pattern is a catch-all and invalid patterns
  are skipped. Unmatched traffic uses the channel/session lookup.
- A Telegram text that replies to a message answers that message, whichever agent sent it,
  when the message was delivered to that chat (a delivery row's `external_message_id` for a
  `telegram_chat` destination, or the legacy `telegram_message_id`/`telegram_chat_id`
  metadata) and the replying boss can access its agent. The answer goes through the same
  one-answer claim as every other path. A reply that matches nothing, or a message the boss
  cannot access, is routed like unquoted text and links to no parent. Option buttons still
  resolve only the chat's agent; a button for another agent's message returns 404.
- Each iOS/macOS client has a `native_live` destination; each push device has an `apns`
  destination referencing its device ID. Revoked clients and removed devices are
  excluded when resolving or retrying.

## Quiet hours, grouping and retries

Thresholds are `low < normal < high < critical`. Quiet hours apply only to normal and low
priority in every mode; high and critical bypass them. An enabled destination stays
eligible during quiet hours with its own due time. `honours_quiet_hours=false` opts a
destination out of quiet hours entirely.

Eligible destinations across bosses collapse by effective external target: credential
hash plus chat/channel and thread for Telegram/Discord, device token for APNs, client ID
for native live. Each target key has a unique per-message claim. The earliest due time
wins (immediate beats deferred), then destination ID. Only the canonical row has a retry
schedule and attempt count; duplicates reference it through `merged_into` and copy its
status and external receipt. Retries re-resolve the group, so an eligible shared
destination can replace a disabled canonical one. Changing the effective target cancels
its retry. Deleting a destination cascades its routes and delivery rows.

Each external attempt claims its row for five minutes. A failed send retries after one
minute, then two minutes, for at most three attempts. Cron rechecks access, enabled
state, client/device ownership, quiet hours and expiry. Exhausted or ineligible rows
become terminal failures with NULL `next_attempt_at`. External acceptance records `sent`,
which is not a human receipt. Error text is sanitized so provider URLs and tokens never
reach delivery records. Native live rows stay queued without a retry time: streams expose
stored messages and no per-client receipt is claimed.

Providers offer no transaction shared with D1. A process failure after provider
acceptance but before the success write can duplicate a retry; the lease prevents
overlapping cron attempts but does not make external sends exactly-once.

## Boss API

- `GET /api/boss/destinations` lists the caller's destinations with provider labels,
  route counts, the effective mode and credential-free provider choices.
- Managers and admins can `POST` Telegram/Discord destinations using an existing provider,
  `PATCH` `enabled`, `min_priority`, `honours_quiet_hours` and `label` (JSON booleans),
  and `DELETE` their own destinations. Viewers are read-only. No boss can mutate another
  boss's destination through this API.
- `GET/POST /api/boss/providers` is admin-only. A duplicate effective credential returns
  409. Responses never contain credentials or their hashes. No email kind is accepted.
- `POST /api/boss/destinations/:id/test` requires ownership and a non-viewer role and
  returns 409 unless the mode is `on`. It sends a probe to the base destination, ignoring
  thresholds and quiet hours, without inserting a message. Native live destinations have
  no push adapter and return 409; adapter failures return a sanitized 502.
- `GET/POST /api/boss/me/external-accounts` and `DELETE …/:id` manage the caller's
  Telegram/Discord identities (viewers read-only); admins use
  `/api/bosses/:bossId/external-accounts`. Provider/user pairs are globally unique.
  Inbound Telegram and Discord interactions prefer this table and fall back to the
  legacy boss columns only when the pair is absent.

The web console's Notifications page manages the current boss's destinations.

## Known limitations

- `off` is the default, so the legacy tables remain the default delivery path.
- There is no route CRUD UI, no automatic destination provisioning for new native
  clients, and no native per-client receipt.
- Questionnaire push is not sent in `on` mode; the destination dispatcher handles
  messages only.
