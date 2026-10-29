# macOS render and update survey

KB consulted: hosted-window toolbar geometry, oversized-window artifacts, and small fixtures hiding
full-data scans. Windows use the visible screen and the production snapshot fixtures.

## Method

Measured on 2026-10-29, Apple M6 / 24 GiB, macOS 27.0.1 (26A434), Apple Swift 6.4.
The table records the tested source commit, independently of the documentation commit.
All windows are real AppKit windows. Main-window hosts request 1320 × 820 content points;
SwiftUI toolbar hosting extends the hosting view to 1320 × 852. Settings hosts are 900 × 712.
Island sizes come from the real controller. The script records actual hosting-view dimensions.

Idle is process user + system CPU from `getrusage(RUSAGE_SELF)` across at least three seconds,
after one second of settling, or five seconds where marked. 100% means one CPU core;
WindowServer/GPU work is excluded. Autonomous timers and session-age expirations remain active;
there are no injected mutations during the idle interval. Expiry-driven store updates can occur.
Update, interaction and scroll columns measure main-thread CPU with `CLOCK_THREAD_CPUTIME_ID`.
Each includes the mutation, 300 ms of run-loop draining and final pending layout/display.
Sleeping does not count as CPU. These are individual observations, not latency percentiles;
background timer ticks can contribute, and work deferred beyond the drain is excluded.
No CPU percentage is asserted, and no layout-call counts are used.

The normal fixture is 30 messages across three sessions. Scale is 2,000 messages across
200 sessions, plus a separate 2,000-message single-session thread. Message bodies and metadata
derive from `PhaseBSnapshotFixtures` and `SessionThreadFixtures`; 20% are decision messages.
Box uses five mixed snapshot items or 500 text references. Progress uses three snapshot posts
or 500 text posts. Panels use one or 50 static metric tiles derived from `StubPanelsService`.
Media is synthetic; the snapshot loopback server supplies question images. No live account is used.

The main-window update installs one arriving message in the injected `OverviewStore`, including
snapshot projection and visible rendering, but excluding network decoding and feed delivery.
Box and Progress refresh through their fixture service with an added item/post. A panel update
changes `/task/done`. Island questions update the visible reply draft through its binding;
the collapsed Island receives a health update. Settings changes the local device label.

Interactions select a session through the native sidebar table, open a Box detail, open a panel
detail, switch Island/window presentation, or toggle the local sound setting. The Settings toggle
is visible only on the relevant pane; other panes measure propagation of that shared setting.
Scroll measures one accepted 300-point native clip-view step. `—` means no scrollable native view
was found or that no interaction was supplied. A sidebar scroll can be chosen when several
scroll views exist; the survey does not identify the chosen viewport in the output.

Attention list/detail and Sessions sidebar/inspector/thread are simultaneous compositions.
History's initial inline threads are collapsed; expanded threads are separately hosted at the real
900-point row width in a 1320-point window, with three or 2,000 replies and bound reply typing.
Projects has no standalone destination in
`OverviewDestination`; its table rows repeat the Today composition with the project/session sidebar.
Today uses preview mode, which suppresses network loading and embedded panel sections; Panels are
measured separately. All nine real Settings panes use the real shell in the local/unpaired state.
Authenticated device lists, pairing sheets, video playback, network latency and full application
launch are outside these numbers. Settings has no data-size axis in the unpaired state.

The only production seam is `SettingsScene.initialPane`, defaulting to `.connection` exactly as
before. Existing callers retain their initial state. No render or update implementation changed.
Survey methods throw `XCTSkip` without `HIBOSS_PERF_SURVEY=1`, preventing routine desktop takeover.

## Measurements

`30/3` and `2000/200` mean messages/sessions. Unmarked rows settle for one second.
All CPU and timing columns belong to the build and commit in that row. `rel` means
`-c release -Xswiftc -enable-testing`; `dbg` means debug with the same testing flag.
Short commit IDs below identify these exact sources:

- `23ba31c7`: `23ba31c760b50b3911f933cd39ae66428bacef3f`
- `11794718`: `117947185c616fa521e8c2f66237ff21dac37ae9`
- `78cb2970`: `78cb29703254b48827ac329544349d18c2545097`

