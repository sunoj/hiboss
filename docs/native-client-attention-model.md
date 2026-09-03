# Attention model — the shared contract for both native clients

The iOS app and the macOS windows are being redesigned together. This file is the
single model they both implement. Where a client deviates it must be because the
platform demands it, not because it invented its own vocabulary.

## The problem this replaces

The iOS home screen currently orders itself: an **Activity** card (three
percentage deltas and a seven-column heatmap), then a horizontally scrolling
**Projects** strip, then **Needs you**. The thing that requires the boss begins
at the tab bar — everything above it is retrospective. Four consequences, all
reported by the boss and all visible in one screenshot:

- **No urgency is encoded anywhere.** An agent blocked and burning time looks the
  same as a finished test run. `Decisions -50%` is rendered in red without a
  window label or a baseline, and nobody can say whether it is good news.
- **Project attribution is lost.** The project strip scrolls horizontally and
  truncates; the attention list does not carry the project at all.
- **There is no action.** Two unread badges sit on two different tabs (`Home 2`,
  `Inbox 3`) whose distinction is not stated, and no element on the first screen
  is an entry point to doing anything.
- **History and now are interleaved.** The heatmap is history, the project
  snippet is history, and the only present-tense element is last.

## The one question

> **The first screen answers: does anything need me right now?**

Everything else is secondary and lives below it or elsewhere. A screen that says
"nothing needs you" is a correct and *desirable* outcome, not an empty state to
apologise for — it is the answer the boss opens the app to get, and most of the
time it is the true one. Design it to feel settled rather than unfinished.

## The attention item

Every row in the attention surface is derived from data that already exists. No
new server fields, no invented signals.

| The row must say | Field |
|---|---|
| Which project | `sessionLabel`, falling back to `sessionBranch` |
| Who is asking | `agentName` |
| What is being asked | `body`, with `metadata.content` as subtitle |
| The choices | `metadata.options` |
| How long it has waited | `createdAt` |
| Whether the agent is blocked on it | `sessionStatus` (`waiting` means blocked on you) |
| How urgent it is declared to be | `priority` |
| **When it decides itself** | `expiresAt` |
| **What it will decide** | `metadata.defaultOption` |
| Whether that already happened | `metadata.isExpired` (`options_expired`) |

## Urgency comes from a deadline, not an adjective

The system already has a real, consequential clock that the current UI throws
away: `hiboss ask --default` makes the **server** auto-select on timeout. That is
a genuine deadline with a genuine outcome, and it outranks every other signal
because ignoring it is itself a decision.

Rank attention items by, in order:

1. **A running auto-decision** — `expiresAt` in the future and `defaultOption`
   present. Show the remaining time and name the option that will win. This is
   the only element on either client that may use a live-updating countdown.
2. **A blocked agent with no deadline** — `expiresAt` absent and `sessionStatus`
   is `waiting`. Nothing decides this for you; the agent simply stops until you
   answer. Show how long it has been stopped.
3. **Declared priority** — `critical`, then `high`. Below `high` an item is not
   an attention item at all; it belongs in the message list.

`metadata.isExpired` items are **not** attention items. They were decided without
the boss, and the honest place for them is history, labelled as auto-decided —
never silently rendered as if the boss had chosen.

## Surfaces

| Surface | Answers | Notice |
|---|---|---|
| Attention (first screen) | Does anything need me now? | Yes |
| Messages | What has been said to me? | Yes |
| Progress | What shipped? | **No** — posts never notify and never enter the inbox |
| History | What happened, and who decided it? | No |

Two unread counts on two tabs for two kinds of "someone said something" is the
defect, not the fix. There is one place for messages.

## What is removed

- **The activity heatmap and the percentage deltas.** They encode nothing the
  boss can act on and they occupy the most valuable screen real estate. If a
  statistics view is wanted later it is a separate, deliberate destination.
- **The horizontal project strip as a primary element.** Project is an attribute
  of an attention item, shown on the item. It is not a browsing surface that
  outranks the work.

## Platform split

Both clients implement the same model and the same ranking. They differ only in
what the form factor allows.

- **iOS** is glanceable and one-handed. The attention list is the root. An item
  is actionable from the list without a detail screen wherever the options are
  short enough to tap directly.
- **macOS windows** have room to show the attention list and the selected item's
  full context side by side. The Dynamic-Island panel is unchanged in purpose —
  it is the interrupt surface, and it must present the same ranking so that what
  the panel shows first and what the window lists first never disagree.

The macOS work additionally remains bound by `docs/macos-design-v2.md`: system
controls, semantic colours, no hex literals in views, no `.system(size:)`.
