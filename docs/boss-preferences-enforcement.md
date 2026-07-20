# Deferred: enforcing boss preferences at delivery time

**Status: not implemented. Deliberately deferred.**

The macOS client writes `routing` and `quiet_hours` into the free-form
`bosses.preferences` JSON blob via the pre-existing `GET/PUT /api/boss/me/preferences`.
The server **stores** them and **nothing reads them at delivery time**. The two Settings
panes that own these values say so on screen (`SettingsNotAppliedNotice`).

An implementation of the enforcement side was written and then removed before merge after
an adversarial audit returned BLOCK. This document records why, so the next attempt starts
from the findings rather than rediscovering them.

## Why the first attempt failed

The approach hooked preference resolution into `POST /api/messages`, resolving a boss's
routing matrix at the moment an *agent* sends a message. That is the wrong layer, and most
of the findings below follow from it.

### 1. Mis-scoped: per-boss policy applied per-agent-message (architectural)

`resolveBossRoutingChannels` selected every boss matching
`role = 'admin' OR agent_id = ? OR boss_agent_access`, then **unioned** their routing.
Consequences: an admin boss's partial matrix changed delivery for a boss who had configured
nothing, and one boss's explicit mute suppressed another boss's push.

Delivery is currently expressed in terms of an *agent's* `channel_configs`; "which boss
receives this message, and on which of their channels" is not modelled. Until that is,
per-boss notification policy has nowhere correct to live. **Fix this before anything else
— the remaining items are comparatively mechanical.**

### 2. `api` is not a real channel

`channel_configs` accepts only `discord`, `telegram`, `email` (`migrations/0001_init.sql`).
The design's API column therefore had no backing row: selecting `api` alone left
`messages.channel = NULL`, and *deselecting* it disabled `notifyBossAgents`, killing
boss-agent callbacks and iOS/APNs push. Native-client delivery needs to be a first-class
preference independent of `channel_configs`.

### 3. Legacy `quiet_hours` shape is still actively written

`dashboard.html` (~line 1541) sends the old `quiet_hours: { start, end }` form, and
`getAgentQuietHoursEnd` still reads `$.quiet_hours.start/end`. Any strict validator on
`PUT /me/preferences` breaks the web dashboard's quiet-hours save. Validating only the
incoming payload is *not* sufficient — a live client produces the legacy shape. Migrate the
dashboard and the stored rows together, or accept both shapes explicitly.

### 4. `high` priority would silently start being deferred

Today `isUrgent = critical || high` and quiet hours apply only when `!isUrgent`, so `high`
is never deferred. Routing boss quiet hours through all priorities with only `critical`
bypassing changes that. Either keep `high` exempt or make it an explicit, announced change.

Note the design mock contradicts itself here: the Notifications pane says "critical & high
always break through" while the Quiet Hours pane says "Silence normal & low; critical still
alerts." Resolve this with the user before implementing.

### 5. Quiet-hours fan-out can double-deliver

Enqueueing every channel config (rather than the first) inserts multiple `delivery_queue`
rows for one message. `scheduled.ts` selects by queue `id` and `markMessageDelivered` does
not check prior delivery; there is no unique constraint on `(message_id, channel)`.

### 6. Overnight quiet windows check the wrong day

`days` is matched against the *current* local weekday. For a window like
`22:00 → 08:00 days:[Mon]`, the 01:00 Tuesday continuation is not recognised as part of
Monday's window. Semantics must key off the window's start day.

## What to keep from the attempt

The typed preference schema was sound and is worth restoring from git history:
per-priority `routing` (`discord | telegram | api`) and
`quiet_hours { enabled, start, end, timezone, days, critical_bypass }`.
`HibossKit/Sources/HibossKit/BossPreferences.swift` already models exactly this and
round-trips unknown channels and priorities intact, so an older client cannot erase a
channel it does not understand — preserve that property in any server-side validator.

Per-priority **alert sound** is client-side only and must never be sent to the server.