| Surface | Data | Idle % | Update ms | Action ms | Scroll ms | Build | Commit |
|---|---|---:|---:|---:|---:|---|---|
| Empty window before | 0 | 0.08 | 0.23 | — | — | rel | 23ba31c7 |
| Empty window after | 0 | 0.09 | 0.27 | — | — | rel | 23ba31c7 |
| Island collapsed | 0 | 0.09 | 0.62 | 1.17 | — | rel | 23ba31c7 |
| Island short | 2 options | 6.71 | 17.12 | 18.43 | — | rel | 23ba31c7 |
| Island short settled | 2 options; 5s | 0.23 | 8.87 | 12.91 | — | rel | 78cb2970 |
| Island long | 12 options | 6.71 | 17.38 | 28.79 | — | rel | 23ba31c7 |
| Island images | 2 images | 0.36 | 8.77 | 21.48 | — | rel | 23ba31c7 |
| Option window | 2 options | 0.30 | 10.21 | 16.00 | — | rel | 23ba31c7 |
| Today | 30/3 | 0.80 | 15.84 | 116.33 | 1.76 | rel | 11794718 |
| Today | 2000/200 | 24.31 | 242.40 | 388.68 | 31.76 | rel | 11794718 |
| Today settled | 2000/200; 5s | 7.75 | 212.81 | 327.60 | 182.28 | rel | 78cb2970 |
| Attention list/detail | 30/3 | 0.62 | 12.27 | 9.67 | — | rel | 11794718 |
| Attention list/detail | 2000/200 | 1.16 | 113.64 | 35.73 | 16.28 | rel | 11794718 |
| Sessions + inspector/thread | 30/3 | 0.45 | 14.82 | 63.78 | 6.72 | rel | 11794718 |
| Sessions + inspector/thread | 2000/200 | 0.44 | 56.27 | 88.14 | 17.29 | rel | 11794718 |
| Long session thread | 2000/1 | 0.60 | 103.51 | — | 2.36 | rel | 23ba31c7 |
| History list/inline thread | 30/3 | 8.32 | 20.19 | 82.78 | 11.07 | rel | 11794718 |
| History list/inline thread | 2000/200 | 12.44 | 69.80 | 117.95 | 14.51 | rel | 11794718 |
| Expanded History | 3 replies | 0.41 | 4.05 | 225.60 | — | rel | 11794718 |
| Expanded History | 2000 replies | 25.81 | 123.20 | 313.58 | 84.90 | rel | 11794718 |
| Expanded History settled | 2000 replies; 5s | 7.48 | 309.37 | 213.86 | 75.39 | rel | 78cb2970 |
| Box browser | 5 mixed | 2.68 | 59.10 | 45.75 | — | rel | 23ba31c7 |
| Box browser | 500 text | 0.35 | 143.22 | 59.94 | 228.11 | rel | 23ba31c7 |
| Progress | 3 posts | 0.85 | 30.52 | — | — | rel | 23ba31c7 |
| Progress | 500 posts | 1.65 | 65.45 | — | 2.09 | rel | 23ba31c7 |
| Panels | 1 tile | 0.08 | 288.65 | 13.11 | — | rel | 78cb2970 |
| Panels | 50 tiles | 0.33 | 275.82 | 37.90 | 167.46 | rel | 23ba31c7 |
| Projects sidebar / Today | 30/3 | 0.72 | 18.71 | 118.31 | 1.37 | rel | 11794718 |
| Projects sidebar / Today | 2000/200 | 15.30 | 241.42 | 386.33 | 16.96 | rel | 11794718 |
| Settings General | local | 0.08 | 1.99 | 1.52 | — | rel | 23ba31c7 |
| Settings Connection | local | 0.11 | 7.02 | 3.23 | — | rel | 23ba31c7 |
| Settings Devices | unpaired | 0.10 | 1.78 | 1.31 | — | rel | 23ba31c7 |
| Settings Notifications | local | 0.09 | 2.20 | 3.98 | — | rel | 23ba31c7 |
| Settings Routing | local | 0.08 | 13.19 | 3.65 | — | rel | 23ba31c7 |
| Settings Quiet Hours | local | 0.09 | 1.59 | 1.34 | — | rel | 23ba31c7 |
| Settings Presentation | local | 0.09 | 2.86 | 9.73 | — | rel | 23ba31c7 |
| Settings System/Doctor | local | 0.08 | 1.08 | 1.20 | — | rel | 23ba31c7 |
| Settings About | local | 0.09 | 1.11 | 1.65 | — | rel | 23ba31c7 |

