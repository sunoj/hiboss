# macOS History — Message Threads

Status: accepted 2026-10-08. Supersedes the row description in
[macos-design-v2.md §3](macos-design-v2.md#3-history-window); the native-first rules there
still apply (rule 0, semantic colours, semantic type, no hex, no `.system(size:)`).

## Problem

The History stream renders every message as its own row. A boss answer to a question
("批准") lands as a separate "Me" row, often far from the question, with its own Details
block. Option images render full size, one above each button. A closed question hides
its choices behind a "Choices" disclosure, so the stream never shows what was chosen.

## Unit of the stream: a thread

A **thread** is one agent message plus every boss message whose `reply_to` is that
message's id and that is present in the same history list. A boss message whose parent
is absent (unlinked Telegram or Discord text, or a parent outside the loaded page) is a
**standalone boss thread** and renders as today's "Me" row.

- Replies keep server order. All replies render; none is dropped.
- The **outcome** of a decision comes from the newest reply.
- Authorship is read from `direction` only. A boss reply carries the agent's name.

The fold lives in `HibossKit` (`MessageThreads.swift`) and is shared by iOS and macOS.
iOS `MessageThreading.items` and `DecisionSettlement.init(reply:)` consume it directly; no
second fold remains in either app.

### Outcome

`ThreadOutcome` is derived, never stored:

| Case | Condition | Shown as |
|---|---|---|
| `open` | `canAnswer` (options, unresolved, not expired) | choices, countdown, composer |
| `chosen(option, source)` | newest reply body equals an option, not `auto_default` | chosen option marked; "Answered on Telegram" when the source is another surface |
| `autoSelected(option)` | newest reply has `metadata.auto_default == true`, or parent `metadata.options_expired` | clock glyph, "Auto-selected when time ran out"; never worded as the boss's choice |
| `replied(text, source)` | newest reply body matches no option | the reply quoted under the question |
| `expired` | options, no reply, status `expired` | "Expired without an answer" |
| `none` | no options | replies nested under the message |

Option matching trims whitespace and compares exactly; it never guesses.

## Filtering and search run on threads

Fold first, then filter. A thread matches search when its message or any reply matches.
Unread and Blocking test the agent message. Session headers count threads. Filtering a
flat list first would turn a matching reply whose parent does not match back into an
orphan row.

## Thread row

One row per thread, in the existing readable stream (`ScrollView` + `LazyVStack`,
session section headers, inline expansion). Layout top to bottom:

1. Header: monogram, agent name (`.headline`), unread dot, priority glyph, timestamp.
2. Body (`HistoryMessageBody`, unchanged).
3. Decision block, by outcome (above).
4. Replies for `none` and `replied`: each reply indented under a leading hairline, "Me"
   with time and source in `.caption` `.secondary`, text selectable.
5. Details disclosure for the agent message only. Folded replies have no Details.

### Choices

- **Text options, open:** native `.bordered` buttons, one per option; "default" marker in
  `.secondary`; countdown with `Text(timerInterval:)` when `expires_at` is set; "Write a
  reply" opens the composer (unchanged behaviour, shared drafts).
- **Text options, settled:** every option stays visible as a compact list. The chosen one
  carries `checkmark.circle.fill` in the accent colour and `.primary` text; the rest are
  `.secondary` with `circle`. An auto-selected option carries `clock.arrow.circlepath`.
- **Image options:** an adaptive grid (`LazyVGrid`, minimum column ~160 pt) of tiles. A
  tile is the thumbnail (`OptionMediaPreview`, fixed height, `scaledToFit`, click opens
  `OptionMediaPopover`), the label, the caption in `.caption`, and — when open — a native
  choose button. Settled: the chosen tile gets a checkmark overlay and accent outline from
  the system accent colour; the others are dimmed with `.opacity`. Options without media in
  the same message render as text options below the grid.
- **While a choice is sending:** the tapped option shows a small `ProgressView`; all
  choices are disabled. On success the history refresh brings the reply and the row
  settles; on conflict the existing `settleConflict` path applies.

## Notification detail

`HistoryMessageDetail` (the window opened from a notification) renders the same thread
row component for its message. It is a window wrapper, not a second renderer.

## Out of scope

The floating island (`IslandView`, `IslandPanelController`) and `Attention/` keep their own
option surfaces. Server and API are unchanged.

## Files

`HibossKit/Sources/HibossKit/MessageThreads.swift` (fold + outcome). In
`macos/Sources/HibossIsland/History/`: `HistoryThreadRow.swift` (replaces `HistoryRow`),
`HistoryDecisionBlock.swift` (choices by outcome), `HistoryOptionGrid.swift` (image tiles),
`HistoryReplies.swift` (nested replies). `HistoryReplyActions.swift` keeps the composer only.
The History folder stays at or under 10 files.

## Verification

- `HibossKit` unit tests for the fold and every outcome row in the table, including multiple
  replies, unlinked replies, auto-default, and whitespace in options.
- macOS tests for filter-after-fold and thread counts.
- A snapshot test that renders each outcome — open text, open images, chosen, chosen image,
  auto-selected, replied free text, expired, standalone boss, plain message with a reply —
  in light and dark with `ImageRenderer`, writing PNGs when `HIBOSS_SNAPSHOT_DIR` is set.
- `swift build && swift test` in `macos/`; iOS T3 for the `HibossKit` change; then
  `bash macos/scripts/build-app.sh` and look at the app.
