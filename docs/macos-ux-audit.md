# macOS Client UX Audit — 2026-10-02

Audit of the current native macOS client (`macos/`, shared code in `HibossKit/`) against
[`macos-design-v2.md`](macos-design-v2.md), [`macos-information-redesign.md`](macos-information-redesign.md)
and [`native-client-attention-model.md`](native-client-attention-model.md). These docs were
treated as claims to check, not as facts. Every finding here was traced in code, and most
were also observed in a native render or a recorded state transition.

KB consulted: `a-view-the-platform-drops-renders-no-error`. Code and tests cannot prove
what the host draws, so each visual claim below cites a render, and anything that looks
like a capture artifact is listed as unverified.

## Method

- **Baseline:** `swift test` in `macos/` ran 175 XCTest tests with 0 failures.
- **Render harness:** a copy of the `macos/` and `HibossKit/` packages, with extra test files
  outside the repository. The harness hosts the real `MainView`, `SettingsScene`,
  `IslandView`, `HistoryMessageDetail` and `DashboardPanelDetail` in offscreen titled windows
  and captures each one with `cacheDisplay`.
  - All data is synthetic: an in-memory token store, a throwaway `UserDefaults` suite, and
    scripted `BossServing`, `PanelsServing` and `QuestionnaireServing` fakes.
  - `HIBOSS_PANELS_DEMO=1` supplies the panel fixtures.
  - The harness makes no network calls, never touches the Keychain or the app's own defaults,
    and never launches the installed app.
  - Run: 9 tests, 0 failures, 33 PNGs.
  - Captured sizes: 1320×820, 1100×700, 760×480 and 480×400 (the minimum), light and dark.
  - Captured states: disconnected, populated, refresh failed, token rejected, Settings,
    Island, and panel questionnaires.
- **Not verified live:** real pointer, keyboard and VoiceOver interaction, the menu-bar status
  item, the Island panel's on-screen position and animation, and multi-display behaviour. All
  four of the harness's accessibility `press` lookups returned false or not found, so the
  inspector opened by a click was not rendered.

Severity: **P0** means false confidence in a decision or an unreachable primary surface.
**P1** means a wrong or missing state that the boss will hit. **P2** means hierarchy,
consistency or polish.

## State matrix (observed)

| State | Overview / Dashboard | Needs You | History | Settings | Island |
|---|---|---|---|---|---|
| Disconnected | Notice + Settings ✓; panels show an orange error + second empty state ✗ | "Connect to HiBoss" ✓ | same ✓ | "Disconnected · daemon idle"; footer reads "Listening" ✗ | hidden ✓ |
| Loading | dashes ✓ | spinner ✓ (idle state not covered) | spinner ✓ | — | — |
| Empty | "Nothing needs you" ✓ (ignores questionnaires ✗) | settled empty ✓ | per-scope ✓ | — | — |
| Refresh failed, cached rows | sidebar notice only ✗ at <760 pt | no failure signal ✗ | no failure signal ✗ | — | — |
| Token rejected | message + Try again ✓; toolbar flaps ✗ | — | — | reason not shown ✗ | — |
| Expired / resolved | — | removed ✓ | "Auto-decided" for unanswered expiry ✗; chosen answer missing ✗ | — | 3 s resolved card ✓ |
| Long content | wraps, 2-line preview ✓ | scrolls, composer pinned ✓ | ✓ | — | scrolls ✓ |
| 480×400 | single column ✓ | composer visible, timing below the fold ~ | filter collapses to overflow ~ | min 820×560 | 420 pt fixed |
| Dark | tiles ✓; sidebar text unverified | ✓ | ✓ | ✓ | always dark ✓ |
| Keyboard | ⌘, ⌘↩ only; no ⌘R; history detail is double-click only ✗ | ⌘↩ ✓ | ✗ | — | none |

## Confirmed failures