| Surface | Data | Idle % | Update ms | Action ms | Scroll ms | Build | Commit |
|---|---|---:|---:|---:|---:|---|---|
| Today | 30/3 | 0.54 | 14.70 | 102.23 | 1.10 | dbg | 78cb2970 |
| Island short | 2 options | 6.21 | 9.34 | 16.66 | — | dbg | 78cb2970 |

These small fixtures do not establish a release/debug multiplier: rendering noise, cold caches
and timer phase dominate several low-cost measurements. No debug value is presented as release.

Actual Island host sizes were 184 × 36 collapsed, 420 × 232 short/window, 420 × 792 long,
and 420 × 388 with images. The five-second rows are separate single-method observations;
they demonstrate settling sensitivity, not confidence intervals or isolated timer A/Bs.

## Findings ranked by visible cost

1. **Large Today updates and navigation consume hundreds of main-thread milliseconds.**
   The settled run spends 212.81 ms updating and 327.60 ms switching sidebar selection.
   The one-second-settled run spends 242.40/388.68 ms. The update stack records
   `OverviewStore.update → OverviewSnapshot.init → TodaySnapshot.init`, followed by
   `TodayDecisionCard.body`. The idle stack names `DecisionDefaultLine`, `TodayActivity` and
   `TodaySummary` leaf closures. `TodayView.swift:60` and `:82` eagerly build `VStack` decision
   content rather than a lazy stack. Snapshot rebuilding and eager decision rendering are confirmed
   contributors; their individual shares are not isolated. The five-second idle result is 7.75%.

2. **Panel numeric animation dominates a single metric update.** A same-commit, one-tile A/B
   measures 288.65 ms normally and 1.01 ms with the test root transaction disabling animations
   (99.65% less main-thread CPU). `PanelTilePreview.swift:73–74` installs `.numericText()` with a
   250 ms animation; no hover/input animation is driven during this update. The 50-tile sample
   contains `NSWindow.layoutIfNeeded → NSView.layoutSubtreeIfNeeded → SwiftUI → AttributeGraph`.
   Animation cost is confirmed; production animation is unchanged. The large wall also spends
   167.46 ms on one scroll step.

3. **Expanded History replies are expensive to update and type into.** The five-second-settled
   2,000-reply run uses 309.37 ms for arrival and 213.86 ms for typing; the earlier observation
   uses 123.20/313.58 ms. Samples name `HistoryReplies.body` and its nested reply closures.
   `HistoryReplies.swift:12–13` eagerly renders every reply in a `VStack/ForEach`.
   This confirms the rendering path, but does not isolate layout, text selection and draft
   propagation costs. Even three replies take 225.60 ms for first bound typing; its cause remains
   ambiguous and should not be attributed solely to the large collection.

4. **Box refresh/scroll has a visible scale cost despite quiet idle.** At 500 text items the
   update takes 143.22 ms and a scroll step 228.11 ms, while idle is 0.35%.
   The update sample names `BoxBrowserView.list` (73 inclusive observations),
   `BoxBrowserRow.body` (54), `BoxItem.metadata(now:)` (49) and `visibleItems` (16).
   List rebuilding and row metadata construction are observed; the precise scroll-specific cause
   is not sampled and is therefore ambiguous.

5. **Shared snapshot projection and Attention filtering scale beyond the visible rows.**
   Attention updates rise from 12.27 to 113.64 ms; the long session thread uses 103.51 ms.
   Attention's update sample includes `MainMessageSurface.body` (247 observations) and
   `OverviewSnapshot.messages(for:)` (70). `MainMessageSurface.swift:29–31` calls the latter inside
   a filter for every attention item, repeatedly rebuilding and searching the destination array.
   The long-session sample names `SessionThreadView.body` (202) and `rows(reader:)` (181),
   with shared snapshot projection also present. No cache or algorithm changes were made.

6. **Initial idle readings include transient work and autonomous expiration.** Island short
   falls from 6.71% after one-second settling to 0.23% after five seconds; its idle sample has
   almost entirely waiting threads and one `ExpiryBandView.resynchronize` observation.
   This does not reproduce a sustained expiry-band redraw loop. History/Attention idle samples
   include `OverviewStore.scheduleExpiration` and snapshot rebuilding: session timestamps span
   the 15-minute activity boundary (`TodaySession.activityWindow`), so elapsed time can invalidate
   an entire snapshot without external input. Warm-up and expiry contributions are not separated.

