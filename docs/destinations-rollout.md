# Destination delivery rollout — phases 2a–2b

Apply migration `0040_destinations.sql` before deploying this server. It adds five
tables, indexes, and a backfill; it does not alter `messages` or delete legacy data.
Apply additive migration `0041_destination_targets_external_accounts.sql` before the
phase 2b server. It adds external identities and canonical delivery target claims.
Apply `0042_provider_credentials.sql` before the FIX-round server. It backfills
`credential_hash` as SHA-256 of the UTF-8 effective credential: nonempty webhook URL,
otherwise bot token (empty string only for credential-less legacy rows). It retains
the smallest provider ID per hash, repoints all destinations, and removes duplicate
provider rows. Destination IDs, routes, attribution, and delivery history remain intact.
The unique hash index protects API writes; a second unique expression index prevents
direct SQL writers from bypassing uniqueness with an absent or incorrect hash.
The SQL backfill uses portable integer/JSON operations, so Wrangler runs it without
exporting credentials or requiring a separate application backfill command.
This change is committed locally only. Deployment and the production comparison
week are separate operational steps.

## Modes

Set the Worker environment binding `DESTINATIONS_MODE` to one of these values.
An absent or unrecognized value resolves to `off`. No Wrangler default is changed.

| Mode | External delivery | Destination records | Cron |
| --- | --- | --- | --- |
| `off` | Existing agent channel selection, quiet-hours queue, and APNs behavior | None | Existing delivery queue |
| `shadow` | Identical legacy delivery; boss destination changes have no delivery effect yet | Queued observations plus mismatch audits | Existing queue only |
| `on` | Enabled destinations of all accessible bosses; channel argument is a hint | Per-destination attempts, external ID, send result, and quiet deferral | Destination retries only |

On mode uses destinations for new sends, agent-to-boss replies, and forwards.
Agent-to-agent callbacks retain their existing semantics. Boss-as-agent callbacks
also remain supported; APNs is excluded from the legacy notifier in on mode.
Normal/low legacy messages select one channel; urgent legacy messages fan out.
The new resolver intentionally fans out across every eligible boss destination.
Differences due to that ownership change must be reviewed during comparison.

Shadow inserts have `status='queued'`, `attempts=0`, and `next_attempt_at=NULL`.
They never send, even after switching to on. A shadow recording error is logged
without changing the legacy HTTP response or sends. Monitor those errors alongside
coverage; absence of mismatch audits alone does not establish parity.

## Backfill and routing choices

- Providers deduplicate by provider plus webhook URL, falling back to bot token.
  Credentials remain server-side; provider APIs return only ID, provider, label,
  and creation time. Destination targets cannot inject credentials.
- An admin receives destinations from every agent; managers/viewers only from
  their grants. Destinations deduplicate by boss/provider/chat or channel. Mixed
  enabled values collapse with OR; uniform values are preserved.
- Session routes retain Discord threads, Telegram topics, and config topic fallback.
  Config-only topics use the agent name as a temporary text project scope. Conflicts
  at that scope choose the first config ID deterministically.
- Lookup prefers session, then project, then agent-name fallback, then unscoped route.
  Project text comes from the explicit resolver input or the session label prefix.
  Missing routes use the destination target. New on-mode threads are not automatically
  created; provision routes explicitly. Legacy thread creation remains in off/shadow.
- The migration does not invent default inbound agents for shared chats. Configure
  `inbound_routes` explicitly; only on mode consults them. Off/shadow query legacy
  routing tables only. Priority descending then route ID selects the first
  matching pattern. A NULL pattern is a catch-all. Invalid patterns are skipped.
  Unmatched traffic retains the existing channel/session lookup.
- Every existing iOS/macOS client has a `native_live` inventory destination; every
  existing push device has an `apns` destination referencing its device ID. Revoked
  clients and removed/reparented devices are excluded when resolving or retrying.

## Quiet hours and retries

