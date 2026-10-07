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
   Keep the count beside the title and deadline information on each card.
   The attention contract requires the content subtitle on the row;
   reducing reading must not hide information needed to choose safely.
4. **Loaded empty data can mask an unhealthy stream.**
   `ios/App/Home/HomeView.swift:101` checks fetch coverage but not `connectionState`.
   The all-clear invariant must explicitly require a connected stream. Cached requests
   remain visible with an offline/connecting explanation and a refresh gesture.
5. **Two ranking implementations can disagree.**
   `ios/App/Inbox/InboxStore.swift:77` sorts Live Activity candidates by deadline and
   priority; Home uses `AttentionModel`, which also ranks agents waiting without a
   deadline. Use Home's authoritative required-input set and ranking for Live Activity
   candidates and test agreement. Keep only the first option decision active and update
   it in place; lower-ranked activities must not replace it on the Island.
6. **A panel push can select a panel without presenting it.** The baseline sheet is
   attached to `HomePanelWall`, inside Home's lazy stack. A cold-launch panel route
   fails while the wall is offscreen (`hiboss-ios-v3-focused.log`, panel notification
   test). Move sheet ownership to Home's persistent root; keep the detail itself intact.

## New information architecture

Use four native tabs, each with one purpose:

- **Home:** requests that need the boss and the live panel wall. Options and option
  images stay inline. Message detail remains for full context and custom/text replies.
  Each request offers a session context-menu action. The all-clear island stays here and appears
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
| Follow request's session | Home → long-press card → View session | 2 → 2 |
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
| Session tiles and message/branch counts | Removed from summaries; transcript/detail retain context |
| Home request subtitle | Retained beside the question, as required by the attention contract |
| Request's session context | Home context menu and named VoiceOver action; detail link retained |
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
- `HomePanelWall`: Home only; move its sheet modifier to HomeView so lazy wall mounting
  cannot prevent a notification opening HomePanelDetail. Inspect wall and form routes.

## Screenshot comparison

Full-resolution galleries are `/private/tmp/hiboss-ios-v3-before/shots` and
`/private/tmp/hiboss-ios-v3-after/shots`. Links below open the 900-pixel review copies.
The original tour captured 73 images; the additional unchanged-app dark tour fills the
English, accessibility L, empty and connection comparisons. The empty/offline regression
failed on the old app, confirming the missing connection gate.

| Screen or state | Before | After | Visible change |
| --- | --- | --- | --- |
| Light, English Home | [image][b-en] | [image][a-en] | Smaller heading; four tabs; direct session link |
| Dark, English Home | [image][b-den] | [image][a-den] | Same hierarchy with semantic dark colors |
| Light, Chinese Home | [image][b-zh] | [image][a-zh] | Localized Activity and session action |
| Dark, Chinese Home | [image][b-dzh] | [image][a-dzh] | Same localized structure |
| Light, accessibility L Home | [image][b-l] | [image][a-l] | Smaller heading; question still wraps fully |
| Dark, accessibility L Home | [image][b-dl] | [image][a-dl] | Same Dynamic Type behavior |
| Light, accessibility L sessions | [image][b-ls] | [image][a-ls] | Native menu and stacked session rows |
| Dark, accessibility L sessions | [image][b-dls] | [image][a-dls] | Same readable native layout |
| Light, Chinese empty Home | [image][b-empty] | [image][a-empty] | Healthy all-clear illustration retained |
| Dark, Chinese empty Home | [image][b-dempty] | [image][a-dempty] | Healthy dark all-clear retained |
| Light, Chinese failed | [image][b-fail] | [image][a-fail] | Failure notice above cached requests |
| Dark, Chinese failed connection | [image][b-dfail] | [image][a-dfail] | Same connection notice |
| Light, Chinese connecting | [image][b-conn] | [image][a-conn] | Connecting notice above cached requests |
| Dark, Chinese connecting | [image][b-dconn] | [image][a-dconn] | Same pending-connection state |
| Session browser | [image][b-sessions] | [image][a-sessions] | Sessions is Activity's default selection |
| Message browser | [image][b-messages] | [image][a-messages] | Chronological history within Activity |
| Session transcript | [image][b-transcript] | [image][a-transcript] | Transcript and replies retained |
| Automatic outcome detail | [image][b-auto] | [image][a-auto] | Timeout source remains explicit |
| Progress media | [image][b-media] | [image][a-media] | Existing feed media viewer retained |
| Device pairing | [image][b-pair] | [image][a-pair] | Existing native pairing flow retained |

The after tour additionally covers Chinese accessibility L, English empty states, and
empty failed/connecting/disconnected states in both appearances. The unchanged tour did
not capture Chinese accessibility L or the new empty-connection regression attachments;
those are additional coverage, rather than matched comparisons.

