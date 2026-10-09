<!-- Design v4 for the iOS app and the macOS app: information architecture, tokens, screens.
     Derived from docs/philosophy.md; mockups and scenes live in docs/design-v4/. -->
# Design v4: Today, Sessions, Box, Progress

v4 replaces the information architecture of `docs/ios-design-v3.md` and the main window
of `docs/macos-design-v2.md`. The native-first rules of `docs/ios-design-contract.md`
and `docs/macos-design-v2.md` still hold: system controls, semantic colours from the
asset catalog (no hex in views), Dynamic Type text styles (no `.system(size:)`),
localization through the existing catalogs (English and zh-Hans).

Every rule below exists because of a rule in `docs/philosophy.md`; the section names it.

## Sources

- Mockups (HTML, read them as a precise picture, not as code to port):
  `docs/design-v4/mockups/`. `Main.dc.html` is iOS Today. Others are named by surface.
- Scenes: `docs/design-v4/scenes/island-day.svg`, `island-night.svg`. Ship them as
  vector assets (asset catalog with Preserve Vector Data on iOS; a bundled resource
  on macOS). Do not redraw them in code.
- Icon: the existing app icon, unchanged.

## Information architecture

### iOS: four tabs

| Tab | Purpose | Replaces |
|---|---|---|
| Today | What needs me, what is running, what just arrived | Home |
| Sessions | Every session grouped Needs you / Working / Idle; opens the session thread | Activity › Sessions and Messages |
| Box | Grid of Box items with search and filters | Activity › Box |
| Progress | The existing quiet feed, restyled | Progress |

Settings moves behind the avatar button at the top right of Today (a sheet). Messages
history is reachable from each session thread and from search on Sessions; there is
no separate Messages tab.

### macOS: one window, three panes

- Sidebar: Today (badge = open decisions), Box, Progress; then Sessions with a status
  dot each; a Live/Connecting footer and a Settings button.
- Content: Today = Your call / Working now / Delivered; a session = its thread with a
  reply field; Box = the existing browser restyled.
- Inspector (right): the selected decision, answerable in place with options and a
  free-text reply, plus "Earlier in this session" and Open session. For a session: its
  facts, what waits on the boss, its Box items, and its peers.
- The notch Island keeps its existing design; the menu bar item shows the icon and
  the open-decision count.

## Colour has a job

Named colours in each asset catalog, light and dark variants:

| Name | Light | Dark | Meaning (only this) |
|---|---|---|---|
| `Ink` | #111317 | #F2F3F5 | The primary action. Filled buttons only. |
| `Signal` | #C2410C | #F97316 | Needs you: deadlines, open-decision counts, Needs you dots |
| `Live` | #1D5FD8 | #7FB0FF | Working now, live panels, agent provenance badges |
| `Settled` | #15803D | #4ADE80 | The boss's recorded answer, a healthy connection |
| `Ground` | #F2F3F5 | #0E0F12 | Screen background |
| `Surface` | #FFFFFF | #1A1C21 | Cards and grouped rows |
| `SecondaryText` | #4A505A | #B4B9C2 | Context, meta |
| `TertiaryText` | #5F6570 | #9EA5AF | Timestamps, footnotes |
| `Hairline` | #E4E6EA | #2A2D34 | Separators |

