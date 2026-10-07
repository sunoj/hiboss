<!-- iOS navigation and interaction design, with simulator evidence and tap counts.
     Scope: native iOS app; follows the native design and attention contracts. -->
# iOS design v3

KB consulted: `kb ios navigation attention decision ux` and `kb 'SwiftUI screenshot simulator'`.
The relevant results were “A view the platform silently drops renders no error” and
“A fix that constrains the container breaks at the next call site”. Rendered screens,
including every changed consumer, are required evidence.

## Baseline

Baseline source: `5912a4113c5cf9c30ed953994705263ba59e5edf`.
Run from `ios/`: `scripts/ux-tour.sh /private/tmp/hiboss-ios-v3-before`.
Full attachments, logs and result bundles remain outside the repository at that path.
Screenshots use `shots/`; reduced copies use `shots/small/`.

The current five tabs are Home, Messages, Progress, Sessions and Settings.
Home combines ranked requests, inline options and the live panel wall.
Messages is chronological history. Sessions groups that same history and opens live
transcripts. Progress is a separate, non-notifying feed. Settings holds connection,
pairing, Device Requests, notification preferences and sign-out.

Tap counts start on Home with the requested row visible. Launching, typing, scrolling,
and another device's actions are excluded; tapping a text field counts as one tap.
Reading options or comparing option images does not require tapping.

| Flow | Current path | Taps |
| --- | --- | ---: |
| Answer an option decision | Home → option | 1 |
| Custom or text reply | Home → detail → reply field → Send | 3 |
| Follow the session of a request | Home → detail → View session | 2 |
| Browse a session | Sessions tab → session | 2 |
| Read a message | Messages tab → message | 2 |
| Check a live panel | Scroll Home → panel | 1 |
| Answer questionnaire | Home request → form → fields → Submit | 2 + field taps |
| Check progress | Progress tab | 1 |
| Pair a device | Settings tab → Pair another device | 2 |
| Review Device Request | Settings → Device Requests → request | 3 |
| Sign out | Settings → Sign Out → confirm | 3 |

## Problems and evidence

1. **Two competing history entrances.** `ios/App/Shell/RootTabView.swift:109` and
   `:128` create separate stacks for Messages and Sessions; both derive their rows
   from `InboxStore.history`. Baseline `en-04-messages` and `en-08-sessions` show the
   duplicate browsing destinations. CONFIRMED in code; Progress is a distinct feed.
2. **Context takes a detour through decision detail.**
   `ios/App/Home/HomeAttentionRow.swift:148` links only to the message; the session
   link is in `ios/App/Inbox/MessageDetailView.swift:65`. Baseline `en-03-home-detail`
   is the intervening screen.
3. **Home spends space repeating its job.**
   `ios/App/Home/HomeAttentionRow.swift:73` has a title, a count subtitle and group
   headings before the question. Baseline `xxl-01-home` shows the cost at accessibility L.
   Keep the count, meaningful deadline group and decision context, but use a smaller
   semantic title. The attention contract requires the content subtitle on the row;
   reducing reading must not hide information needed to choose safely.
4. **Loaded empty data can mask an unhealthy stream.**
   `ios/App/Home/HomeView.swift:101` checks fetch coverage but not `connectionState`.
   The all-clear invariant must explicitly require a connected stream. Cached requests
   remain visible with an offline/connecting explanation and a refresh gesture.
5. **Two ranking implementations can disagree.**
   `ios/App/Inbox/InboxStore.swift:77` sorts Live Activity candidates by deadline and
   priority; Home uses `AttentionModel`, which also ranks agents waiting without a
   deadline. Use Home's ranking for Live Activity candidates and test agreement.

## New information architecture

Use four native tabs, each with one purpose:

- **Home:** requests that need the boss and the live panel wall. Options and option
  images stay inline. Message detail remains for full context and custom/text replies.
  Each request offers a direct session link. The all-clear island stays here and appears
  only after healthy, complete message and questionnaire coverage.