Stack symbol/count excerpts are retained in [macos-survey-samples.txt](macos-survey-samples.txt).
These findings identify measured contributors; none is an optimization claim.

## Timer scope

The following are one-second SwiftUI schedules. Scope describes the closure in source, not a
guarantee that native ancestor layout is avoided. Sampling cannot prove the absence of a parent
body evaluation; unsampled or optimized frames remain ambiguous.

| Timer | Surface | Closure scope |
|---|---|---|
| `TodaySummary.swift:30` | Today / Projects alias | Live freshness label |
| `TodayActivity.swift:68` | Today working sessions | One session's age text |
| `TodayDecisionCard.swift:64` (`DecisionDeadline`) | Today decisions | One deadline text |
| `TodayStyle.swift:47` (`DecisionDefaultLine`) | Defaulted Today decisions | One default/deadline line |
| `AttentionRow.swift:20` | Attention list | One row's trailing time/priority |
| `AttentionDetail.swift:90` | Attention detail / Today inspector | Timing metadata group |
| `CachedReadStatus.swift:16` | Main toolbar, Box, Progress, Panels | One status text, even blank |
| `IslandView.swift:142` | Defaulted Island/window question | One auto-decision caption |
| `PanelDashboardCard.swift:99` | Each panel freshness badge | One freshness label |

History rows/replies and Session inspector/thread/resolved banners also have 60-second schedules;
Box browser and rows have 30-second schedules and Box detail has a 60-second schedule.
Those may not fire in a three-second idle observation. Pairing and phone-signin sheets have
one-second countdowns but are not mounted in the measured Settings states.
The Today idle samples name leaf closures without `MainView.body`/`TodayView.body` frames;
parent body re-evaluation on each one-second tick is not demonstrated. Native ancestor layout
does propagate in sampled updates. The History/Attention whole-surface evaluations seen during
idle have the expiration-task ancestry, rather than proving a one-second TimelineView fan-out.

## Reproduction

From the repository root:

```sh
macos/scripts/perf-survey.sh release
HIBOSS_PERF_FILTER='Today typical,Island short' macos/scripts/perf-survey.sh debug
```

The script runs `scripts/window-run.sh swift test -c <configuration> -Xswiftc -enable-testing --filter
'HibossIslandTests\.(MacosPerfSurveyTests|PerfSurveyIslandTests|PerfSurveySettingsTests|
PerfSurveyHistoryTests)/'` (without the line break), so a survey counts against the shared
window-run budget and an identical survey is replayed rather than rerun. It pipes
the complete log through `tee`, and prints a Markdown table. `HIBOSS_PERF_OUTPUT` chooses the
retained artifact directory. `HIBOSS_PERF_FILTER` is a comma-separated substring filter.
`HIBOSS_PERF_SAMPLE` selects surfaces for separate three-second idle and repeated-update `sample`
captures, taken after the measured windows. Samples are outside the reported idle/update costs.
Sampling counts below are inclusive stack observations, not method-call counts or additive times.
`HIBOSS_PERF_SETTLE_SECONDS=5` selects the longer settling period and annotates the data column.
`HIBOSS_PERF_DISABLE_ANIMATIONS=1` suppresses panel-root animations only in the test host.

## Verification and limits

All compilation and execution were local macOS tests; no remote HEAD or remote run applies.
`bash -n macos/scripts/perf-survey.sh` passed; all 40 table rows match retained log values.
Staged credential scanning passed with zero findings before each commit; no hooks were bypassed.
`macos/scripts/verify-tier.sh --files` selected M2 and the survey window classes. The release
survey compiles the app and tests together; the filtered survey replaced an additional debug
M2 window run. No full `HibossIslandTests` suite or screenshot harness ran.

Commands and retained evidence; log paths below start with `/private/tmp/hiboss-perf-`:

