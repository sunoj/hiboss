# iOS intermediate states

KB consulted: `kb ios loading required-input stream ready reconnect` found stream-liveness
examples: a pipe can stop delivering while its owner still reports healthy, and an
HTTP success alone does not prove freshness. The iOS trace below checks coverage separately.
A second KB query, `kb xcodebuild simulator unit stalls`, found cold-launch environment
issues. Cold test-host launches are reported separately from matched test results.
Base: `8bafbf1`. The four tabs and compact Home remain the information architecture.

## Inventory

References are relative to the repository root and refer to `8bafbf1`. Abbreviated
Inbox filenames live in `ios/App/Inbox/`; Home filenames in `ios/App/Home/`;
questionnaire filenames in `HibossKit/Sources/HibossKit/Questionnaires/`;
panel filenames in `HibossKit/Sources/HibossKit/Panels/`. `HibossKit/...` abbreviates
`HibossKit/Sources/HibossKit/`. Durations describe the original code.
HTTP calls normally use the 15-second request timeout; that is a transport limit,
not a guarantee of complete coverage across repeated fetches. “Unbounded” includes
streams, repeated reconnects and superseded snapshots. Screenshots are demo simulator
captures, linked in the evidence table. A row may share a screenshot with another
state on the same surface; separate consumers are captured separately.

