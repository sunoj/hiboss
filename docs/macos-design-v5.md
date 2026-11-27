# macOS design v5

v5 changes the main window's layout and behaviour. Colours, type and `DesignTokens`
stay as they are. The notch Island and the menu bar icon keep their look; the Island only
gained collapsible message details (`OptionMessageDetails`).

## Packages

Each package lands on its own branch and merges only when the app is coherent with that
package alone.

| # | Package | Change | Status |
|---|---|---|---|
| 1 | Sidebar | Sessions grouped Needs you / Working / Idle; History section (All messages, Completed, Device requests); Settings moves from the sidebar footer to the toolbar | done |
| 2 | Watching | Live panels become a sidebar destination; Today keeps a short summary that links to it | done (page screenshot pending) |
| 3 | Today focus card | The first open decision gets a focus card with collapsible details; the rest are one-line rows; the inspector shows context, not a second copy of the choices | done (window run pending) |
| 4 | Session outcomes | Every settled decision in a thread states how it ended in one line: the answer, where and when, or "Expired without an answer" | done (window run pending) |
| 5 | Inline failures | A failed refresh keeps the loaded content; Settings › Connection names the state and the server's reason | met by existing behaviour (see below) |
| 6 | Box | Filter chips, newest item preselected, "Added by" badge, a date on every row | rows already carry a date and "Added by"; chips and preselection wait for `feat/box-v2-macos` |

## Sidebar rows

Section headers are rows inside one `ForEach`, not `Section`s (`SidebarSessionRow`). A session
changes state often (an arrival moves it from Idle to Working); across a `Section` its row would
be rebuilt and the list would re-send the selection, which marks a background arrival read.

## Today focus

`TodayDecisionFocus` picks the full card: the selected decision, else the first. Answer on a row
expands that decision where it stands, so the order stays the snapshot's. The inspector always
describes the focus decision and has no choices (`AttentionDetail` without `onChoose`).

## Inline failures

v4 already does what package 5 asks, so v5 adds no code for it. Every cached surface (Box,
Progress, the panel wall in Watching, Device requests, the message toolbar) keeps its content on a
failed refresh and shows `CachedReadStatus`: "Update failed" with Retry in a reserved slot. A full
"Unavailable" page appears only when nothing was ever loaded. Settings › Connection shows the state
and the server's message; a 401 reads "That Boss Token was rejected…". Two differences from the
canvas: the reason is in the status's tooltip, not in a row above the content (an inserted row would
move the content, which `BoxStableRefreshTests` and `ProgressPolishSnapshotTests` guard against), and
the 401 copy says to check the token rather than to pair again.

## Out of scope

- Decision fact rows (Changes / Risk / Undo): no message field carries them.
- A menu bar popover: the current status item menu was not compared with the design.

## Rules every package keeps

- Without a selection the focus decision is `snapshot.today.decisions.first`. No package re-ranks
  decisions or derives answerability outside `DecisionAnswerability`.
- A series gap is drawn as a gap; a percentage appears only with a real denominator.
- New strings carry every locale and pass `python3 macos/scripts/i18n-audit.py`.
