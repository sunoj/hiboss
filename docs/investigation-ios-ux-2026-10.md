# iOS client UX audit

KB consulted: `kb ios ux swiftui` returned 36 matches, two relevant.
`ai-coding/a-view-the-platform-drops-renders-no-error` (a rendered screenshot is the
only check that fails when a view is absent) — every finding below was checked against
a screenshot, and the tour was extended where a screen had none.
`ai-coding/a-fix-that-constrains-the-container-breaks-at-the-next-call-site` (a shared
component has more than one consumer) — the decision-state fixes live in the shared
`DecisionSettlement` and `InboxStore`, not in one screen. The remaining matches concern
unrelated build, network and on-chain topics.

## Method and evidence

`ios/scripts/ux-tour.sh <dir>` drives `UXTourUITests` on an iPhone 17 simulator
(iOS 27.0) in demo mode (`HIBOSS_DEMO=1`): light and dark, English and Simplified
Chinese, empty Home, two connection states and accessibility text size L. Screenshots
land in `<dir>/shots/`; file names below refer to that directory. "Before" is the
unchanged app; "after" is this branch. Screens that the unchanged tour never reached
were captured from the unchanged app with only the demo services and tour stops below
added.

Each finding was reviewed against `docs/ios-design-contract.md` and
`docs/native-client-attention-model.md`; `file:line` references point at the
unchanged source.

### Tour coverage added

| Gap | Cause | Added |
| --- | --- | --- |
| Pair another device, Device Requests | `ios/App/Settings/SettingsView.swift:47` shows both rows only with a `ConnectionConfig`, which demo mode never sets (`ios/App/HiBossApp.swift:41`). `ios/App/Shell/RootTabView.swift:43` gave `JoinRequestsModel` no service in demo mode, so the list would stay in `.idle` and show a spinner (`ios/App/Settings/DeviceRequestsView.swift:49`). | `DemoPairingIssuer` and `DemoJoinRequestsAPI` (`ios/App/Preview/DemoDevices.swift`); stops `en-13-pair-device`, `en-14-device-requests`, `en-15-device-request-review`, `en-17-pair-expired` |
| Onboarding | No tour stop launched `HIBOSS_DEMO_ONBOARDING=1`. | `en-00-onboarding`, `xxl-00-onboarding` |
| Connection states on Home | `testTourConnectionStates` captured Messages only. | `conn-failed-01-home`, `conn-connecting-01-home` |
| Failed refresh over loaded rows | No demo state. | `HIBOSS_DEMO_REFRESH_FAILS=1`; `conn-stale-04-messages` |
| Auto-decided history | No demo fixture resolved by a timeout default. | Fixture `a1` with a reply in the historical timeout shape (`auto_default: true`, `source: "api"`); `en-18-auto-decided-detail`, `en-19-resolved-auto-decided` |
| Sign Out | Not reached. | `en-16-sign-out` |
| Progress media | `ios/UITests/UXTourUITests.swift:128` tapped `app.images.firstMatch`, which matched a tab-bar glyph: `en-07-progress-media.png` shows Home. | The stop taps the first feed image by its alt text. |

## Findings

### P0 — wrong or misleading state in the decision flow

**P0-1. A timeout default is presented as the boss's choice.** Fixed.