| ID | Trigger and original code reference | Original presentation | Duration / can persist forever? | Target |
|---|---|---|---|---|
| H1 | Cold Home, `ios/App/Home/HomeView.swift:105`; `InboxStore.swift:24` | Title and grey “Checking for requests…” on an otherwise empty page | Until every independent source completes; yes | Named sources, redacted attention rows after 300 ms; Retry at 8 s |
| H2 | Required-input fetch, `ios/App/Inbox/InboxStore+RequiredInputs.swift:40` | Generic checking; cached decisions remain | HTTP timeout per fetch; repeated events can supersede forever | Name Requests; preserve cached decisions; bound continuous coverage gap |
| H3 | Required-input readiness, same file `:89` | Generic checking despite main stream connected | `.ready` can never arrive; yes | Name Requests connection; watchdog, Retry reconnects this stream |
| H4 | Required-input clean end/backoff, same file `:104` | Generic checking without an error | Repeated clean endings every reconnect delay; yes | Explicit lost requests connection; coverage remains incomplete; Retry |
| H5 | Main connection, `ios/App/Inbox/InboxStore.swift:212` | Connecting text above content or an empty page | Stream acquisition can suspend forever | Connection progress plus placeholders when no content; Retry / Settings |
| H6 | Main reconnect/backoff, same file `:235` | Error notice, or connected after a clean end | Exponential 4–60 s waits; retries indefinitely | Honest reconnect notice; cached content; bounded escalation |
| H7 | Panel discovery, `HibossKit/Sources/HibossKit/Panels/PanelsModel+Loading.swift:27` | Generic Home checking; no wall until tiles exist | Multiple HTTP requests; invalidation can repeat forever | Name Panels; Home placeholders and Retry |
| H8 | Questionnaire index/wall acknowledgement, `PanelsModel+Questionnaires.swift:50` | Generic Home checking | Fetch plus wall connection; no wall acknowledgement can last forever | Name Questionnaires; partial coverage never all-clear |
| H9 | Any refresh or foreground reload, `ios/App/Home/HomeView.swift:23` | Decisions/panels retained; generic checking may flash | Fetch chain or repeated invalidations; yes | Cached content with delayed refreshing notice; same 8 s clock across sources |
| H10 | Failed fetch over cached Home, `HomeView.swift:101` | Plain error + pull-to-refresh advice | Until next successful coverage; yes | Earlier results explicitly marked, Retry and Settings |
| L1 | Sessions first load, `ios/App/Messages/ActivityView.swift:60` | Centered unlabelled spinner | History HTTP timeout; can await service indefinitely in demo | Redacted rows, named progress, Retry after 8 s |
| L2 | Messages first load, `ios/App/Messages/MessagesView.swift:13` | Same spinner | Same as L1 | Same system, separate consumer capture |
| L3 | Progress first load/filter, `ios/App/Progress/ProgressFeedView.swift:15` | Same spinner, or old project posts until filter finishes | Feed HTTP; queued operations can delay indefinitely | Keep cached posts, refreshing mark; first-load rows; named outstanding feed |
| L4 | List refresh fails with cache, `ios/App/Inbox/ListStateView.swift:60` | Bottom stale banner | Until successful refresh; yes | Keep banner and add actual Retry control |
| L5 | Empty list fetch failure, `ListStateView.swift:40` | System unavailable view with Retry | Final error until retry | Retain system view; retry progress disables its own button |
| L6 | Resolved cold history, `ios/App/Inbox/ResolvedDecisionsView.swift:52` | “No handled decisions” before history completes | History HTTP timeout | Same loading/stale gate as lists; no false empty state |
| D1 | Uncached detail, `ios/App/Inbox/MessageDetailView.swift:116` | Unlabelled spinner; navigation title Loading | 1 s credential readiness + targeted fetch (2 s transport limit) | Redacted detail shape; named message wait; Retry after 8 s |
| D2 | Missing/failed detail, same file `:124` | System not-found/unavailable with Retry | Final fallback until retry | Keep it; Retry shows local progress; input/cache not discarded |
| A1 | Option reply from Home, `ios/App/Decision/DecisionOptions.swift:54` | Spinner on selected option, its choice group disabled | HTTP timeout; gate can remain held if service never returns | Delay spinner 300 ms; slow notice offers Settings; other decisions usable |
| A2 | Option reply from detail/transcript, `MessageDetailView.swift:193`, `SessionDecisionBubble.swift:43` | Same controls; haptic success, alert failure | Same as A1 | Same controls and slow state; visible success/recorded provenance |
| A3 | Typed reply, `MessageDetailView.swift:226` | Field and Send disabled, no progress on Send | Same as A1 | Progress on Send; draft editable/preserved, snapshot text sent |
| P1 | Feed next page, `ios/App/Progress/ProgressFeedView.swift:58` | Bottom spinner | HTTP timeout plus queued operations | Inline named progress; keep posts; slow Retry |
| P2 | Like action, `ios/App/Progress/ProgressFeedStore.swift:129` | Optimistic heart; silent rollback on failure | HTTP timeout plus queue; repeated taps queued | Own heart disabled/progress; visible failure and optimistic success |
| T1 | Transcript cold load/resync, `ios/App/Inbox/SessionMessagesView.swift:71` | Spinner or resync alert; empty list/error afterwards | Multi-page loop; repeated resync can run forever | Transcript shape/progress, Retry; preserve loaded transcript |
| T2 | Transcript connection/reconnect, `HibossKit/Sources/HibossKit/SessionStreamStore.swift:167` | Toolbar dot only | SSE + 2 s reconnect forever | Named reconnect notice; cached events; Retry after bounded wait |
| T3 | Transcript backfill, `SessionMessagesView.swift:94` | Spinner at top | One HTTP request; repeat failure retriggers on appearance | Inline earlier-events wait; Retry, visible load error |
| M1 | Option thumbnails, `ios/App/Inbox/OptionMediaComparison.swift:94` | Fixed image shape + spinner; failure glyph | Image URL load; no UI deadline, potentially forever | Keep shape; delayed progress, unavailable words and local Retry |
| M2 | Option zoom, same file `:124` | Full-screen spinner or unavailable view | Same as M1 | Named wait and Retry; Done always usable |
| M3 | Progress image cell, `ios/App/Progress/ProgressMediaView.swift:160` | Shape + spinner; failure photo glyph | URLSession timeout, no UI deadline | Same image state system; ALT/full-screen remains available |
| M4 | Progress viewer, `ProgressMediaViewer.swift:78` | Spinner or photo glyph | AsyncImage no UI deadline | Named wait, Retry, Close always usable |
| M5 | Video poster/player, `ProgressVideoPlayer.swift:86`, `:196` | Film glyph; player can cover it with black | Poster load/player buffering can last forever | Keep poster until player ready; system progress and Retry/close for slow video |
| M6 | Avatar, `ProgressTeamAvatar.swift:22` | Same-size empty circle | AsyncImage no UI deadline; yes | Keep decorative same-size placeholder; no spinner or escalation |
| O1 | Credential restore, `ios/App/HiBossApp.swift:48` | Centered spinner | Detached Keychain read; no explicit deadline | Named restore wait; system progress; no false sign-in flash |
| O2 | Manual connect/pair redemption, `ios/App/Onboarding/ConnectView.swift:156`, `:170` | Entire fields disabled; spinner in custom button | Network and key generation; can stall | System button with delayed progress; preserve credentials; slow explanation/cancel |
| S1 | Pair-code generation/polling, `ios/App/Settings/PairDeviceView.swift:67`; `HibossKit/.../Pairing/DevicePairingModel.swift:80` | Requesting spinner, then QR/countdown | Request timeout; poll every 1 s until code expires (normally 5 min) | **Owned by the Settings redesign** |
| S2 | Mac sign-in load/approve/reject, `ios/App/Settings/MacSigninView.swift:51`, `:127` | Spinner or disabled review form | HTTP timeout; pending code valid until expiry | **Owned by the Settings redesign** |
| S3 | Device Requests list/lookup/approve/reject, `ios/App/Settings/DeviceRequestsView.swift:50`, `JoinRequestReviewView.swift:33`, `:117` | List/detail spinner; whole review form disabled | HTTP; poll every 30 s on owning flow | **Owned by the Settings redesign** |
| S4 | Preferences load/save, `ios/App/Settings/PreferencesStore.swift:11`; `SettingsView.swift:119` | Form values and saving spinner | HTTP timeout, until reload | **Owned by the Settings redesign** |
| S5 | Push permission/register, `ios/App/Settings/SettingsView.swift:202` | System permission dialog / Registering | APNs callback can never arrive | **Owned by the Settings redesign** |
| S6 | Scanner permission/camera, `ios/App/Onboarding/PairingScannerView.swift:52` | System permission prompt / requesting camera access | User can leave prompt unanswered forever | **Owned by the Settings redesign** (shared scanner) |
| Q1 | Panel questions first load/poll, `HibossKit/.../Questionnaires/PanelQuestionnairesView.swift:20` | Progress above panel, errors with Retry | HTTP per fetch; every 10 s while open | Named wait, no flash; slow Retry; cached forms retained |
| Q2 | Submit/recover saved answers, `QuestionnaireEditor.swift:61`; `QuestionnaireModel.swift:66`, `:90` | Standalone spinner; form locked; draft and pending ID retained | Multiple HTTP calls, then unconfirmed receipt may persist forever | Button progress, slow Check status explanation; never auto-resubmit |
| Q3 | Panel relay freshness, `HibossKit/.../Panels/PanelsModel+Lifecycle.swift:24`; `PanelRelayConnection.swift:73` | Freshness label, frozen last values | Reconnect backoff 1–30 s indefinitely | Keep values/freshness; named relay wait and Retry/Settings in Home/detail |
| Q4 | Panel deep-link discovery, `ios/App/Shell/RootTabView.swift:178` | Home while awaiting open; unavailable alert only afterwards | Wait on `isFetching` can last forever | Explicit opening-panel progress with bounded retry; route can be dismissed |
| Q5 | Pin/archive/acknowledge, `HibossKit/.../Panels/PanelsModel+Loading.swift:91` | Menu dismisses; no in-flight indicator | HTTP timeout | Own panel action progress and failure; other panel controls available |
| Q6 | Embedded web leaf handshake, `HibossKit/Sources/HibossKit/PanelWebLeaf.swift:158` | Web content placeholder until mount handshake | Web navigation/bridge handshake can stall forever | Visible loading / slow retry; native content stays usable |