Thresholds are low < normal < high < critical. Enabled destinations remain eligible
during quiet hours, with their own due time. The existing timezone-aware calculation
is reused. Quiet hours apply only to normal/low priority in every mode; high/critical
bypass them exactly as legacy delivery does. Set `honours_quiet_hours=false` to opt
a destination out of quiet hours entirely, including normal/low messages.

Phase 2b collapses eligible destinations across bosses by effective external target:
effective credential hash plus chat/channel and thread for Telegram/Discord, device token for APNs,
and client ID for native live. SHA-256 target keys have a unique per-message claim.
The earliest quiet-hours due time wins (an immediate destination wins over deferral),
then destination ID breaks ties. Only the canonical row has a retry schedule; duplicates
reference it through `merged_into` and copy its status and external receipt. The canonical
row carries attempt counts. Shadow uses the same grouping but never schedules sends.
Send grouping and shadow comparison call the same credential/target key helper;
provider row IDs, labels, app IDs, and unused bot tokens behind webhooks do not split a target.
Retries re-resolve the group, so an eligible shared destination can replace a disabled
canonical destination. Changing the effective target cancels its existing retry.
Deleting a canonical destination also cascades its merged delivery history.

Each external attempt atomically claims its row for five minutes. A failed send
retries after one minute, then two minutes, with three total attempts maximum.
Cron rechecks access, enabled state, client/device ownership, quiet hours, and expiry.
Exhausted/ineligible rows become terminal failures with NULL `next_attempt_at`.
External acceptance records `sent`, not a human receipt. Error text is sanitized so
provider URLs/tokens cannot leak into delivery records.

Providers do not offer an atomic transaction with D1: a process failure after provider
acceptance but before recording success can duplicate a retry. The lease prevents
ordinary overlapping cron attempts; it cannot guarantee exactly-once external sends.
APNs destination priority controls eligibility, while existing privacy/sound preferences
still shape the payload. Native live rows stay queued without retry time: existing
streams expose stored messages, and no per-client receipt is claimed.

## One-week comparison

Keep legacy configs in place, deploy `shadow`, and record the start time. Record
every mode change operationally. The SQL below assumes `:start`/`:end` are bound
to that shadow window; replace them with quoted UTC timestamps in the D1 console.

```sql
-- Overall coverage: zero-destination messages legitimately have no delivery rows.
SELECT COUNT(*) AS messages,
       SUM(EXISTS (SELECT 1 FROM message_deliveries d WHERE d.message_id = m.id))
         AS messages_with_destinations
FROM messages m WHERE direction = 'agent_to_boss'
  AND created_at >= :start AND created_at < :end;

-- Mismatch rate by agent and priority (chat sets are deduplicated across bosses).
SELECT m.agent_id, m.priority, COUNT(*) AS messages,
       SUM(EXISTS (SELECT 1 FROM audit_log a
         WHERE a.action = 'destination_shadow' AND a.resource_id = m.id)) AS mismatches
FROM messages m WHERE m.direction = 'agent_to_boss'
  AND m.created_at >= :start AND m.created_at < :end
GROUP BY m.agent_id, m.priority;

SELECT created_at, resource_id AS message_id,
       json_extract(details, '$.legacy_chats') AS legacy_chats,
       json_extract(details, '$.destination_chats') AS destination_chats
FROM audit_log WHERE action = 'destination_shadow'
  AND created_at >= :start AND created_at < :end ORDER BY created_at;

-- Inspect per-destination attempts after enabling on.
SELECT d.status, d.last_error, COUNT(*) AS deliveries
FROM message_deliveries d WHERE d.created_at >= :start
GROUP BY d.status, d.last_error;

SELECT COUNT(*) AS pending_legacy FROM delivery_queue
WHERE status IN ('pending', 'processing', 'failed');
```