Supplemental after captures: [Chinese accessibility L][a-zhl], [empty failed][a-efail],
[empty connecting][a-econn], [empty disconnected][a-edisc], [panel form][a-form],
[panel wall][a-wall], [Device Request notification][a-device], [Home option images][a-images],
[image zoom][a-zoom], [detail option images][a-detailimages], [sign-out confirmation][a-signout].
Their dark counterparts have the same filename with a `dark-` prefix.

[b-en]: /private/tmp/hiboss-ios-v3-before/shots/small/en-01-home.png
[a-en]: /private/tmp/hiboss-ios-v3-after/shots/small/en-01-home.png
[b-den]: /private/tmp/hiboss-ios-v3-before/shots/small/dark-en-01-home.png
[a-den]: /private/tmp/hiboss-ios-v3-after/shots/small/dark-en-01-home.png
[b-zh]: /private/tmp/hiboss-ios-v3-before/shots/small/zh-01-home.png
[a-zh]: /private/tmp/hiboss-ios-v3-after/shots/small/zh-01-home.png
[b-dzh]: /private/tmp/hiboss-ios-v3-before/shots/small/dark-zh-01-home.png
[a-dzh]: /private/tmp/hiboss-ios-v3-after/shots/small/dark-zh-01-home.png
[b-l]: /private/tmp/hiboss-ios-v3-before/shots/small/xxl-01-home.png
[a-l]: /private/tmp/hiboss-ios-v3-after/shots/small/xxl-01-home.png
[b-dl]: /private/tmp/hiboss-ios-v3-before/shots/small/dark-xxl-01-home.png
[a-dl]: /private/tmp/hiboss-ios-v3-after/shots/small/dark-xxl-01-home.png
[b-ls]: /private/tmp/hiboss-ios-v3-before/shots/small/xxl-08-sessions.png
[a-ls]: /private/tmp/hiboss-ios-v3-after/shots/small/xxl-08-sessions.png
[b-dls]: /private/tmp/hiboss-ios-v3-before/shots/small/dark-xxl-08-sessions.png
[a-dls]: /private/tmp/hiboss-ios-v3-after/shots/small/dark-xxl-08-sessions.png
[b-empty]: /private/tmp/hiboss-ios-v3-before/shots/small/empty-01-home.png
[a-empty]: /private/tmp/hiboss-ios-v3-after/shots/small/empty-01-home.png
[b-dempty]: /private/tmp/hiboss-ios-v3-before/shots/small/dark-empty-01-home.png
[a-dempty]: /private/tmp/hiboss-ios-v3-after/shots/small/dark-empty-01-home.png
[b-fail]: /private/tmp/hiboss-ios-v3-before/shots/small/conn-failed-01-home.png
[a-fail]: /private/tmp/hiboss-ios-v3-after/shots/small/conn-failed-01-home.png
[b-dfail]: /private/tmp/hiboss-ios-v3-before/shots/small/dark-conn-failed-01-home.png
[a-dfail]: /private/tmp/hiboss-ios-v3-after/shots/small/dark-conn-failed-01-home.png
[b-conn]: /private/tmp/hiboss-ios-v3-before/shots/small/conn-connecting-01-home.png
[a-conn]: /private/tmp/hiboss-ios-v3-after/shots/small/conn-connecting-01-home.png
[b-dconn]: /private/tmp/hiboss-ios-v3-before/shots/small/dark-conn-connecting-01-home.png
[a-dconn]: /private/tmp/hiboss-ios-v3-after/shots/small/dark-conn-connecting-01-home.png
[b-sessions]: /private/tmp/hiboss-ios-v3-before/shots/small/en-08-sessions.png
[a-sessions]: /private/tmp/hiboss-ios-v3-after/shots/small/en-08-sessions.png
[b-messages]: /private/tmp/hiboss-ios-v3-before/shots/small/en-04-messages.png
[a-messages]: /private/tmp/hiboss-ios-v3-after/shots/small/en-04-messages.png
[b-transcript]: /private/tmp/hiboss-ios-v3-before/shots/small/en-09-sessions-detail.png
[a-transcript]: /private/tmp/hiboss-ios-v3-after/shots/small/en-09-sessions-detail.png
[b-auto]: /private/tmp/hiboss-ios-v3-before/shots/small/en-18-auto-decided-detail.png
[a-auto]: /private/tmp/hiboss-ios-v3-after/shots/small/en-18-auto-decided-detail.png
[b-media]: /private/tmp/hiboss-ios-v3-before/shots/small/en-07-progress-media.png
[a-media]: /private/tmp/hiboss-ios-v3-after/shots/small/en-07-progress-media.png
[b-pair]: /private/tmp/hiboss-ios-v3-before/shots/small/en-13-pair-device.png
[a-pair]: /private/tmp/hiboss-ios-v3-after/shots/small/en-13-pair-device.png
[a-zhl]: /private/tmp/hiboss-ios-v3-after/shots/small/zh-xxl-08-sessions.png
[a-efail]: /private/tmp/hiboss-ios-v3-after/shots/small/empty-failed.png
[a-econn]: /private/tmp/hiboss-ios-v3-after/shots/small/empty-connecting.png
[a-edisc]: /private/tmp/hiboss-ios-v3-after/shots/small/empty-disconnected.png
[a-form]: /private/tmp/hiboss-ios-v3-after/shots/small/en-20-panel-form.png
[a-wall]: /private/tmp/hiboss-ios-v3-after/shots/small/en-22-panel-wall.png
[a-device]: /private/tmp/hiboss-ios-v3-after/shots/small/en-23-device-notification.png
[a-images]: /private/tmp/hiboss-ios-v3-after/shots/small/en-24-home-option-images.png
[a-zoom]: /private/tmp/hiboss-ios-v3-after/shots/small/en-25-option-image-zoom.png
[a-detailimages]: /private/tmp/hiboss-ios-v3-after/shots/small/en-26-detail-option-images.png
[a-signout]: /private/tmp/hiboss-ios-v3-after/shots/small/en-16-sign-out.png