## Design rules

1. Wait 300 ms before adding progress UI. Fast operations change directly to their
   result. Keep the existing content during refresh; placeholders are for absent content.
2. At 8 seconds, name the outstanding source and provide a real Retry or Settings
   control. Eight seconds gives a mobile request room to recover while escalating well
   before the normal 15-second network deadline. Continuous incomplete coverage owns
   one timer: events and backoff must not restart the eight-second grace period.
3. Use system `ProgressView`, redacted native text rows and system buttons. No custom
   spinner, shimmer, fixed font sizes or invented percentage. Theme semantic roles
   supply app colours; labels wrap at accessibility L and in Simplified Chinese.
4. A first-load placeholder communicates content shape without fake agent names or
   tappable fake decisions. Hide redacted labels from VoiceOver; announce the real wait.
5. Name Connection, Requests, Panels and Questionnaires independently. Messages/history
   is also named while its initial fetch remains outstanding. Incomplete or stale
   coverage never renders the island or “Nothing needs you”.
6. Disable the active action's admission control, including mutually exclusive choices
   for that same decision. Keep other decisions, navigation, media, and text input usable.
   Never retry a write automatically. Preserve drafts after failure; success is visible.
7. Read-only retries cancel/supersede the older attempt where the store supports it.
   A slow write offers connection Settings or explicit status reconciliation, without
   claiming cancellation means the server did not accept the write.