### P0-1 — "Open HiBoss…" in the status menu cannot find the main window
`HibossIslandApp.swift:170-173` looks the window up by `title == productName` ("HiBoss").
`MainView` sets `navigationTitle` to the destination. The harness read `window.title` as
"Dashboard" and "Needs You", never "HiBoss". In Island mode with the status item shown,
`HibossIslandApp.swift:106-107` sets the `.accessory` activation policy, so there is no Dock
icon either. After the boss closes the main window, nothing in the status menu reopens it.
- **Fix:** open by scene id (`openWindow(id: "main")`, which is already bridged through
  `MessageNotificationNavigation.openWindow`) instead of matching the title.
- **Verify:** a unit test that the status action calls the bridged opener. Then a live
  check: close the window and reopen it from the menu.

### P0-2 — Replying to an already-resolved question reports success
`OptionFlowStore.answerHistory` and `send` (`HibossKit/.../OptionFlowStore.swift:155,185`)
discard `ReplyOutcome`, so a 409 `.alreadyResolved` returns `true`. Harness:
`ScriptedBossAPI(replyOutcome: .alreadyResolved)` produced `draft=<cleared> error=<none>`.
The boss's text disappears as if it had been delivered, while another answer actually
resolved the question. This is the same defect as Theme B in the iOS audit.
- **Fix:** return the outcome. On `.alreadyResolved`, keep the draft, show "Already answered
  elsewhere", and refresh history.
- **Verify:** an `AttentionReplyState` test with the scripted 409.

### P1-3 — Unanswered expiry is labelled as a decision
`HistoryMessageLogic.swift:117-128` treats any `status == "expired"` as auto-decided and
appends `defaultOption`. The server now expires abandoned asks "without choosing its
default" (`server/src/abandoned-asks.ts`). The render (Completed, 1100×700) shows
"Should I rename the billing table? — Auto-decided · Keep" for a question that no one
decided. This breaks the attention-model rule "never silently rendered as if the boss had
chosen", in reverse.
- **Fix:** label it "Auto-decided · X" only with a recorded automatic reply identifying X.
  `options_expired` alone also marks abandonment. Otherwise show "Expired · no answer".
- **Verify:** `HistoryLogicTests` cases for both.

### P1-4 — Resolved questions never show what was chosen
The History row (`HistoryRow.swift:75-87`) and the detail (`HistoryMessageDetail.swift:112-123`)
render a replied question's options as neutral chips or empty circles. The boss reply sits
elsewhere in the list as a separate row. Render: the detail for "Merge the dependency bump?"
shows ○ Merge ○ Close. History is meant to answer "who decided it", and it does not.
- **Fix:** resolve the reply by `replyTo` from the loaded history, or from `fetchMessage`
  replies. Mark the chosen option and show its source.
- **Verify:** a detail render plus a logic test.

### P1-5 — A refresh failure is invisible below 760 pt and in content views
When cached rows exist, `AttentionView.swift:25-33` and `HistoryView.swift:72-83` fall through
to the normal list or "Nothing needs you". The only failure signal is the sidebar notice
(`OverviewSidebar.swift:61-69`), and `MainView.swift:157-159` hides the sidebar below 760 pt.
Render (480×400, `historyState=failed`, connection `connected`): Needs You shows no warning,
and the toolbar antenna is green.
- **Fix:** add a content-level inline banner, "Couldn't refresh · showing messages from
  HH:mm" with Try again, in Attention, History and Dashboard.
- **Verify:** a 480×400 render in the failed state.

### P1-6 — Connection shows "Listening" before the server accepts it
`OptionFlowStore.swift:197-199` sets `.connected` as soon as `messageStream()` returns. That
stream is lazy, so no request has succeeded yet. With a stream that rejects the token, the
harness used an accelerated 200 ms retry and recorded 17 transitions in 1 s, 5 of them
`connected`; this does not measure production retry frequency. The default 2 s retry has no backoff
and no auth classification. The toolbar icon (`MainView.swift:97-100`), the status menu label
and the Settings status all flicker to "connected" or "Listening".
- **Fix:** mark the connection connected on the first event or an HTTP 200 from the stream.
  Stop retrying on 401/403 and surface "Token rejected".
