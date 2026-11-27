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
| 3 | Today focus card | The first open decision gets a focus card with collapsible details; the rest are one-line rows; the inspector shows context, not a second copy of the choices | planned |
| 4 | Session outcomes | Every settled decision in a thread states how it ended in one line: the answer, where and when, or "Expired without an answer" | done (window run pending) |
| 5 | Inline failures | A failed refresh is one line above the content already loaded; Settings › Connection names the state and the server's reason | planned |
| 6 | Box | Filter chips, newest item preselected, "Added by" badge, a date on every row | waits for `feat/box-v2-macos` |

## Sidebar rows

Section headers are rows inside one `ForEach`, not `Section`s (`SidebarSessionRow`). A session
changes state often (an arrival moves it from Idle to Working); across a `Section` its row would
be rebuilt and the list would re-send the selection, which marks a background arrival read.

## Out of scope

- Decision fact rows (Changes / Risk / Undo): no message field carries them.
- A menu bar popover: the current status item menu was not compared with the design.

## Rules every package keeps

- The focus decision is `snapshot.today.decisions.first`. No package re-ranks decisions or
  derives answerability outside `DecisionAnswerability`.
- A series gap is drawn as a gap; a percentage appears only with a real denominator.
- New strings carry every locale and pass `python3 macos/scripts/i18n-audit.py`.