8. Image geometry stays stable; progress only appears inside its reserved area. Decorative
   avatars keep their placeholder indefinitely. Their failure does not block the post.
9. A timeout-selected default retains “Auto-selected” provenance in all decision surfaces.
   A pending state must not turn a server default into a boss choice.
10. Settings rows are inventoried only; their design and implementation belong to the
    Settings redesign. No file under `ios/App/Settings/` is changed here.

## Shared-component consumers

| Component | Consumers to verify |
|---|---|
| ListStateView | Activity Sessions, Activity Messages, Progress; Resolved and transcript join the same gate |
| DecisionOptions | HomeAttentionRow, MessageDetailView, SessionDecisionBubble; appearance unit snapshots |
| OptionMediaComparison | HomeAttentionRow, pending/resolved MessageDetailView, SessionDecisionBubble, ResolvedDecisionsView; full-screen zoom |
| Progress image / video rows | ProgressPostCard feed mosaic and ProgressMediaViewer |
| DecisionActivityControls | Widget ActionButtons and DemoActivityStateView (same native control) |
| HomeAttentionSection | HomeView; attention-layout tests |
| PanelQuestionnairesView / QuestionnaireEditor | iOS HomePanelDetail and macOS PanelsView; iOS-only presentation changes preserve macOS behavior |

## Stuck-state investigation

**CONFIRMED with failing-before and passing-after regression tests.** The main message
stream marks itself connected as soon as an `AsyncThrowingStream` is obtained
(`InboxStore.swift:217`). That says nothing about the separate required-input stream.
`applyRequiredInputEvent` cancels and invalidates the snapshot on every event;
`.ready` sets readiness, other events retain it, then reconciliation fetches the
authoritative set. Both flags are cleared at stream start and end. The fetch may
set loaded before ready, but `hasCompleteRequiredInputs` requires both. This is correct
coverage safety, but has no liveness deadline. A clean end records no error, and a
silent stream can wait forever. Repeated ready/end cycles also continually invalidate.

The premise that every event clears readiness is **REFUTED**: `message` and
`resolved` retain readiness; every event does invalidate the fetched snapshot. Start,
end and reconnect clear readiness. The fix keeps that coverage rule, gives a clean
end an explicit source error, and gives continuous missing readiness/snapshot coverage
an eight-second watchdog. A successful fetch without `.ready` cannot clear the error.
Retry restarts the required-input stream and preserves the cached attention set.
Main-stream clean endings now leave `.connected` immediately.

`RequiredInputLivenessTests` ran against the original implementation: **2 tests,
2 failures** (`hiboss-liveness-before-3.xcresult`). Both pass with the fix. The tests
assert that the main stream remains connected while required-input coverage becomes
an actionable error, never all-clear. Existing nine coverage tests also pass.

Panels set `.loaded` only after metadata and all additions reconcile. Every wall
change/disconnect invalidates questionnaire coverage; a successful questionnaire
fetch counts only when the wall is acknowledged and there is no scheduled/in-flight
reconciliation. A wall that never acknowledges can therefore keep questionnaires
incomplete despite a loaded panel list. A missing QuestionnaireServing also returns
without coverage or an error. These states must remain conservative and visible. A normal `load()` during an
existing fetch only queues reconciliation, so a slow Retry needs a superseding read.
`retryLoading()` now supersedes discovery and questionnaire reads. `PanelRetryTests`
checks a new request is admitted and a late old request cannot end the new pending
state (**2 passing tests**). A questionnaire fetch without wall acknowledgement
still does not grant coverage. The UI names Questionnaires and offers Retry/Settings.

