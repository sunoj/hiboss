# iOS UX / Business Audit — 2026-07-24

Read-only audit of the hiboss iOS client across four lenses — **信息完整度** (completeness),
**准确度** (accuracy), **流程 UX** (flow), **中间状态** (intermediate-state handling) — over four
areas (inbox/decision lifecycle, sessions/messages browsing, connection/onboarding/shell,
settings/push/formatting). Findings are clustered by theme; each references `file:line`.

Severity: **P0** = correctness/false-confidence in the core decision flow, **P1** = missing info
or lifecycle gaps a boss will hit, **P2** = consistency/polish.

---

## Theme A — Offline/error masquerades as healthy  *(P0 — surfaced by 3 of 4 audits)*

For a decision-notification tool this is the worst failure mode: a broken connection looks
identical to "nothing needs you."

- `InboxStore.loadError` is set on fetch/reply failure (`InboxStore.swift:76,91,105`) but **no list
  view reads it**. `InboxView` shows `ContentUnavailableView("All clear", "No decisions are waiting
  on you.")`; `MessagesView`/`SessionsView` show "No messages/sessions yet". Only `MessageDetailView`
  consults `loadError`.
- No first-load/loading state: `history` starts `[]`, so **every cold launch flashes "All clear"**
  before the first fetch resolves (`InboxStore.swift:11-16`, `InboxView.swift:56-61`).
- Settings "Status" shows `isConfigured ? "Connected"(green)` and ignores the live
  `connectionState` (`SettingsView.swift:18-21`) — the one screen to check connection actively
  misleads.
- `ConnectionDot` renders `.failed` the same gray as `.disconnected` (`InboxView.swift:118-124`).

**Fix:** thread a load state + `loadError` into all list views (error state w/ retry, spinner
before first load, never "All clear" while failed/disconnected); drive Settings status from
`connectionState`; red tint for `.failed`.

## Theme B — Reply reports success when it didn't  *(P0)*

- **409 "already resolved" is swallowed.** `HibossAPI.reply` returns `ReplyOutcome.alreadyResolved`
  on 409, but `InboxStore.reply` does `_ = try await api.reply(...)` then unconditionally
  `return true` (`InboxStore.swift:100`). `MessageDetailView.submit` / `MessageCard` then fire a
  success haptic and dismiss. If the decision was already answered elsewhere (Telegram, another
  device) or expired, the boss believes **their** choice won when a different answer resolved it.

**Fix:** propagate `ReplyOutcome`; on `.alreadyResolved` refresh + show "Already answered elsewhere"
and let the view re-render into its resolved branch.

## Theme C — Expiry is never enforced locally  *(P0/P1)*

- `InboxStore.pending` only re-evaluates when `history` changes; **nothing fires at the deadline**
  (contrast `OptionFlowStore.scheduleExpiration`). An expired decision keeps live, tappable option
  buttons until an unrelated event/refresh arrives — and tapping it hits Theme B (409 → false
  success). Same in `MessageDetailView.decisionSection`.
- `CountdownText` clamps to 0 and renders **"0:00 left" forever** after expiry, never "Expired", and
  ticks indefinitely; long timeouts render "120:00 left" (no hours) (`CountdownText.swift:14-23`).

**Fix:** mirror `OptionFlowStore.scheduleExpiration` in `InboxStore` (per-deadline task that
re-publishes/prunes); render "Expired" and stop ticking at 0; add hours for long windows.

## Theme D — Auth/token lifecycle  *(P1)*

- `isConfigured` = "has a well-formed token", not "token valid"; `restore()` never verifies
  (`ConnectionStore.swift:30-42`). A revoked token routes straight into the app.
- Stream reconnect is a **fixed 2s loop with no error classification** — a permanent 401 retries
  forever, no backoff, no re-auth prompt (`InboxStore.swift:110-127`).
- Cold launch **flashes the onboarding screen** for configured users (restore is async, no
  "restoring" state) (`HiBossApp.swift:16`, `RootView` gate `:28`).
- Onboarding 401 shows opaque "Server request failed (HTTP 401)." not "token rejected"
  (`ConnectView.swift:35-40`); bare-host URL w/o scheme rejected (`Keychain.swift:76-81`).
- Foreground return doesn't refresh Inbox history or re-kick a dropped stream (only Settings does)
  (`InboxStore.consume` never calls `refreshHistory` on reconnect).

Together A+D: a revoked token yields an app that says "Connected", shows "All clear", and reconnects
forever — zero signal anything is wrong.

## Theme E — Missing context on rows & cards  *(P1 completeness)*

