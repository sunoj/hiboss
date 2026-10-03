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
| Auto-decided history | No demo fixture resolved by a timeout default. | Fixture `a1` with a `system` reply; `en-18-auto-decided-detail`, `en-19-resolved-auto-decided` |
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
- Property: the server records a timeout default as a reply whose metadata `source`
  is `system` (`server/src/routes/message-options.ts:117`, the only writer of that
  source). `DecisionSettlement.answeredElsewhere`
  (`ios/App/Inbox/InboxSettlement.swift:16`) treats every source other than `ios` as
  another boss surface, and `resolutionSourceLabel` capitalizes unknown sources
  (`HibossKit/Sources/HibossKit/Domain.swift:226`), producing "Answered on System"
  next to a checkmark. The attention model requires auto-decided items to be labelled
  as such and never rendered as if the boss had chosen.
- Fix: `DecisionSettlement.isAutoDefault`, `attribution` and `symbol` drive all three
  surfaces. Tests: `DecisionStateTests.testSystemReplyIsAnAutoDefaultNotAnAnswerFromElsewhere`,
  `DecisionStateUITests.testTimeoutDefaultIsNotShownAsTheBossChoice`.

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
- Fix: `InboxStore.replying` holds the in-flight choice per decision;
  `replyWithFeedback` ignores a second tap; Home and transcript pass the choice to
  `DecisionOptions`, which disables every option and shows progress on the chosen one.
  Test: `DecisionStateTests.testSecondTapWhileReplyIsInFlightSendsNothing`.

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
  `DecisionStateUITests.testFailedRefreshKeepsRowsAndSaysTheyAreStale`.

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

**P2-6. `MessageCard` has no call sites.** Open. `ios/App/Inbox/MessageCard.swift`
still carries its own "Answered on" wording; no view constructs it.

### Needs server

No finding in this audit requires a server change. P0-1 relies on the existing
`source: "system"` marker of timeout-default replies.

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