A separate Home assertion failed before the refresh fix (**1 test, 1 failure**,
`hiboss-home-refresh-before.xcresult`): complete request coverage must still name
Messages while cached history refreshes. Home now includes in-flight history and panel
reads and names the failed source before its diagnostic.

Transcript reads also use generations: stopped, superseded and late backfill responses
cannot replace or append to a newer transcript (`TranscriptRefreshTests`, **3 passing**).

The questionnaire form retains its existing immutable pending-submission draft lock:
a receipt lookup refers to that saved answer version. Other questionnaires and panel
navigation stay usable. A status check never automatically submits the draft again.

## Before / after evidence

The capture harness holds operations for 60 seconds (120 seconds for the long
Settings preference form) and records ordinary and slow
forms. File suffix `-slow` is the same held state after eight additional seconds.
After captures cover light/dark × en/zh-Hans × standard/accessibility L. All screenshots
come from `app.launchConfiguredDemo()`; no device installation is used.

| Inventory IDs | Before (English/light) | After |
|---|---|---|
| H1, H2 | [Requests](../ios/Screenshots/intermediate/before/en-home-requests.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-requests.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-home-requests-slow.png) |
| H3 | [Requests readiness](../ios/Screenshots/intermediate/before/en-home-requests_ready.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-requests_ready.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-home-requests_ready-slow.png) |
| H4 | [Clean end](../ios/Screenshots/intermediate/before/en-home-stream-ends-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-stream-ends.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-home-stream-ends-slow.png) |
| H5 | [Connecting](../ios/Screenshots/intermediate/before/en-home-connecting.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-connecting.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-home-connecting-slow.png) |
| H6 | [Backoff](../ios/Screenshots/intermediate/before/en-home-failed-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-failed.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-home-failed-slow.png) |
| H7 | [Panels](../ios/Screenshots/intermediate/before/en-home-panels.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-panels.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-home-panels-slow.png) |
| H8 | [Questions](../ios/Screenshots/intermediate/before/en-home-questionnaires.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-questionnaires.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-home-questionnaires-slow.png) |
| H9, H10 | [Partial](../ios/Screenshots/intermediate/before/en-home-partial.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-partial.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-home-partial-slow.png) |
| L1 | [Sessions](../ios/Screenshots/intermediate/before/en-sessions-load.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-sessions-load.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-sessions-load-slow.png) |
| L2 | [Messages](../ios/Screenshots/intermediate/before/en-messages-load.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-messages-load.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-messages-load-slow.png) |
| L3 | [Progress](../ios/Screenshots/intermediate/before/en-progress-load.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-progress-load.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-progress-load-slow.png) |
| L4 | [Stale messages](../ios/Screenshots/intermediate/before/en-messages-stale.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-messages-stale.png) |
| L5 | [Feed error](../ios/Screenshots/intermediate/before/en-progress-failed.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-progress-failed.png) |
| D1 | [Detail](../ios/Screenshots/intermediate/before/en-detail-load.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-detail-load.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-detail-load-slow.png) |
| D2 | [Missing](../ios/Screenshots/intermediate/before/en-detail-missing.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-detail-missing.png) |
| A1 | [Home reply](../ios/Screenshots/intermediate/before/en-home-reply.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-reply.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-home-reply-slow.png) |
| A2 | [Detail reply](../ios/Screenshots/intermediate/before/en-detail-reply.png), [transcript reply](../ios/Screenshots/intermediate/before/en-transcript-reply.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-detail-reply.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-detail-reply-slow.png) |
| T1 | [Transcript](../ios/Screenshots/intermediate/before/en-transcript-load.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-transcript-load.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-transcript-load-slow.png) |
| T2 | [Transcript reconnect](../ios/Screenshots/intermediate/before/en-transcript-reconnect-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-transcript-reconnect.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-transcript-reconnect-slow.png) |