Audit sets contain SHA-256 fingerprints of provider credentials plus effective chat/channel
and thread IDs. Sets collapse shared-boss multiplicities and preserve distinct threads.
Credentials and device tokens are never placed in the audit.
Compare routing, expected boss fan-out, disabled configs, quiet deferrals, and APNs
eligibility separately. Target-set parity does not verify message text, media, device receipts, or
provider availability. Automated shared-target adapter-call tests cover duplicate sends. Review route inventory too.

Drain or explicitly disposition the legacy queue before enabling on. On leaves old
queue rows untouched. Switch to `off` to restore legacy delivery for new messages;
on-mode retry rows pause until on is restored. Do not replay shadow rows. Inspect
outstanding real retries before resuming to avoid delivering stale work.

## API and deferred work

`GET /api/boss/destinations` lists only the caller's destinations with provider labels,
route counts, the effective mode, and credential-free provider choices. Managers/admins can POST Telegram/Discord destinations using an
existing provider, PATCH enabled/min_priority/honours_quiet_hours/label, and DELETE
their own destinations. PATCH booleans are JSON booleans. Viewers are read-only.
Even admins cannot mutate another boss's destination through this API.
`GET/POST /api/boss/providers` is admin-only. New APIs accept no email kind/provider.
Duplicate effective credentials return 409, including simultaneous creates and a
different label/app ID. Neither success nor conflict responses contain credentials
or their hashes. Select the existing provider when creating another destination.

Existing `/api/bosses` HTTP contracts match `37ce778`: schema-generated 32-hex IDs,
raw preference strings after PATCH, unchanged trimming and validation order, and
plain-text validation errors. Non-string PATCH names/roles are ignored; invalid
role strings still return `400 invalid role` without trimming. The existing JSON
`403 {"error":"admin required"}` authorization response is preserved. POST identity
conflicts now return text 409 instead of an uncaught 500, an intentional improvement.
PATCH constraint failures retain the parent's 500 and roll back identity writes.
The shared preference validator rejects `preferred_channel` and `notify_priorities`
on both admin PATCH and self `PUT /api/boss/me/preferences`; accepted merges prune
previously stored removed keys. Quiet-hours validation is shared by both paths.
CLI argument names, defaults, and output remain unchanged except the two removed
flags/help entries. A timezone-only CLI update remains a successful empty-preference
merge, and a successful PATCH with string preferences prints no preference lines.

`POST /api/boss/destinations/:id/test` requires ownership and a non-viewer role, and
returns 409 unless mode is `on`. It sends an explicit probe to the base destination,
ignoring delivery thresholds/quiet hours, without inserting a message. Native live
streams have no push adapter and return 409. Channel and APNs probes return a receipt
when available; adapter failures return a sanitized 502.

The console `/notifications` page replaces Channels in navigation, showing only the
current boss's destinations. `/channels` remains reachable until 2c. Administrators
can create providers with write-only credentials; managers use safe provider choices.

`GET/POST /api/boss/me/external-accounts` and `DELETE /api/boss/me/external-accounts/:id`
manage only the caller's identities; viewers are read-only. Admins use the same CRUD
under `/api/bosses/:bossId/external-accounts`. Provider/user pairs are globally unique.
Inbound Telegram and Discord interactions prefer this table, falling back to old boss
columns only when the pair is absent. Existing admin boss identity edits synchronize
both stores atomically. Deletion clears a matching old column to prevent fallback
recognition. Those columns remain until phase 2c.

Route CRUD UI, automatic destination provisioning for newly registered native clients,
native banner filtering/receipts, legacy message edit/reaction receipt adoption, CLI
channel-management changes, and removal of `channel_configs`,
`routing_rules`, and `delivery_queue` remain deferred. Deleting a destination cascades
its routes and delivery rows; export any audit evidence needed before deleting it.

All E2E and full server suite execution takes place on an authorized grok host in an
isolated temporary checkout. Live Telegram/Discord/APNs delivery and the production
one-week comparison are not performed by the automated suite.
