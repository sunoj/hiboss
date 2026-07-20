# macOS Client — Design v2 Spec

Source of truth: Claude Design project `7eb92e64`, file `macOS HiBoss Island.dc.html`,
built on the `ming's work` design foundations (`colors_and_type.css`).

This document is the implementation contract for the macOS client redesign. Where this
document and a screenshot disagree, this document wins.

## 1. Design language

"朴素 / plain": near-monochrome, flat and matte, hairline structure, generous whitespace,
one quiet accent at most. Prefer borders over shadows. Modest, slightly squared radii.

### Palette (dark — the macOS client is always dark)

| Token | Value | Use |
|---|---|---|
| `ink` | `#ECEBE7` | primary text |
| `ink-2` | `#A7A6A0` | secondary text |
| `ink-3` | `#7A7974` | muted / captions |
| `ink-4` | `#54534F` | faint / disabled |
| `paper` | `#161614` | window background |
| `surface` | `#1E1E1C` | cards, panels |
| `surface-2` | `#262624` | filled control / hover |
| `surface-3` | `#2F2F2C` | pressed |
| `line` | `#2C2C29` | hairline |
| `line-2` | `#3A3A36` | stronger hairline |
| `pos` | `#5E7257` | positive / connected |
| `neg` | `#97574B` | negative |
| `warn` | `#9A7B43` | caution |

Priority accents (used only as small dots/labels, never as fills):
`critical #C46A5A` · `high #C79A57` · `normal #7A7974` · `low #54534F`.

Status-light green for the live/connected pulse: `#6E8A5E`.

### Type

Sans is the system font (SwiftUI default) — the web mock uses IBM Plex Sans, but on macOS
use the platform font rather than bundling a face. **Monospace is load-bearing**: use
`.monospaced` for timestamps, priority labels, server URLs, latency, and status chips.

| Role | Size / weight |
|---|---|
| pane title | 18 semibold |
| section header | 13 semibold |
| row title | 13 semibold |
| body | 13 regular |
| caption | 12 regular, `ink-3` |
| mono label | 11 medium, uppercase, tracked +0.06em, `ink-3` |

Radii: 6 small controls · 8 segmented/pill · 11 cards and rows · 14 window.

## 2. History window (main window)

The main window. Native title bar (see §5 — the design mock's in-window tab switcher is
replaced by native macOS conventions).

**Toolbar row** — segmented filter `All | Unread N | Blocking`, spacer, search field
("Search messages…"). Connection state lives in the title bar accessory as a pulsing dot
plus mono label (`SSE connected` in `pos`, otherwise `ink-3`).

**Message rows** — 11pt radius, hairline border, `surface-2` fill when unread/selected,
transparent otherwise. Unread rows carry a 3pt full-height accent bar in the priority
colour on the leading edge.

Row layout, leading to trailing:
- 30x30 avatar tile, radius 8, `#26221F` fill, `line-2` border, 2-letter mono monogram
  derived from the agent name. The boss's own messages use a gradient tile and `Me`.
- Header line: agent name (13 semibold) · direction glyph · priority + mode mono label ·
  spacer · timestamp (10 mono, `ink-4`).
- Body line: 13pt, `ink` when unread and `ink-2` when read, max 2 lines, truncated.
- Footer chips: delivery status chip (bordered, 10 mono — `● delivered` in `warn`,
  `✓ replied` in `pos`, `● read` in `ink-3`) and any reactions.

Direction glyphs: `arrow.right` agent→boss · `arrow.left` boss→agent ·
`arrow.left.arrow.right` agent↔agent (show the peer name for this case).

Empty and failure states keep `ContentUnavailableView`.

## 3. Settings window

Native `Settings` scene (⌘,), sidebar + detail, 210pt sidebar.

Panes, in order: **Connection** · **Notifications** · **Channels & Routing** ·
**Quiet Hours** · **Presentation** · **System & Doctor** · **About**.

Every pane: 18 semibold title, then a 13pt `ink-3` subtitle describing the pane, then
content. Rows are label + caption on the leading side, control trailing, separated by
hairlines. Footer strip across the bottom: live status on the left (pulsing dot + mono
`Listening`), primary button `Save & Connect` on the right.

### Connection
Server URL, boss token (secure). A connection status card at the top: pulsing dot, bold
state line ("Connected · daemon running"), mono detail line (`host · 38ms`), an `SSE`
mono chip, and a `Reconnect` button.

### Notifications
`Option display` segmented control (Island / Window / Banner), `Critical bypasses Do Not
Disturb` toggle, `Show menu bar icon` toggle.

### Channels & Routing
The priority routing matrix — a bordered table, header row on `surface-2`:

```
PRIORITY   | Discord | Telegram | API |            Sound
critical   |    ●    |    ●     |  ●  |          Alarm ⌄
high       |    ○    |    ●     |  ○  |          Glass ⌄
normal     |    ●    |    ○     |  ○  |            Pop ⌄
low        |    ●    |    ○     |  ○  |           None ⌄
```

Each cell is a 20pt toggle circle: on = `pos`-tinted fill with `#6E8A5E` border and an
`#8FB07E` inner dot; off = hollow with a `line-2` border. The priority label is a mono
name preceded by an 8pt rounded square in the priority colour.

Channel enablement persists to the server (`routing` in boss preferences). **Sound is a
per-priority client-side preference** and does not go to the server. Changing a sound
previews it — choosing a sound you cannot hear is choosing blind.

### Quiet Hours
Master toggle, caption "Silence normal & low; critical still alerts." Then a start→end
time range control and a 7-day selector (M T W T F S S, 26pt squares, radius 7; selected
= `ink` fill with `paper` text, unselected = `surface-2` with `line-2` border). A
timezone picker. A `critical_bypass` toggle.

### System & Doctor
Daemon/hook health, server reachability, last error — read-only diagnostics.

### About
Version, build, links.

## 4. Island / option surface

Unchanged in behaviour. Two corrections:

1. **Window mode corner defect.** `IslandPanelController.configureWindow()` creates an
   opaque `.titled` NSWindow whose square darkAqua backdrop shows through outside the
   SwiftUI `RoundedRectangle(cornerRadius: 18)` — visible as black square corners at the
   bottom of the panel. Window mode must become a transparent, borderless, rounded,
   draggable floating panel: `backgroundColor = .clear`, `isOpaque = false`, corners
   masked, movable by its background. `configurePanel()` (the island) already does this
   correctly and is the reference.
2. Island bottom corner radius is 24 and its background shape and expiry-band path must
   describe the *same* curve, so the fill never protrudes past the stroke.

Motion: appears from the top with a spring; the timer counts down; choosing an option
shows a "Replied" confirmation then retracts; if answered on Discord/Telegram first it
fades to "Resolved elsewhere."

## 5. Deliberate deviations from the mock

- The mock puts History and Settings in one window behind a top segmented switcher. We
  use macOS conventions instead: History is the main window, Settings is a native
  `Settings` scene opened with ⌘,.
- The mock renders IBM Plex Sans; we use the system font, keeping monospace for the
  textural mono labels.
- The mock's macOS menu bar and traffic-light chrome are drawn by the platform, not by us.