- **Verify:** a flow test asserting that no `connected` state appears with a rejecting stream.

### P1-7 — "Nothing needs you" while a blocking questionnaire waits
The Dashboard decision count comes from `AttentionRanking` over messages only
(`OverviewSnapshot.swift:58-63`, `DashboardDecisionsSection.swift:66-68`). Render: the
Decisions heading reads "0 · Nothing needs you" while the panel card beside it reads
"Needs input". The macOS attention subset still uses the priority rule, so a normal-priority
option question from a `working` session appears only under All. The populated fixture
"Which icon set…" is absent from Needs You (4), and iOS Home counts it. The two clients give
the same account different answers to "does anything need me?".
- **Fix:** include `panels.pendingQuestionnaireCount` in the Dashboard decisions status, and
  align the attention subset with iOS (see `investigation-ios-home-attention-update.md`).
- **Verify:** an agreement test with the same fixture on both clients.

### P1-8 — Island content and controls diverge from the live message
`IslandPanelController` shows and sizes the panel for `flow.activeMessage`
(`IslandPanelController.swift:179-196`, `265-268`). `IslandView` renders the top-ranked
attention item instead (`IslandView.swift:33-37`). Skip appears only when those two are the
same message (`IslandView.swift:114-117`). Harness: live "Deploy the preview build?", shown
"Ship release 2.4", and the Skip control is absent.
- A ranked item with more options or media than the live message is drawn in a frame sized
  for the live message. Heights matched in this fixture, so overflow was not observed.
- A choice on a history item goes through `answerHistory`. A failure leaves
  `presentationState` untouched, so no error appears (`IslandView.swift:188-196`).
- **Fix:** compute the frame from the presented item, offer Skip for whatever is presented,
  and route history answers through a state that can show an error.
- **Verify:** render the live-sized frame with a longer ranked item.

### P2-9 — Inline History choices fail silently
`HistoryView.swift:91-93` runs `Task { await flow.answerHistory(...) }` and drops the result.
A failed one-click answer from a list row gives no feedback, and the row is unchanged.
- **Fix:** route the result through `AttentionReplyState` errors keyed by message ID, and show
  them in the row.

### P2-10 — Settings status copy contradicts state
- The footer always reads "Listening" (`SettingsScene.swift:100-104`). Only the circle's fill
  changes, so a disconnected or failed client still says "Listening" (render: failed state).
- The Connection pane says "Disconnected · daemon error" but never shows
  `connectionState.detail`, so "That Boss Token was rejected…" appears nowhere in Settings
  (`ConnectionSettingsPane.swift:86-101`).
- "Daemon" names the CLI's daemon, which this client does not run.
- **Fix:** show state-specific text (Listening / Connecting / Disconnected / Failed) plus the
  failure detail.

### P2-11 — Settings sidebar row with no icon
`SettingsModels.swift:54` uses `desktopcomputer.and.iphone`. `NSImage(systemSymbolName:)`
returns nil for it on this OS, and the Devices row renders without an icon in both
appearances. `laptopcomputer.and.iphone` exists.

### P2-12 — Disconnected Dashboard repeats the same state four times as an error
`PanelsView.swift:24-34` renders `failureMessage` in orange with "Retry panels". Below it,
`PanelWallEmptyState` adds "Panels unavailable" with "Refresh"
(`PanelLifecycleControls.swift:54-59`). Together with the sidebar notice and the Decisions
notice, a first launch shows "connect" four times. Two of them are styled as failures, and
there are two retry buttons for one cause.
- **Fix:** treat `PanelClientError.notConfigured` as a setup state. Show one secondary line
  and no retry.