## Compact Home and offline comparisons

KB consulted: `kb ios accessibility NavigationLink Home card` returned
“A view the platform silently drops looks exactly like a view you forgot to write”.
The missing `home-message-c1` button at accessibility XXXL is CONFIRMED: the unchanged
test failed before the fix (0 passed, 1 failed) and passed after it without assertion changes.
Attention groups now instantiate their request rows together, preserving offscreen question
accessibility. The extra session link row is removed; the question still opens message detail.
Long-press its context/question area for the native **View session** menu, or use the named
VoiceOver **View session** action. Message detail retains its session link.

The title and count share a baseline; group headings repeated information already on cards.
Each live default and countdown shares one caption line at default text size. At larger sizes
or with longer option labels, it wraps without truncating either value. Full questions,
content subtitles, inline choices, default markers and countdown urgency colors remain.

| Home flow | Main | Previous version | Compact Home |
| --- | ---: | ---: | ---: |
| Answer an option / compare images | 1 / 0 | 1 / 0 | 1 / 0 |
| Open decision detail | 1 | 1 | 1 |
| Follow the request's session | 2 taps | 1 tap | 1 long-press + 1 tap |
| Follow session with VoiceOver | Detail + link | Session link | 1 named action |
| Custom reply | 3 | 3 | 3 |

iPhone 17, default text size, identical demo data: the first two cards measure **239.33 pt**
each in both English and Chinese, versus approximately **267.67 pt** each on main
(803 pixels at 3× in the baseline Chinese screenshot). Both complete cards and all four
option buttons are visible: the second card ends at **595 pt**, above the tab bar at **791 pt**.
The geometry test checks card height, full bottom edges, 44 pt options and single-line timing.

| Home comparison | Main | Previous version | Compact Home |
| --- | --- | --- | --- |
| Chinese, light | [image][b-zh] | [image][a-zh] | [image][r2-zh] |
| English, light | [image][b-en] | [image][a-en] | [image][r2-en] |
| Chinese, dark | [image][b-dzh] | [image][a-dzh] | [image][r2-dzh] |
| English, dark | [image][b-den] | [image][a-den] | [image][r2-den] |

Demo option comparisons use two bundled, distinct 320×200 PNGs (about 1 KB each), generated
by `python3 ios/scripts/generate-demo-option-media.py`. Local image decoding is used in the
pending comparison and zoom viewer; remote message images retain their existing loader.
Tests verify bundled URLs, decoding, two distinct images and visible images in Home and zoom.
No resolved-decision view is changed.

Additional captures: [dark all-clear][r2-empty], [offline Home images][r2-images],
[offline image zoom][r2-zoom], and [accessibility XXXL question][r2-ax].

[r2-zh]: /private/tmp/hiboss-ios-v3-round2/shots/small/zh-01-home.png
[r2-en]: /private/tmp/hiboss-ios-v3-round2/shots/small/en-01-home.png
[r2-dzh]: /private/tmp/hiboss-ios-v3-round2/shots/small/dark-zh-01-home.png
[r2-den]: /private/tmp/hiboss-ios-v3-round2/shots/small/dark-en-01-home.png

[r2-empty]: /private/tmp/hiboss-ios-v3-round2/shots/small/dark-zh-empty-home.png
[r2-images]: /private/tmp/hiboss-ios-v3-round2/shots/small/dark-en-24-home-option-images.png
[r2-zoom]: /private/tmp/hiboss-ios-v3-round2/shots/small/dark-en-25-option-image-zoom.png
[r2-ax]: /private/tmp/hiboss-ios-v3-round2/shots/small/accessibility-home-question.png