Soft fills (`SignalSoft` #FFF1E8 / #3A2414, `LiveSoft` #EAF1FD / #18243A,
`SettledSoft` #EEF6F0 / #13301F) back badges and banners. Text on them uses the
dark tone of the same role. Brand colours (Sky #2FA3DE, Lagoon #19B9C4, Sand #E5BE77,
Palm #6CA83A) appear only inside the scenes, never as UI state.

## Type

| Mockup role | iOS text style | macOS |
|---|---|---|
| Large title (Today, Sessions, Box) | `.largeTitle` bold | window title |
| Title (decision detail) | `.title2` bold | `.title2` bold |
| Section (Your call) | `.title3` bold | `.headline` |
| Question | `.headline` | `.headline` |
| Body | `.subheadline` / `.body` | `.body` |
| Meta | `.footnote` | `.callout` / `.caption` |

## Components

1. **DecisionCard** (Today, Sessions, inspector, Live Activity, Island). In order:
   provenance line (project · branch · agent); deadline in `Signal` or the words
   "No deadline"; the question; what it changes (`metadata.content` or the message's
   subtitle) visible without a tap; options as buttons (first option filled `Ink`,
   others bordered) or A/B image tiles; when a default exists, the line
   "No answer in <time> picks “<default>”. That is not approval." (Authority 2)
2. **StatusChip**: dot + count ("2 need you", "3 working", "Live").
3. **ProvenanceBadge**: "Added by <agent>" on `LiveSoft`. Never shown for the boss's
   own items. (Authority 5)
4. **SessionRow**: monogram tile, project + branch, current step or last message,
   relative age. The tile tint follows the bucket: Signal / Live / neutral.
5. **FreshnessLabel**: "updated 9s ago", "Live · 6s". Every live value carries one.
   (Truth 3)
6. **ResolvedBanner**: "You chose B · 13:02" on `SettledSoft`; a timeout default shows
   "Default picked · not approval" on a neutral fill instead.
7. **Scene**: island-night in dark appearance, island-day in light, above the words
   "Nothing needs you" and the live line. Used only for the all-clear state and
   onboarding. Never on or next to a decision.

## Screens

### Today (iOS) / Today (macOS content + inspector)

- Header: date eyebrow, large title, avatar → Settings (iOS).
- Status chips row.
- **Your call**: DecisionCards from `TodaySnapshot.decisions`, ranked by the shared
  ranking. Options answer in place.
- **Working now**: SessionRows from `TodaySnapshot.working`.
- **Delivered**: recent results from `TodaySnapshot.delivered`, with attachment
  thumbnails (`MessageAttachment`).
- **All clear**: only when `TodaySnapshot.isAllClear` (no decisions, live connection,
  complete coverage). Otherwise the screen says what it cannot see. (Attention 5)
- Live panels that are running appear under "Watching" between Your call and Working
  now, with their freshness. Series gaps stay gaps.

### Decision detail (iOS sheet)

Provenance header, title, a facts card (Changes / Risk / Undo / Evidence rows when the
message provides them; otherwise the message content), the deadline banner, full-width
options, a free-text reply, Open session.

### Sessions (iOS)

Search field; sections Needs you / Working / Idle from `SessionDirectory`; rows open
the session thread.

### Session thread (iOS and macOS)

Header with project / branch, agent and machine, and a live step strip with
freshness. The thread shows messages with full attachments, decisions (open ones
answerable, resolved ones as ResolvedBanner), and live panel cards. A reply field at
the bottom replies to one target, always shown above the field: the session's newest
agent message that is not a resolved decision ("Replying to: <first line>"). When that
target is an open decision the label reads "Custom answer to: <question>", because a
free-text reply answers it. The target is fixed when the boss starts typing; if a newer
agent message arrives meanwhile, the field keeps its target and offers "Reply to the
newer message" instead of switching silently. With no eligible message the field is
disabled and says why. On iOS a + button
attaches from Box.

Session facts come from `ProjectSession` (`host`, `agentName`, `status`, `statusText`,
`startedAt`, `lastSeenAt`); a missing fact is omitted, never invented. Box items carry
no origin session, so the inspector shows "In your Box for <project>" (project scope),
not "from this session".

### Box

Search, filter chips (All, From me, From agents, kinds), a two-column grid on iOS and
the existing list on macOS; ProvenanceBadge on agent items.

### Lock screen / Dynamic Island / notch Island

These keep their existing design (the boss's call after reviewing a v4 redraw): the
iOS Live Activity / Dynamic Island and the macOS notch Island look and behave as before
v4. v4 changes only which decision they carry, taken from `TodaySnapshot.decisions`,
so every surface shows the same top decision. The `iOS-Lock` and `Mac-Island` mockups
are superseded on this point. (Attention 2)

Resolved cards never show the default line; "No deadline" appears once per card.

## Shared model (HibossKit)

`TodaySnapshot` and `SessionDirectory` in HibossKit are the single source for both apps:
the same ranking, the same buckets, the same all-clear rule. Neither app re-ranks.
Only the server's required-input list can make a decision open; history adds context
(working, delivered) and never reopens an answered or retired message.