| H9 | [Original cached refresh](../ios/Screenshots/intermediate/before/en-home-refresh.png) · [held](../ios/Screenshots/intermediate/before/en-home-refresh-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-refresh.png) |
| H10 | [Original stale Home](../ios/Screenshots/intermediate/before/en-home-stale.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-home-stale.png) |
| L1, L4 | [ordinary](../ios/Screenshots/intermediate/before/en-sessions-stale.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-sessions-stale.png) |
| L1, H9 | Same cached content as H9; original refresh adds no source-specific recovery. | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-sessions-refresh.png) |
| L6 | [ordinary](../ios/Screenshots/intermediate/before/en-resolved-load.png) · [held](../ios/Screenshots/intermediate/before/en-resolved-load-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-resolved-load.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-resolved-load-slow.png) |
| A2, T1 | [ordinary](../ios/Screenshots/intermediate/before/en-transcript-reply.png) · [held](../ios/Screenshots/intermediate/before/en-transcript-reply-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-transcript-reply.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-transcript-reply-slow.png) |
| A3 | [ordinary](../ios/Screenshots/intermediate/before/en-typed-reply.png) · [held](../ios/Screenshots/intermediate/before/en-typed-reply-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-typed-reply.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-typed-reply-slow.png) |
| A3 failure | Original failure/banner behavior is shared with L4/A3. | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-typed-reply-failed.png) |
| P1 | [ordinary](../ios/Screenshots/intermediate/before/en-progress-more.png) · [held](../ios/Screenshots/intermediate/before/en-progress-more-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-progress-more.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-progress-more-slow.png) |
| P2 | [ordinary](../ios/Screenshots/intermediate/before/en-progress-like.png) · [held](../ios/Screenshots/intermediate/before/en-progress-like-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-progress-like.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-progress-like-slow.png) |
| T3 | [ordinary](../ios/Screenshots/intermediate/before/en-transcript-earlier.png) · [held](../ios/Screenshots/intermediate/before/en-transcript-earlier-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-transcript-earlier.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-transcript-earlier-slow.png) |
| M1 Home | [ordinary](../ios/Screenshots/intermediate/before/en-image-home.png) · [held](../ios/Screenshots/intermediate/before/en-image-home-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-image-home.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-image-home-slow.png) |
| M1 detail | [ordinary](../ios/Screenshots/intermediate/before/en-image-detail.png) · [held](../ios/Screenshots/intermediate/before/en-image-detail-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-image-detail.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-image-detail-slow.png) |
| M1 transcript | [ordinary](../ios/Screenshots/intermediate/before/en-image-transcript.png) · [held](../ios/Screenshots/intermediate/before/en-image-transcript-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-image-transcript.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-image-transcript-slow.png) |
| M1 resolved list | [ordinary](../ios/Screenshots/intermediate/before/en-image-resolved.png) · [held](../ios/Screenshots/intermediate/before/en-image-resolved-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-image-resolved.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-image-resolved-slow.png) |
| M1 settled detail | [ordinary](../ios/Screenshots/intermediate/before/en-image-settled-detail.png) · [held](../ios/Screenshots/intermediate/before/en-image-settled-detail-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-image-settled-detail.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-image-settled-detail-slow.png) |
| M2 | [ordinary](../ios/Screenshots/intermediate/before/en-image-zoom.png) · [held](../ios/Screenshots/intermediate/before/en-image-zoom-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-image-zoom.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-image-zoom-slow.png) |
| M3, M6 | [ordinary](../ios/Screenshots/intermediate/before/en-image-progress.png) · [held](../ios/Screenshots/intermediate/before/en-image-progress-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-image-progress.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-image-progress-slow.png) |
| M4 | [ordinary](../ios/Screenshots/intermediate/before/en-image-progress-viewer.png) · [held](../ios/Screenshots/intermediate/before/en-image-progress-viewer-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-image-progress-viewer.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-image-progress-viewer-slow.png) |
| M5 feed | [ordinary](../ios/Screenshots/intermediate/before/en-video-progress.png) · [held](../ios/Screenshots/intermediate/before/en-video-progress-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-video-progress.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-video-progress-slow.png) |
| M5 viewer | [ordinary](../ios/Screenshots/intermediate/before/en-video-viewer.png) · [held](../ios/Screenshots/intermediate/before/en-video-viewer-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-video-viewer.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-video-viewer-slow.png) |
| O1 | [ordinary](../ios/Screenshots/intermediate/before/en-restore.png) · [held](../ios/Screenshots/intermediate/before/en-restore-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-restore.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-restore-slow.png) |
| O2 | [ordinary](../ios/Screenshots/intermediate/before/en-onboarding-connect.png) · [held](../ios/Screenshots/intermediate/before/en-onboarding-connect-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-onboarding-connect.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-onboarding-connect-slow.png) |
| S1 code | [ordinary](../ios/Screenshots/intermediate/before/en-owned-pairing-code.png) · [held](../ios/Screenshots/intermediate/before/en-owned-pairing-code-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-pairing-code.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-pairing-code-slow.png) (Settings-owned UI unchanged) |
| S1 poll | [ordinary](../ios/Screenshots/intermediate/before/en-owned-pairing-poll.png) · [held](../ios/Screenshots/intermediate/before/en-owned-pairing-poll-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-pairing-poll.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-pairing-poll-slow.png) (Settings-owned UI unchanged) |
| S2 lookup | [ordinary](../ios/Screenshots/intermediate/before/en-owned-signin-load.png) · [held](../ios/Screenshots/intermediate/before/en-owned-signin-load-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-signin-load.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-signin-load-slow.png) (Settings-owned UI unchanged) |
| S2 approve/reject | [ordinary](../ios/Screenshots/intermediate/before/en-owned-signin-approve.png) · [held](../ios/Screenshots/intermediate/before/en-owned-signin-approve-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-signin-approve.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-signin-approve-slow.png) (Settings-owned UI unchanged) |
| S3 list | [ordinary](../ios/Screenshots/intermediate/before/en-owned-devices-load.png) · [held](../ios/Screenshots/intermediate/before/en-owned-devices-load-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-devices-load.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-devices-load-slow.png) (Settings-owned UI unchanged) |
| S3 lookup | [ordinary](../ios/Screenshots/intermediate/before/en-owned-device-detail.png) · [held](../ios/Screenshots/intermediate/before/en-owned-device-detail-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-device-detail.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-device-detail-slow.png) (Settings-owned UI unchanged) |
| S3 approve/reject | [ordinary](../ios/Screenshots/intermediate/before/en-owned-device-approve.png) · [held](../ios/Screenshots/intermediate/before/en-owned-device-approve-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-device-approve.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-device-approve-slow.png) (Settings-owned UI unchanged) |
| S4 read | [ordinary](../ios/Screenshots/intermediate/before/en-owned-preferences-load.png) · [held](../ios/Screenshots/intermediate/before/en-owned-preferences-load-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-preferences-load.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-preferences-load-slow.png) (Settings-owned UI unchanged) |
| S4 write | [ordinary](../ios/Screenshots/intermediate/before/en-owned-preferences-save.png) · [held](../ios/Screenshots/intermediate/before/en-owned-preferences-save-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-preferences-save.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-preferences-save-slow.png) (Settings-owned UI unchanged) |
| S5 register | [ordinary](../ios/Screenshots/intermediate/before/en-owned-push-register.png) · [held](../ios/Screenshots/intermediate/before/en-owned-push-register-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-push-register.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-push-register-slow.png) (Settings-owned UI unchanged) |
| S6 | [ordinary](../ios/Screenshots/intermediate/before/en-owned-camera-permission.png) · [held](../ios/Screenshots/intermediate/before/en-owned-camera-permission-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-owned-camera-permission.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-owned-camera-permission-slow.png) (Settings-owned UI unchanged) |
| Q1 | [ordinary](../ios/Screenshots/intermediate/before/en-panel-questions.png) · [held](../ios/Screenshots/intermediate/before/en-panel-questions-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-panel-questions.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-panel-questions-slow.png) |
| Q2 submit | [ordinary](../ios/Screenshots/intermediate/before/en-questionnaire-submit.png) · [held](../ios/Screenshots/intermediate/before/en-questionnaire-submit-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-questionnaire-submit.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-questionnaire-submit-slow.png) |
| Q2 recovery | Original pending-submission presentation is shown in Q2 submit. | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-questionnaire-recovery.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-questionnaire-recovery-slow.png) |
| Q3 awaiting/stale/offline | [Original freshness label](../ios/Screenshots/intermediate/before/en-panel-preference.png) | [awaiting](../ios/Screenshots/intermediate/after/en-light/en-light-panel-stream-awaiting-slow.png) · [stale](../ios/Screenshots/intermediate/after/en-light/en-light-panel-stream-stale-slow.png) · [offline](../ios/Screenshots/intermediate/after/en-light/en-light-panel-stream-offline-slow.png) |
| Q4 | [ordinary](../ios/Screenshots/intermediate/before/en-panel-route.png) · [held](../ios/Screenshots/intermediate/before/en-panel-route-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-panel-route.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-panel-route-slow.png) |
| Q5 | [ordinary](../ios/Screenshots/intermediate/before/en-panel-preference.png) · [held](../ios/Screenshots/intermediate/before/en-panel-preference-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-panel-preference.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-panel-preference-slow.png) |
| Q6 | [ordinary](../ios/Screenshots/intermediate/before/en-panel-web.png) · [held](../ios/Screenshots/intermediate/before/en-panel-web-slow.png) | [ordinary](../ios/Screenshots/intermediate/after/en-light/en-light-panel-web.png) · [held](../ios/Screenshots/intermediate/after/en-light/en-light-panel-web-slow.png) |