- Screens: message detail of a resolved decision, Resolved list, session transcript.
- Screenshots: before `en-18-auto-decided-detail.png` ("Selected", "Answered on
  System"), `en-19-resolved-auto-decided.png`; after: the same names show "Auto-selected"
  and "Auto-selected when time ran out" with the auto-select glyph.
- Code: `ios/App/Inbox/MessageDetailView.swift:240` marks the recorded answer
  "Selected"; `:246` words it "Answered on \(source)". `ResolvedDecisionsView.swift:135`
  and `SessionDecisionBubble.swift:51` use the same wording.
- Property: the server records a timeout default as a reply whose metadata carries
  `auto_default: true` (`server/src/routes/message-options.ts:117`). Current replies also
  carry `source: "system"`; replies written before commit `5563a7a` carry
  `source: "api"`, so the source does not identify them. `DecisionSettlement.answeredElsewhere`
  (`ios/App/Inbox/InboxSettlement.swift:16`) treats every source other than `ios` as
  another boss surface, and `resolutionSourceLabel` capitalizes unknown sources
  (`HibossKit/Sources/HibossKit/Domain.swift:226`), producing "Answered on System"
  next to a checkmark. The attention model requires auto-decided items to be labelled
  as such and never rendered as if the boss had chosen.
- Fix: `DecisionSettlement.isAutoDefault`, `attribution` and `symbol` drive all three
  surfaces. The first version classified by `source == "system"`; see audit fix round 1
  for the marker-based version and the remaining surfaces.

**P0-2. Home and transcript choice buttons stay live while a reply is in flight.** Fixed.

- Screens: Home attention rows, session transcript decisions.
- Screenshots: `en-01-home.png`, `en-09-sessions-detail.png`, before and after. A demo
  reply resolves immediately, so the in-flight state is not visible in a still image;
  the unit test below is the evidence.
- Code: `ios/App/Home/HomeAttentionRow.swift:190` and
  `ios/App/Inbox/SessionDecisionBubble.swift:37` build `DecisionOptions` without
  `submitting`, so no option is disabled or shows progress. The row leaves the list only
  after the server answers (`ios/App/Inbox/InboxStore.swift:194`).
- Property: a second tap during the round trip sends a second, competing reply. The
  server reports it as already resolved and
  `ios/App/Inbox/InboxStore+ReplyFeedback.swift:18` shows "That decision was already
  answered elsewhere." although both taps came from this phone. Message detail already
  guarded this with local state (`MessageDetailView.swift:261`).
- Fix: `InboxStore.replying` holds the in-flight choice per decision; Home and
  transcript pass the choice to `DecisionOptions`, which disables every option and shows
  progress on the chosen one. The first version guarded only `replyWithFeedback`; see
  audit fix round 1 for the single admission point.

### P1 — missing information or a flow a boss will hit

**P1-1. An expired pairing code offers no way to request a new one.** Fixed.

- Screen: Settings → Pair another device.
- Screenshots: before `en-17-pair-expired.png` ("Pairing code expired", no button, the
  "scan this code" footer still shown); after: the same name shows "Request a fresh code".
- Code: `ios/App/Settings/PairDeviceView.swift:116` evaluates `model.state(at: .now)`
  for the action section outside the `TimelineView` at `:19`; the footer condition at
  `:23` tests `grant != nil`, which stays true after expiry.
- Property: `DevicePairingModel` publishes nothing when a code expires, so only the
  timeline content re-renders. The action section keeps its "ready" state until the
  boss leaves the screen.
- Fix: one `TimelineView` derives the state once per tick for content, footer and
  action. Test: `DecisionStateUITests.testExpiredPairingCodeOffersAFreshCode`.

**P1-2. Sign Out acts on a single tap.** Fixed.

- Screen: Settings, last row.
- Screenshots: before `en-12-settings-bottom.png`, `en-16-sign-out.png` (the session is
  gone); after `en-16-sign-out.png` (confirmation anchored to the button).
- Code: `ios/App/Settings/SettingsView.swift:119` calls `connection.signOut()` directly.
- Property: `signOut()` deletes the device token and the signing key
  (`ios/App/Connection/ConnectionStore.swift:161`); getting back in needs another
  signed-in device or a Boss Token.
- Fix: a `confirmationDialog` states the consequence. Test:
  `DecisionStateUITests.testSignOutAsksBeforeDeletingTheToken`.

**P1-3. A failed refresh over loaded rows looks like a successful one.** Fixed.

- Screens: Messages, Sessions, Progress (all use `ListStateView`).
- Screenshots: before `conn-stale-04-messages.png` (rows, no sign of failure); after:
  the same name shows a banner between the rows and the tab bar.
- Code: `ios/App/Inbox/ListStateView.swift:23` renders the error only when the list is
  empty; `:34` renders content without it.
- Property: `InboxStore` keeps the previous history and sets `loadError` on a failed
  fetch or reply (`InboxStore.swift:143`, `:164`, `:205`). The toolbar label
  (`ConnectionDot.swift:20`) reflects the event stream, not the fetch, so it can read
  connected while the list is stale.
- Fix: `ListStatePhase.content(staleError:)` and a banner in the bottom safe-area
  inset; a top inset covered the large navigation title.
  Tests: `DecisionStateTests.testListPhaseKeepsRowsAndReportsAFailedRefresh`,
  `DecisionStateUITests.testFailedRefreshKeepsRowsAndSaysTheyAreStale`. Progress passed
  its error only when it had no posts until audit fix round 1.

### P2 — polish

**P2-1. Two side-by-side options take different heights at large text.** Open.
Screenshots `xxl-02-home-scrolled.png`, `xxl-09-sessions-detail.png`: "Coarse grid"
wraps to two lines and its button is taller than "Fine grid". Code:
`ios/App/Decision/DecisionOptions.swift:15` places the two buttons in an `HStack`
sized by each label; the labels do not fill the row height.

**P2-2. Session status words disagree between Home and Sessions.** Open.
Home groups `sessionStatus == "waiting"` under a red "Stopped on you"
(`ios/App/Home/HomeAttentionModel.swift:77`, `HomeAttentionRow.swift:43`); Sessions
shows the same word as an orange "Waiting" and `blocked` as a red "Blocked"
(`ios/App/Sessions/SessionCard.swift:38`). In `en-08-sessions.png` payments-hotfix is
red "Blocked" while `en-02-home-scrolled.png` lists its decision under "Decides for you
soon", and nightly-export is orange "Waiting" in Sessions but red "Stopped on you" on
Home.

**P2-3. Copy Link gives no confirmation.** Open. `en-13-pair-device.png`;
`ios/App/Settings/PairDeviceView.swift:96` writes the pasteboard with no visible or
haptic feedback.

**P2-4. A device request that cannot be approved looks like one that can.** Open.
`en-14-device-requests.png`: `ci-runner` has no verification code; the row
(`ios/App/Settings/DeviceRequestsView.swift:66`) is identical to an approvable one and
the reason appears only in the review sheet.

**P2-5. The iOS i18n audit reported two findings.** Fixed.
`ios/App/Shell/RootTabView.swift:76` rendered a `String` through `Text(_:)` (catalog
lookup of runtime text), and an allowlist entry for `HomePanelWall.swift` no longer
matched any code. With `--stringsdata`, the `HiBossBrandIcon.swift` entry was also
stale: neither target's compiler output extracts that key.
`ios/scripts/i18n-audit.py` now reports 0 findings in both modes.

**P2-6. `MessageCard` has no call sites.** Fixed. `MessageCard` and `ReplySheet` had no
call sites; each carried its own answer wording, and `ReplySheet` its own in-flight
state. Both are deleted.

### Needs server

No finding in this audit requires a server change. P0-1 relies on the existing
`auto_default: true` marker of timeout-default replies.

## Audit fix round 1

An independent audit of commit `bc0fd81` returned FIX. Changes:

**Automatic marker (audit P0-1, P0-3).** `MessageMetadata.isAutoDefault` decodes
`auto_default` (`HibossKit/Sources/HibossKit/MessageMetadata.swift`); the source is not
consulted. `SessionEvent.isAutoDefaultReply` reads the same key from the transcript
payload's message metadata (`server/src/session-events.ts:29` includes it). The live
option stream carries no metadata: the server maps `auto_default: true` to source
`system` and emits `system` for nothing else
(`server/src/routes/boss-option-stream.ts:183`), so `OptionResolution.isAutoDefault`
reads that encoding until the persisted reply replaces it on the next history load.
`DecisionSettlement` stores the flag and is built only through `init?(reply:)` and
`init?(resolution:)`, which message detail, the Resolved list, transcript settlements
and history reloads all use. The transcript draws an automatic reply as
`SessionTranscriptItem.automatic` with the settlement's glyph and attribution instead of
an outgoing boss bubble. Tests: `AutoDefaultMarkerTests` (HibossKit: historical
`{auto_default: true, source: "api"}`, current `{auto_default: true, source: "system"}`,
`source` alone, transcript payload), `DecisionStateTests` (history reload, a boss choice
equal to the default), `DecisionStateUITests.testTimeoutDefaultIsNotShownAsTheBossChoice`
and `testAutomaticReplyInTheTranscriptIsNotTheBossSpeaking`.

**One admission point (audit P0-2).** `DecisionReplyGate`
(`ios/Shared/DecisionReplyGate.swift`) admits at most one reply per decision id. It
records the choice before it suspends and releases it with `defer` on success,
already-resolved, failure and cancellation. `InboxStore.reply` (Home, transcript,
detail), notification actions (`PushManager`) and `RespondDecisionIntent` all submit
through `DecisionReplyGate.shared`; a refused submission returns `.busy` and sends
nothing. `InboxStore.replying` reads the gate, so a reply started from a notification
also disables the in-app buttons. Message detail has no local in-flight state.

**Live Activity outcome (audit P0-3).** `DecisionActivityLink` mirrors the gate onto the
decision's activity: `ContentState.submitting` disables both buttons while any surface
sends, a failure re-enables them, and a settled reply ends the activity with
`DecisionCompletion`. An already-resolved reply reads the recorded winner from message
detail and shows "Auto-selected when time ran out" when it carries the marker, else
"Already answered elsewhere." The intent no longer ends the activity unconditionally.

**Progress stale banner (audit P1-4).** `ProgressFeedView` passes `loadError` for
populated lists. Test: `DecisionStateUITests.testFailedProgressRefreshKeepsPostsAndSaysTheyAreStale`.

**Tests (audit P1-5).** `HeldReplyAPI` holds each reply in its own slot until released.
`DecisionReplyGateTests` cover a second tap, detail during a Home reply, a
notification/intent submission while the app replies, independent decision ids, failure
with retry, cancellation, and republishing to observers. Each waits on a bounded poll and
releases the fake before awaiting, so removing the guard fails three tests in under a
second instead of hanging (checked by deleting the guard line).
`DecisionStateUITests.testInFlightReplyDisablesTheButtonsOnHomeAndInDetail` holds a demo
reply for eight seconds (`HIBOSS_DEMO_REPLY_DELAY_MS`) and asserts the options are
disabled on Home and in detail.

## Re-audit round: accessibility-size test and guard-test quality

KB consulted: `kb isHittable tab bar floating swipe` — no direct match.

**`testManyOptionsRemainReachableAtAccessibilityTextSize` failure.** The tap never
reached the button, so the reply gate was never entered. Evidence is from the failing
run's result bundle (iPhone 18 Pro, 85 s): the synthesized tap was at (29.0, 778.7) on
a 402 × 874 screen. That is the top-left corner of a sliver of about 12 pt of "Fail over to
Adyen" left above the floating tab bar, outside the capsule's hit shape. Screen-recording
frames at the tap (36.75 s) and 0.8 s later are identical. The sibling options of the
same decision stay at full contrast, and `DecisionOptions` disables every option of a
decision while the gate holds a reply for it. The swipe loop stopped at the first swipe
that made the option "hittable", which is the moment it enters at the bottom edge,
under the bar. Where it lands depends on swipe distance, so the same build passed
on iPhone 17 (single and full suite) and on iPhone 18 Pro (single). No product change
was needed. The test now drags the option fully above the tab bar with held,
momentum-free steps. It asserts the option is clear of the bar and that the answered
decision leaves Home within 5 s, then keeps its original count assertion.

**Release race in `HeldReplyAPI`.** `release()` now resolves every reply recorded so far,
including one recorded but not yet suspended (kept as an early result). Every gate test
releases only after the fake has recorded the reply, and awaits through `Pending.settled()`.
That call waits about two seconds, then cancels the work and fails instead of hanging.

**Real entry points.** `DecisionEntryPointTests` calls `PushManager.handle(_:)` and
`RespondDecisionIntent.perform()` unmodified. Both now obtain their API from
`HiBossStore.replyAPI`, which defaults to `bossAPI()` and is replaced only by tests, because
the unit-test host cannot write the Keychain (`-34018`). `PushActionRequest` and
`handle(_:)` became internal for the test. `DecisionActivityLink.completion(of:after:choice:api:)`
is the extracted choice of Live Activity outcome. `DecisionStateTests` checks it against a
recorded `auto_default` marker, a marker-less `system` source, an unreadable detail, this
device's choice of the default, and a failure.

Mutation checks (reverted): routing either entry point around the gate fails both entry
tests; checking `source == "system"` instead of the marker fails the completion test;
deleting the gate's guard fails four tests. Every failure took under 0.1 s.

Verification for this round: the single test passes on iPhone 18 Pro (60.1 s);
`HiBossTests` 126 tests, 0 failures; `HiBossUITests` without the tour 33 tests, 0 failures
(iPhone 17). HibossKit and the Mac app are unchanged.

## Verification

- `HiBossTests`: 115 tests, 0 failures.
- `HiBossUITests` without the tour: 30 tests, 0 failures, including
  `DecisionStateUITests` (4).
- `ux-tour.sh`: 11 tour tests passed, 73 screenshots.
- `ios/scripts/i18n-audit.py`: 0 findings, with and without `--stringsdata`.
- HibossKit, the Mac app, the server and the CLI are unchanged.

## Limits of the evidence

- Demo mode has no `ConnectionConfig`, so Settings shows Server "—" and Status "Not
  connected" (`en-10-settings.png`) while the other tabs show data. This is a demo
  property, not a production state.
- Demo history is in fixture order. The server returns history newest first
  (`server/src/routes/boss-api-messages.ts:85`), so the non-chronological Messages
  order in `en-04-messages.png` does not occur against a server.
- The demo's `failed` and `connecting` modes affect only the message stream.
  `conn-failed-01-home.png` therefore shows a normal Home: Home ranks the separate
  required-input stream and reports its errors in the status line under the title
  (`ios/App/Home/HomeView.swift`, `attentionStatus`).
- Push notifications, Live Activities, Dynamic Island and physical-device behaviour are
  not covered by simulator screenshots.
- Text size L in the accessibility range was the largest size in the tour.