| Source | Command / selection | Result | Log suffix |
|---|---|---|---|
| 6254be7f | Release | Cache denied; no tests | `survey-20261029-164543/run.log` |
| 6254 + new tests | Release, elevated | 5 passed; exploratory | `survey-20261029-164553/run.log` |
| 23ba31c7 | Release + samples | 7 passed, 1 harness failure | `release-23ba31c7/run.log` |
| 9832e630 | Release | SDK compile failure | `release-9832e630/run.log` |
| 11794718 | Release + samples | 9 passed, 12 observations | `release-final/run.log` |
| 78cb2970 | Five single-method A/Bs | 5 × 1 passed | `ab-*.log` |
| 78cb2970 | Debug, two surfaces | 9 passed, 2 observations | `debug-78cb2970/run.log` |
| 78cb2970 | Opt-out, skip-build | 9 skipped, 0 failures | `opt-out-78cb2970.log` |

Substring filtering leaves unrelated test methods with no selected observations; their passing
method count is not a count of measured cases. The 23ba31c7 main-window failure was a stale probe
anchor, and its partial main-window rows are excluded. Other completed methods supply that commit's
table rows. The exploratory run's hidden collapsed window and unvalidated typing are excluded.
The exploratory script changed during compilation and its trailing table-print step failed.
The cache-denied and SDK compile attempts opened no windows. Four survey executions opened windows,
plus the permitted short single-method A/B checks; logs were read without rerunning for counts.

Exact survey environment for the two sampled release commands:

```sh
# Each line group precedes macos/scripts/perf-survey.sh release.
HIBOSS_PERF_OUTPUT=/private/tmp/hiboss-perf-release-23ba31c7
HIBOSS_PERF_SAMPLE='Today large,Attention list+detail large,History list+inline threads large,'\
'Island short,Session long thread,Box browser large,Panels 50'

HIBOSS_PERF_OUTPUT=/private/tmp/hiboss-perf-release-final
HIBOSS_PERF_FILTER='Today,Attention,Sessions,History,Projects'
HIBOSS_PERF_SAMPLE='Today large,Attention list+detail large,History list+inline threads large,'\
'History expanded 2000'
```

A/B commands used `HIBOSS_PERF_SURVEY=1`, `HIBOSS_PERF_CONFIG=release`, and
`HIBOSS_PERF_COMMIT=78cb29703254b48827ac329544349d18c2545097`, from `macos/`:

```sh
lockf -k /private/tmp/hiboss-macos-window-tests.lock caffeinate -d -i -u \
  swift test -c release -Xswiftc -enable-testing --filter '<method>' 2>&1 | tee '<log>'
```

| Log suffix | Method after `HibossIslandTests.` | Filter | Settle | Disable animations |
|---|---|---|---:|---:|
| panel-normal | `MacosPerfSurveyTests/testPanels` | `Panels 1` | 1 | 0 |
| panel-static | `MacosPerfSurveyTests/testPanels` | `Panels 1` | 1 | 1 |
| today-settled | `MacosPerfSurveyTests/testMainWindowSurfaces` | `Today large` | 5 | 0 |
| history-settled | `PerfSurveyHistoryTests/testExpandedHistoryThread` | `History expanded 2000` | 5 | 0 |
| island-settled | `PerfSurveyIslandTests/testIslandModes` | `Island short` | 5 | 0 |

Here Filter, Settle and Disable animations are `HIBOSS_PERF_FILTER`,
`HIBOSS_PERF_SETTLE_SECONDS` and `HIBOSS_PERF_DISABLE_ANIMATIONS`; logs are
`/private/tmp/hiboss-perf-ab-<suffix>.log`. Each command ran one method and one measured state.
The panel-static row was idle 0.08%, update 1.01 ms and interaction 13.61 ms, on release 78cb2970.
The opt-out command used `env -u HIBOSS_PERF_SURVEY` before the same lock/caffeinate wrapper,
`swift test -c release -Xswiftc -enable-testing --skip-build`, the script's four-class filter,
and `tee /private/tmp/hiboss-perf-opt-out-78cb2970.log`. No survey window opened.

Choices and remaining ambiguities: combined surfaces follow the actual navigation, CPU clocks
include deferred work rather than counting layout calls, and fixtures avoid live credentials.
Only the short Island received the longer-settling A/B; steady idle for the long variant is not
established. Option-window scale, large image-option sets, Progress media posters and authenticated
Settings collections and the Device Requests destination remain unmeasured. Brief idle intervals limit
ranking precision. Existing compiler isolation warnings and the NSTableView reentrancy warning
were left unchanged. No performance fix, push, merge, deployment or delegation occurred.