S4–S6 use the unchanged original Settings/scanner views held by demo transports.
The permission-dialog capture is [the native notification prompt](../ios/Screenshots/intermediate/before/en-owned-notification-permission.png).
Approve and Reject share the same pending control state in each Settings-owned review.
Q3 includes wall acknowledgement and individual panel data. Missing/stale/offline panel
values now suppress Home all-clear and gain a bounded detail notice with Retry/Settings.
The relay transport backoff remains 1–30 seconds; UI retry refreshes metadata without
inventing a fresh lease. Decorative avatars keep their original circle, with a demo-only
hold added so the empty AsyncImage phase can be captured.

Live Activity reply controls also gain delayed progress and slow/failure feedback. The
source trigger is `ios/Shared/DecisionReplyGate.swift:38`; a write can remain pending
until its service completes. [Ordinary controls](../ios/Screenshots/intermediate/after/en-light/en-light-activity-reply.png)
and [slow controls](../ios/Screenshots/intermediate/after/en-light/en-light-activity-reply-slow.png)
use the exact shared control hosted in a demo view. These are component screenshots,
not screenshots of the operating system's Lock Screen container. Originally the selected
button retained its label with the other choice dimmed; it had no progress or escalation.
Optional persisted progress markers keep older ActivityKit content readable (decoding test).
Video transitions retain a displayed frame during buffering, keep failure terminal despite
late ready callbacks, and reset on explicit retry or a changed URL. Two transition tests
failed with the prior presentation behavior (`hiboss-video-before.xcresult`) and pass
with the corrected state.

