# iOS design v5

v5 changes the layout and behaviour of the iOS app and redesigns the decision Live Activity.
Colours, type and the asset-catalog tokens stay as in `docs/design-v4.md`; the native-first
rules of `docs/ios-design-contract.md` still hold. The app icon is unchanged. The structure
follows macOS v5 (`docs/macos-design-v5.md`) so both apps read the same way.

## Decisions

- Watching (live panels) stays a section of Today; "All" opens the full wall. No fifth tab.
- Progress stays a tab.
- Sessions has a History button (All messages, Completed) in place of the Sessions/Messages
  segment; device requests stay in Settings › Devices. Search on Sessions covers messages.
- A session thread keeps its open decision pinned at the top, as one compact card. Where the
  decision was asked, the thread shows a one-line marker; once settled, the marker becomes the
  outcome line.
- The Live Activity colours its keyline, countdown and ring by priority, with the app's
  `PriorityColor` values (critical red, high orange, normal and low grey). The priority name sits
  beside the countdown so colour is never the only cue.
- The Live Activity state gains `defaultOption` and `askedAt`, both optional. The app starts and
  updates the activity from the message it already holds; the server only sends `end` events,
  which omit both fields.

## Packages

Each package lands on its own branch and merges only when the app is coherent with it alone.

| # | Package | Change | Status |
|---|---|---|---|
| 1 | Today | One summary line and a connection chip; the first decision is a focus card with a clamped preview, the rest are one-line rows that open the decision sheet; Watching moves above Working as compact cards with an "All" link; one-line Delivered rows | done |
| 2 | Session thread | The first pinned decision is the full card with a Signal keyline; later ones are one-line rows that expand in place; the thread marks where each was asked | done |
| 3 | Sessions | 64 pt rows grouped Needs you / Working / Idle, Idle collapses after three, History button replaces the segment | done |
| 4 | Decision sheet | One layout for every entry point: provenance, deadline, question, details, picture choices, the default line, custom answer, Open session | done (no attachment button: attachment input is not built yet) |
| 5 | Live Activity | Priority colours from the app palette, 12 pt minimum text, the first two options plus "+N more", sending/slow/failed, end states that say a default is not approval, compact and minimal presentations that say something waits | done |
| 6 | Box | Filter chips, two-column grid with thumbnails, collections row, "Added by" | in progress |
| 7 | Progress | Day-grouped timeline; a refresh failure is one line above the cached posts | in progress |
| 8 | Settings › Connection | One state card: the state in words (Live, Connecting, Disconnected, Connection failed), what it means, and on failure the server's reason with Reconnect; then the server address and the signing key. The shared connected label reads Live instead of Listening | done |
| 9 | iPad | Met by existing behaviour: two columns from 900 pt, the list at 40% up to 420 pt, the detail capped at the 640 pt reading width; TwoColumnUITests pass on a landscape iPad | done |

## Out of scope

Elements on the design canvas with no data behind them today:

- Decision fact rows (Changes / Risk / Undo): no message field carries them.
- "Answered on iPhone": a reply record carries no device.

## Rules every package keeps

- The focus decision is `TodaySnapshot.decisions.first`; no view re-ranks decisions or derives
  answerability outside `DecisionAnswerability`.
- A series gap is drawn as a gap; a percentage appears only with a real denominator.
- A timeout default is never shown as the boss's choice.
- New strings carry every locale and pass `python3 ios/scripts/i18n-audit.py`.
