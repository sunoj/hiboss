# macOS Client — Native Design Contract

> **This supersedes the palette-driven contract used for the first pass.** That version
> specified a fixed hex palette, banned system colours, and declared the client
> "always dark". The result was judged "像一个网页套壳" — a web page in a window — and that
> was a fair verdict: a light system title bar sat on a hardcoded near-black body, and every
> control was hand-drawn. The information architecture below was fine. The *execution*
> rules have been replaced.

## 0. The rule that overrides everything

**If AppKit or SwiftUI has a control for it, use that control.** Do not hand-draw chrome.

A hand-built segmented control, a `TextField` styled to look like a search box, a `List` row
rebuilt as a bordered card — each is individually defensible and collectively reads as "not
a Mac app". Native controls bring focus rings, keyboard traversal, accessibility, contrast
settings, right-click behaviour, the user's accent colour, and appearance changes for free.
Every one of those was missing from the first pass.

If you believe a native control genuinely cannot express something, say so in your final
report and explain why. Do not silently reimplement it.

## 1. Colour

**Never write a hex value in a view.** Use the semantic system colours:

| Need | Use |
|---|---|
| primary text | `Color.primary` / `.foregroundStyle(.primary)` |
| secondary text | `.secondary` |
| dimmer still | `.tertiary`, `Color(nsColor: .tertiaryLabelColor)` |
| control / card background | `Color(nsColor: .controlBackgroundColor)` |
| window background | `Color(nsColor: .windowBackgroundColor)` |
| hairline | `Color(nsColor: .separatorColor)` or a plain `Divider()` |
| selection | `Color(nsColor: .selectedContentBackgroundColor)` — or just let `List` do it |
| elevated / floating surface | `.background(.regularMaterial)` |

`DesignTokens` now contains **only** priority accents and the live-connection tint, because
those carry meaning the system has no colour for. It is already written — use it, and do not
extend it without justification.

**The window follows the system appearance.** Do not set `NSAppearance` on the main or
Settings window, and do not force a dark background. The only always-dark surface is the
floating island panel (`IslandPanelController.configurePanel`), a deliberate self-contained
overlay that is out of scope here.

## 2. Type

Use semantic text styles — `.font(.body)`, `.headline`, `.callout`, `.subheadline`,
`.caption`. **Do not use `.system(size:)`**; the first pass used it 29 times, which freezes
type against the user's text-size and accessibility settings.

Monospace is still welcome where it means something — timestamps, IDs, server URLs, latency
— via `.monospaced()` or `.font(.system(.caption, design: .monospaced))`. But uppercase
tracked mono labels used as decoration are a web affectation; drop them.

## 3. History window

Native window, native title bar, appearance follows the system.

- **Search** — `.searchable(text:placement:)`. Not a hand-built field. It puts the search
  field in the toolbar where Mac users expect it, and gives ⌘F for free.
- **All / Unread / Blocking** — `Picker` with `.pickerStyle(.segmented)`, placed in
  `.toolbar` as a `ToolbarItem`/`ToolbarItemGroup`.
- **Connection status** — a small toolbar item: SF Symbol plus short label, `.secondary`
  when idle, `DesignTokens.live` when connected. Not a floating pill.
- **Refresh** — `ToolbarItem` with `Image(systemName: "arrow.clockwise")`.
- **Rows** — a real `List`. Let `List` own selection, alternating background, inset spacing
  and hover. **No card borders, no per-row rounded rectangles, no manual highlight.** Row
  content: agent avatar, name as `.headline`, body as `.body` truncated to two lines, and a
  trailing `.secondary` timestamp. Express unread the way Mail does — a subtle leading
  indicator or `.badge()` — not a coloured border.
- **Priority / direction** — small SF Symbols tinted with the priority accent, each with an
  accessibility label. Not `NORMAL · ASYNC` uppercase mono text.
- **Avatar** — keep the two-letter monogram, but size it to the row and use
  `.controlBackgroundColor` with a `Circle()` or small `RoundedRectangle`, matching Mail and
  Messages rather than a bordered web square.
- Keep `ContentUnavailableView` for empty and failure states — already the native answer.

## 4. Settings window

Target look: **macOS System Settings**.

- Keep the native `Settings` scene (⌘,) and `NavigationSplitView`.
- Sidebar: `List(selection:)` with `.listStyle(.sidebar)` so it gets real sidebar vibrancy.
  Each row is a `Label(_:systemImage:)`. Do not set a background colour on it — the vibrancy
  is the point, and painting over it is what flattened the first pass.
- Each pane: `Form { Section { … } }` with `.formStyle(.grouped)`. That gives native grouped
  rows, correct label/control alignment and row heights for free — replacing the hand-built
  `SettingsRow` stack.
- Controls: `Toggle` (native switch), `Picker`, `TextField`/`SecureField` with standard
  styling, and `DatePicker(displayedComponents: .hourAndMinute)` for quiet-hours times
  instead of a hand-parsed text field.
- The routing matrix is the one genuinely custom widget. Build it as a `Grid` of native
  `Toggle`s (`.toggleStyle(.checkbox)`) with a real header row — not hand-drawn circles.
- `SettingsNotAppliedNotice` stays on Channels & Routing and Quiet Hours (those preferences
  are stored but not enforced — see `boss-preferences-enforcement.md`). Re-express it
  natively: SF Symbol + `.secondary` `.callout`, or a `Section` footer.
- The footer's "Save & Connect" is a standard `.borderedProminent` button; status text beside
  it is `.secondary`.

## 5. Information architecture (unchanged from the first pass)

Settings panes, in order: **Connection · Notifications · Channels & Routing · Quiet Hours ·
Presentation · System & Doctor · About**.

Row content, filters, unread counting and the "blocking" definition are unchanged and are
already covered by passing tests in `HistoryLogicTests` / `SettingsLogicTests` — keep that
logic and those tests. This pass changes presentation only.

## 6. Verification

`swift build && swift test` in `macos/`. Beyond green tests, check by reasoning: switching
the system between light and dark must carry every surface with it, with no hardcoded colour
left stranded. Grep your own diff for `system(size:` and `Color(hex:` — both should return
nothing outside `DesignTokens.swift`.

Then **build the app bundle and look at it** (`bash macos/scripts/build-app.sh`). This is not
optional for visual work: three real defects in the first native pass survived a clean build,
a clean diff and 61 green tests, and were obvious the moment the app was on screen — a
toolbar item clipped at `.navigation`, an avatar filled with `controlBackgroundColor` that
was invisible against a white list, and a meaningless glyph drawn on every normal-priority
row.

## 7. Status — where the next UI round picks up

Shipped 2026-07-20 as PRs #5 (History), #6 (Settings) and #7 (visual fixes), head `4732a6f`,
installed to `/Applications/HiBoss Island.app`. `server/` is byte-for-byte unchanged by the
whole redesign — **no deploy is required**.

Open items:

1. **The island overlay's bottom corner is code-verified only.** Window mode was fixed (an
   opaque `NSWindow` painted its square backdrop outside the SwiftUI rounding) and the
   island's expiry band now traces true circular arcs matching its fill — but the option
   panel renders only when a live question arrives, so nobody has actually seen it. Confirm
   before assuming it is fixed.
2. **Do not remove `SettingsNotAppliedNotice`** from Channels & Routing or Quiet Hours. Those
   preferences persist to the server and nothing enforces them yet — see
   `boss-preferences-enforcement.md`. The notice is deliberate; it goes when enforcement
   ships, not before.
3. General UI polish continues in a later session at the user's request.