## Verification

The matrix is reproducible with `ios/scripts/intermediate-states.sh` and
`ios/scripts/export-intermediate-shots.py`. Variant names encode language, optional
`ax` (accessibility L), and appearance. Each directory contains every held ordinary/slow
capture; the table above uses English light as its compact before/after comparison.

| Appearance | English | Simplified Chinese |
|---|---|---|
| Light | [Standard](../ios/Screenshots/intermediate/after/en-light/) | [Standard](../ios/Screenshots/intermediate/after/zh-light/) |
| Dark | [Standard](../ios/Screenshots/intermediate/after/en-dark/) | [Standard](../ios/Screenshots/intermediate/after/zh-dark/) |
| Light, accessibility L | [Large](../ios/Screenshots/intermediate/after/en-ax-light/) | [Large](../ios/Screenshots/intermediate/after/zh-ax-light/) |
| Dark, accessibility L | [Large](../ios/Screenshots/intermediate/after/en-ax-dark/) | [Large](../ios/Screenshots/intermediate/after/zh-ax-dark/) |

Focused evidence: 25 initial unit tests passed; 17 coverage/feed/transcript tests passed;
7 panel-retry/transcript/liveness tests passed; 4 Home/media behavioral tests passed.
The final focused coverage run passed **14 unit tests** (including the refresh fix and
missing panel data); the panel-stream capture and corrected push capture also pass.
The typed-reply failure test asserts editable retained input; the refresh test asserts
cached Home/list content. Capture tests assert route entry and reachable close controls.
The macOS shared consumers passed `swift build` and **233 tests, zero failures**.
`python3 ios/scripts/i18n-audit.py` passes. The final report records exact validation
commands, tested commit and full unit/UI xcresult counts; only UXTourUITests is excluded. Simulator screenshots are evidence of rendering;
coverage, retry and write-admission assertions provide behavioral evidence.