- **No timestamp on any message row** — `HistoryRow` (used by Messages, Inbox "All", both session
  detail surfaces) never shows "when", though `relativeCreatedAt` exists (`HistoryRow.swift:11-35`).
- Detail view **drops the countdown/expiry** a pending card showed, and omits `createdAt`/`mode`
  (`MessageDetailView.swift:62-90`).
- Card omits the **default option** (auto-fires on timeout), **session identity** (which
  worktree/session is asking), and hides the **blocking/async** badge once there are >2 options
  (`MessageCard.swift`).
- `SessionCard` hides agent + branch despite its header claiming to show them
  (`SessionCard.swift:55-66`); `SessionGroup` drops `branch`.

## Theme F — Session browsing divergence  *(P1/P2 flow)*

- **Two different drill-in paths** for the same concept: Sessions tab → `SessionDetailView` sheet →
  tapping a message opens **ReplySheet only** (even for resolved/`boss_to_agent` messages); the
  Sessions `NavigationStack` registers no `navigationDestination`, so from that tab you can never
  reach full `MessageDetailView` (`RootTabView.swift:35-39`).
- `SessionDetailView` holds the group **by value → goes stale**; live arrivals/resolutions don't
  update while open (contrast `SessionMessagesView`, which recomputes from `store.history`).
- Session threads read **newest→oldest top-to-bottom** (reverse of chat convention), worsened by no
  timestamps. "View session" can self-loop and grow the nav stack unbounded.
- Trim mismatch (`.whitespaces` vs `.whitespacesAndNewlines`) can make a deep-linked session filter
  to empty (`MessageDetailView.swift:253` vs `:230`).

## Theme G — Push / quiet-hours server↔client mismatch  *(P0/P1 accuracy — needs SERVER change + deploy)*

- **Quiet-hours timezone dropped → evaluated in UTC.** Server reads `$.timezone` (top level); app
  writes it nested under `quiet_hours.timezone` (`quiet-hours.ts:84`, `BossPreferences.swift:96-101`).
  A Bangkok 22:00–08:00 window fires at 22:00–08:00 **UTC**. UI footer claims "Times are in <tz>".
- **"Mute Notifications" OFF has no effect** — server ignores the `enabled` flag (`quiet-hours.ts`
  never reads it); app still ships start/end.
- **"Let Critical Through" toggle does nothing**, and quiet-hours bypass is hardcoded for high+critical
  (`messages.ts:236` gates on `!isUrgent`), contradicting the "Critical" label.
- Quiet hours only suppress device push when an external channel is also configured
  (`messages.ts:236`) — a device-only boss is pushed through their quiet window.
- Device push ignores the Routing matrix (Routing governs external channels only; not disclosed).

## Theme H — Push registration blind spots  *(P1)*

- APNs token is **only** registered inside the permission-grant callback; an already-authorized user
  (reinstall, restore, OS token rotation) never re-registers and silently stops receiving pushes,
  with no UI path to fix (`PushManager.swift:49`, `AppDelegate.swift:11-17`).
- Settings shows OS auth status only — **no server-registration status**; `register` failures go to
  the log. "Push: Enabled" can be green while the device receives nothing
  (`SettingsView.swift:90-104`).
- Provisional/ephemeral auth is shown as "Enabled/green" though it delivers silently
  (`PushStatusStore.swift:29,37`).

## Theme I — Consistency & polish  *(P2)*

- `ReplySheet` uses the web-palette Theme.* colors (violates the native-first contract) and calls
  `onSend(); dismiss()` synchronously — closes before the network resolves, no in-flight/error state
  (`ReplySheet.swift:17-60`).
- First green/prominent option button implies "recommended" purely by index (`MessageCard.swift:82`).
- Status casing differs (row lowercased vs detail `.capitalized`); duplicate ISO parsers, duplicate
  resolution-source maps, two `MessagePriority` enums; `RelativeTime` drops the year for old items;
  Live Activity ends with no "answered ✓" closure (`DecisionActivityManager.swift:25-36`).

---

## Proposed phases

- **Phase 1 — core correctness / intermediate states (P0):** Theme A (load+error states everywhere),
  Theme B (409 propagation), Theme C (expiry timer + CountdownText). *The heart of "确保中间状态合理".*
- **Phase 2 — auth lifecycle + completeness (P1):** Theme D, Theme E (timestamps + card/detail info).
- **Phase 3 — push/quiet-hours accuracy (P0/P1, server + deploy):** Theme G, Theme H.
- **Phase 4 — session unify + polish (P1/P2):** Theme F, Theme I.