### P2-13 — Sidebar footer overlaps the session list
`OverviewSidebar.swift:106-116` places the Settings footer in a `safeAreaInset` with no
background. Every populated render shows "Settings" drawn over the last session's agent
name.
- **Fix:** give the inset `.background(.bar)`, or move Settings into the toolbar or the app
  menu, where ⌘, already lives.

### P2-14 — Row timestamps drop the date
`HistoryTimestamp.shortLocalTime` (`HistoryMessageLogic.swift:73-80`) formats with
`date: .omitted`. A message two days old renders as "16:04", the same as a message from
today.
- **Fix:** show the time for today, a weekday within the last week, and a date beyond that.

## Unverified risks (need a live check)

- **Selection rendering:** selected sidebar rows, and the selected segment of the History
  filter, render as solid black or blank pills in the captures. Dark-mode sidebar text
  renders at very low contrast. All three are consistent with `cacheDisplay` dropping
  vibrancy and inactive-window materials. Confirm with a live screenshot before acting.
- **Unlabelled inspector toggle:** a toolbar button with a `sidebar.right` glyph appears on
  every main-window render. It is most likely the `.inspector` toggle. Its effect with
  nothing selected was not exercised.
- **History filter at the minimum size:** at 480×400 the segmented control collapses into the
  toolbar overflow (») and is hard to discover.
- **Keyboard:**
  - Opening History detail is double-click only (`HistoryMessageLogic.detailClickCount`). No
    Return action, context menu or command was found in the code.
  - There is no ⌘R for refresh.
  - The overview tiles use `.buttonStyle(.plain)`. Their focus rings under Full Keyboard
    Access were not observed.
  - History rows use `.accessibilityElement(children: .combine)` around action buttons. The
    VoiceOver reachability of individual choices was not tested.
- **Tile selection contrast:** the selected-tile ring is white at 1.8–2.3:1 against the tile
  colours, below the 3:1 guidance for UI boundaries. The checkmark glyph provides a
  non-colour cue. The ink-on-tile text measures 5.2–7.3:1, and the priority accents measure
  5.1–8.1:1.
- **Island error label:** it is 10 pt `.system(size:)` with `lineLimit(1)`
  (`IslandView.swift:199-206`), so long failure reasons truncate. `.system(size:)` appears
  14 times in Island surfaces (`IslandView`, `OptionSurfaceComponents`), and the type rule in `macos-design-v2.md` names no exemption
  for them.
- **Questionnaire expiry and Select default:** in the harness, an expired questionnaire still
  showed live fields, and a Select with a default rendered blank. Both trace to fixture data:
  expiry is judged against the stub's 2026-09-07 server clock, and the Select option format
  was guessed. They were not reproduced with a live server.

## Refinements

- **Compact attention detail:** at 480×400 the "Will choose / Time left" metadata sits below
  the fold, and only the "default" tag is visible. Put the countdown next to the question
  heading.
- **Toolbar connection item:** it is icon-only with a tooltip, while the design contract asks
  for a symbol and a short label.
- **Dashboard header:** the "Dashboard / Decisions and live panels." header uses about 120 pt
  of a 400 pt window above the first decision.

## Ordered follow-ups

1. Fix P0-1 (open by scene id) and P0-2 (propagate `ReplyOutcome`). Each is small and has a
   unit test.
2. Fix P1-3 and P1-4 together in `HistoryMessageLogic`, using one resolution model:
   answered, auto-decided, or expired without an answer.
3. Fix P1-6 (connection truth), then P1-5 (content-level failure banner) and P2-10 (Settings
   copy). Each depends on the one before it.
4. Fix P1-7, the attention and questionnaire count, as a shared decision across iOS and
   macOS.
5. Fix P1-8 (Island frame and controls follow the presented item) and P2-9 (row errors).
6. Fix P2-11 through P2-14, then the live screenshot pass for the unverified rows above.
