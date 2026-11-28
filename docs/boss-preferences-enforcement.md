# Boss preferences at delivery time

The native clients write notification preferences into the free-form
`bosses.preferences` JSON blob via `GET/PUT /api/boss/me/preferences`.
Delivery reads the following preferences:

- **Quiet hours.** On the legacy send path, `getAgentQuietHoursEnd`
  (`server/src/routes/quiet-hours.ts`) finds the latest quiet-hours end among the bosses who can
  see the agent; a `normal` or `low` agent-to-boss send is queued in `delivery_queue` until then,
  including sends with no legacy channel config. Those sends use an internal API queue entry;
  the cron drain delivers the same boss-agent callback and push an immediate send gets.
  On the destinations path, `destinationQuietEnd` (`server/src/delivery/destinations.ts`)
  defers each boss destination that honours quiet hours. Both read the flat
  `quiet_hours_start/end` and the nested `quiet_hours { start, end, timezone, enabled }` shapes,
  skip `enabled: false`, and never defer `high` or `critical`.
- **Native clients.** HibossKit decodes both quiet-hours shapes once, with flat start/end
  taking precedence, nested timezone then top-level timezone then UTC, and missing `enabled`
  treated as on. Missing start/end do not create a window. Invalid timezones fall back to UTC.
  Mac Island decisions and sounds hold `normal` and `low` during that window, including with
  `decision_alerts` on; `high` and `critical` bypass it. `days` and `critical_bypass` do not alter
  the server's current quiet-hours rule.
- **Push presentation.** `prepareBossPush` (`server/src/push/boss-payload.ts`) reads
  `decision_alerts`, `private_push` and the push-tier overrides per device.
- **Native delivery.** The per-priority `routing` matrix was removed with the Discord and
  Telegram boss channels. Boss notifications are delivered through HiBoss clients. Native clients
  ignore any stored `routing` key and omit it from preference updates.

## Quiet-hours design findings

### Stored legacy `quiet_hours` preferences

The retired embedded dashboard wrote `quiet_hours: { start, end }`, and stored preferences
can still use this shape. `getAgentQuietHoursEnd` continues to read
`$.quiet_hours.start/end`. Validators must account for existing records even though the
embedded browser UI is no longer served.

### `high` priority would silently start being deferred

Today `isUrgent = critical || high` and quiet hours apply only when `!isUrgent`, so `high`
is never deferred. Routing boss quiet hours through all priorities with only `critical`
bypassing changes that. Either keep `high` exempt or make it an explicit, announced change.

Note the design mock contradicts itself here: the Notifications pane says "critical & high
always break through" while the Quiet Hours pane says "Silence normal & low; critical still
alerts." Resolve this with the user before implementing.

### Quiet-hours fan-out can double-deliver

Enqueueing every channel config (rather than the first) inserts multiple `delivery_queue`
rows for one message. `scheduled.ts` selects by queue `id` and `markMessageDelivered` does
not check prior delivery; there is no unique constraint on `(message_id, channel)`.

### Overnight quiet windows check the wrong day

`days` is matched against the *current* local weekday. For a window like
`22:00 → 08:00 days:[Mon]`, the 01:00 Tuesday continuation is not recognised as part of
Monday's window. Semantics must key off the window's start day.

Per-priority **alert sound** is client-side only and must never be sent to the server.
