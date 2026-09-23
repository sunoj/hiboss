KB consulted: `kb ios home attention swiftui` matched the SwiftUI silent-view-drop
lesson, `ai-coding/a-view-the-platform-drops-renders-no-error.md`.

# iOS Home attention update

## Findings and changes

- Home previously excluded all messages without options and did not include
  pending questionnaires in its attention count.
- Home now uses one snapshot for message groups, questionnaire rows, and the
  count. Blocking text asks join the blocked group. Existing option filtering,
  ranking, and tie-breakers remain unchanged.
- Blocking questionnaire rows are independent of the selected wall filter, deduplicated
  by request ID, and filtered for expiry using the panel's server clock. The
  latest request revision wins. Known terminal panels cannot retain requests.
- Text asks open message detail and its free-text reply. Optimistic withdrawal
  survives stale history and is rolled back on send failure. Questionnaires
  open their owning panel through the existing panel detail sheet.
- The all-clear state requires zero attention items and completed, successful
  message and questionnaire loading. Known items remain visible on load errors.
- Cards combine project and agent attribution, omit repeated context, and give
  all choices equal styling. Short pairs stay inline; long/many choices and
  accessibility text sizes use vertically wrapping controls with 44pt targets.
- The five tabs, notification routing, system theme tokens, safe-area structure,
  and AllClearIsland artwork/motion implementation are unchanged.

## Coverage added

Model and flow cases cover text ask filtering, unchanged option ordering,
request-ID deduplication, latest revisions, server-clock expiry, counts across
resolution, owning-panel selection outside the wall filter, stale history,
and failed replies. UI cases cover inline answers, text detail/reply, and
reaching later choices at accessibility text sizes. Existing populated and
empty Home UI cases remain in place. Demo panel reads now return a known empty
result instead of depending on server credentials; the oversized demo data
file's unchanged progress service was moved to its own file.

## Runtime behavior

- A request whose panel has not loaded remains counted. Opening it explains
  that the panel is unavailable and asks the user to refresh.

## Changed files

- `ios/App/Home/HomeAttentionModel.swift`
- `ios/App/Home/HomeAttentionRow.swift`
- `ios/App/Home/HomeView.swift`
- `ios/App/Inbox/InboxStore.swift`
- `ios/App/Inbox/MessageCard.swift`
- `ios/App/Inbox/MessageDetailView.swift`
- `ios/App/Preview/DemoData.swift`
- `ios/App/Preview/DemoHomePanelsAPI.swift`
- `ios/App/Preview/DemoProgressAPI.swift`
- `ios/App/Shell/RootTabView.swift`
- `ios/Tests/HomeAttentionModelTests.swift`
- `ios/Tests/HomeAttentionFlowTests.swift`
- `ios/UITests/DemoLaunchSupport.swift`
- `ios/UITests/ResolvedNavigationUITests.swift`
- This investigation report.