- **Activity:** one browser for Sessions and Messages using a system picker. Sessions
  is the initial selection; native list rows show session, status and latest activity.
  Messages is chronological history, including recorded human and automatic outcomes.
  Both open the same existing detail/transcript destinations and reply gate.
- **Progress:** the separate non-notifying feed, with its existing media viewer.
- **Settings:** connection, pairing, Mac sign-in, Device Requests, preferences and sign-out.

Four tabs preserve one-tap access to shipped work. Moving Progress into Activity would
add a tap without eliminating overlapping data. The two-way Activity picker scales as
a menu at accessibility sizes so its labels remain readable.

| Flow | New path | Before → after taps |
| --- | --- | ---: |
| Answer option / compare option images | Home → option | 1 → 1 |
| Custom or text reply | Home → detail → field → Send | 3 → 3 |
| Follow request's session | Home → session link | 2 → 1 |
| Browse session | Activity → session | 2 → 2 |
| Read message (fresh Activity selection) | Activity → Messages → message | 2 → 3 |
| Read message (Messages already selected) | Activity → message | 2 → 2 |
| Check panel / questionnaire | Home → panel or request → form | unchanged |
| Check progress / pair / Device Request / sign-out | Existing flow | unchanged |
| Notification: message / panel / join request | Push → detail / panel / review | 1 → 1 |

The extra first-use message-filter tap is an explicit tradeoff for removing a duplicate
top-level destination. Activity remembers its selection while the app is open.
Message notifications select Messages before pushing detail; panel notifications open
Home's panel sheet; join requests open their review sheet over the current tab.

## Removed, merged and moved

| Surface or capability | Result |
| --- | --- |
| Separate Messages and Sessions tabs | Merged into Activity; no data capability removed |
| SessionsView | Deleted; session list belongs to Activity |
| Decorative session tiles and message/branch counts | Removed from summaries; transcript/detail retain context |
| Home request subtitle | Retained beside the question, as required by the attention contract |
| Request's session context | Direct link on Home; existing detail link retained |
| Options, custom replies, option images | Home options/images; full reply composer in detail |
| Transcripts and in-transcript decisions | Activity session destination and Home session links |
| Progress and media | Progress tab and full-screen viewer |
| Panels and all questionnaires | Home wall, Needs input filter and panel detail |
| Pairing, Mac sign-in, Device Requests, sign-out | Settings; notification review remains direct |
| All-clear illustration | Home, unchanged artwork and Reduce Motion behavior |
| Live Activity / Dynamic Island / widgets | Existing native presentation; shared Home decision ranking |

No server routes, CLI, shared HibossKit APIs, panel metrics or questionnaire semantics change.
Automatic outcomes retain their source labels and never become the boss's choice.

## Consumer inventory before implementation

- `HomeAttentionRow`: only `HomeAttentionSection`; section used only by `HomeView`.
- `SessionCard`: only `SessionsView`; replacement consumer is Activity.
- `DecisionOptions`: Home, MessageDetailView, SessionDecisionBubble and
  ProminentActionAppearanceTests. Layout is preserved; inspect all three screens.
- `InboxStore`: root/services, Home, Messages, Sessions, message detail, transcripts,
  resolved history and their tests. Only Live Activity candidate ranking changes.
- `DecisionSettlement`: InboxSettlement, store detail/feedback, MessageThreading,
  MessageDetailView, history and transcript rows, tests and macOS. No changes.
- `HomePanelWall`: Home only; keep panel sheet ownership, including deep links.

## Screenshot comparison

Pending completion of the unchanged tour and the implementation tour. The after tour
must cover light and dark, en and zh-Hans, accessibility L, empty and unhealthy connection
states, plus Home detail, Activity sessions/messages, transcripts, panels/questionnaires,
progress media, pairing, Device Requests and sign-out confirmation.
