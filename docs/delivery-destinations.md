# Delivery destinations

Discord and Telegram boss channels were removed by migration `0072_remove_chat_channels.sql`.
Boss messages and replies use HiBoss clients on iOS, macOS and the web console.
The Worker binding `DESTINATIONS_MODE` selects how native notifications are delivered.

## Modes

An absent or unrecognized value resolves to `off` (`server/src/delivery/types.ts`).

| Mode | External delivery | Destination records | Cron |
| --- | --- | --- | --- |
| `off` | Native notifier and quiet-hours queue | None | Legacy delivery queue |
| `shadow` | Identical to `off`; destination changes have no delivery effect | Queued observations plus mismatch audits | Legacy queue only |
| `on` | Enabled native destinations of accessible bosses | Per-destination attempts, external ID, result and quiet deferral | Destination retries only |

In `on` mode, destinations carry new sends and agent-to-boss replies.
Agent-to-agent and boss-as-agent callbacks keep their semantics; APNs is excluded from
the legacy notifier. The destination resolver fans out across eligible boss destinations.

Shadow rows have `status='queued'`, `attempts=0` and `next_attempt_at=NULL`. They never
send, even after switching to `on`. A shadow recording error is logged without changing
the legacy response or sends. Shadow audits (`audit_log.action = 'destination_shadow'`)
use fingerprints for effective targets.

Switching from `on` to `off` restores legacy delivery for new messages; `on`-mode retry
rows pause until `on` is restored. Shadow rows are never replayed. `on` leaves legacy
queue rows untouched, so drain the legacy queue before enabling it.

## Destinations and access

- An admin boss can receive messages from every agent. Managers and viewers receive
  messages from agents granted to them.
- Each iOS/macOS client has a `native_live` destination; each push device has an `apns`
  destination referencing its device ID. Revoked clients and removed devices are
  excluded when resolving or retrying.

## Quiet hours, grouping and retries

Thresholds are `low < normal < high < critical`. Quiet hours apply only to normal and low
priority in every mode; high and critical bypass them. An enabled destination stays
eligible during quiet hours with its own due time. `honours_quiet_hours=false` opts a
destination out of quiet hours entirely.

Eligible destinations across bosses collapse by effective external target: device
token for APNs or client ID for native live. Each target key has a unique per-message claim. The earliest due time
wins (immediate beats deferred), then destination ID. Only the canonical row has a retry
schedule and attempt count; duplicates reference it through `merged_into` and copy its
status and external receipt. Retries re-resolve the group, so an eligible shared
destination can replace a disabled canonical one. Changing the effective target cancels
its retry. Deleting a destination cascades its delivery rows.

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

- `GET /api/boss/destinations` lists the caller’s native destinations and the effective mode.
- Managers and admins can `PATCH` `enabled`, `min_priority`, `honours_quiet_hours` and
  `label`, and `DELETE` their own destinations. Viewers have read-only access.
- `POST /api/boss/destinations/:id/test` requires ownership and a non-viewer role and
  returns 409 unless the mode is `on`. It sends a probe to the base destination, ignoring
  thresholds and quiet hours, without inserting a message. Native live destinations have
  no push adapter and return 409; adapter failures return a sanitized 502.

The web console's Delivery page manages the current boss's destinations.

## Known limitations

- `off` is the default, so the legacy tables remain the default delivery path.
- Native streams do not report per-client receipts.
- Questionnaire push is not sent in `on` mode; the destination dispatcher handles
  messages only.
