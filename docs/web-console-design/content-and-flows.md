<!-- Message rendering, first-run connect flow, accessibility, motion and i18n for the web console.
     Part of docs/web-console-design.md; the rendering rules restate docs/message-format.md for the web. -->
# Web console content and flows

## Message rendering

[Message format](../message-format.md) is the contract; the console renders what the apps render.
Mockups: `messages.html`, `decision.html`.

**Which text.** The title is `body`, bounded to a heading on display. The details come from
`metadata.rich_content` when the server sent it, otherwise from `metadata.content`. A message
with neither shows only its title. Options come from the structured option array, one button per
entry; option text is never split or parsed.

**Markdown subset.** Paragraphs, ATX headings, emphasis, inline code, links, ordered and
unordered list items, blockquotes, fenced code, copy blocks. Not rendered as rich blocks: tables,
nested-list indentation, embedded images; they appear as their source text. HTML in a message is
shown as text and never inserted into the page. Markdown attachments (`.md`, `.markdown`) open in
a preview that also renders tables, each in its own horizontal scroll area.

| Element | Rule |
|---|---|
| Headings | All levels render in `--t-headline`. A message never produces an `h1` or `h2`; the screen owns those. |
| Links | Live colour and **always underlined**. A bare web URL is a link; trailing punctuation and CJK text after it stay outside; balanced brackets inside it are kept. Links open in a new tab with `rel="noopener noreferrer"`. Only `http`, `https` and `mailto` are links; any other scheme is text. |
| Inline code | Monospace on `--surface-2`. |
| Fenced code | Monospace on `--surface-2`, 12 px radius, no wrapping, horizontal scroll inside the block, focusable so it scrolls by keyboard. No syntax colouring. |
| Blockquote | A 3 px hairline bar and secondary text. |
| Long messages | Over 1,200 characters or 14 explicit lines: a preview of 600 characters or eight lines, cut at a grapheme boundary, with "Show full message" and "Collapse message". A match from search expands the message. |

**Copy block.** A closed fence whose info string starts with the exact word `copy`; the rest of
the line is the label.

- Drawn as a bordered block on `--surface-2`: a header row with the label, when there is one, and a
  Copy button, then the text in monospace.
- The text wraps (`pre-wrap`, break anywhere) and is never truncated or scrolled, so the whole
  value is visible at 375 px.
- Copy writes the block text exactly as written, with CRLF as LF. The button reads "Copied" for
  two seconds and the change is announced through a live region. If the clipboard is refused the
  text is selected and the block says "Press Ctrl/⌘ + C to copy".
- `copyright`, `copy-x`, `Copy`, and a block with no closing fence are ordinary code with no button.

**Embed card.** In `rich_content`, a closed fence whose info string is exactly `hiboss-embed`
holds one card as one line of JSON. Only the server writes these blocks.

- Layout, top to bottom: author, title (a link when `url` is set), description, fields, image,
  footer. A `thumbnail` sits at the top right, 64 px. The card is at most 560 px wide.
- **Edge.** A 4 px left edge in the card's `color`. The colour is the sender's data: it is used
  on the edge only, never for text or fills, and never read as Signal, Live or Settled. With no
  colour the edge is `--border`.
- **Fields.** Consecutive inline fields share rows of three equal columns; a field that is not
  inline takes a full row. The name is weight 600 and the value is secondary text below it. Values
  wrap anywhere, so three columns hold at 375 px (about 90 px each); a row is never scrolled.
- **Footer.** Footer text, then the `timestamp` in the reader's local time ("Today 08:47"), in
  caption style, with the full date and time in a `title` and a `time` element.
- Text values are rendered with the Markdown subset and with cards disabled, so a card never
  contains a card. A block holding only `text` is plain Markdown with no card chrome.
- A block that is unclosed or whose JSON does not decode renders as ordinary code.
- A card is an `article` whose accessible name is "Card: <title>"; fields are a description list.
- Messages from an integration show the Integration badge and have no reply field, because the
  server refuses the reply.

**Attachments.** A row with a type tile, the file name and its kind and size. Images show a
thumbnail and open in one viewer with zoom, next and previous, and Escape to close. Option images
use the same viewer.

**Times.** Relative up to one hour ("12 min ago"), then the clock time today, "Yesterday", then
the date. Every time has its full local date and time in a `time` element's `title` and
`datetime`. Deadlines count down in minutes, and in seconds during the last minute.

## First run: connect to this server

The console is served by the server it talks to, so it never asks for the server first.

1. **Probe.** On load the console calls its own origin. It shows "<host> is reachable" with a
   Settled dot, or "<host> did not answer" with Retry. Nothing else is asked while the probe fails.
2. **Pairing code (default path).** One field and one filled button, Connect. The help text says
   where a code comes from: a paired iPhone or Mac app, valid five minutes, used once. The console
   redeems the code itself with the device label "Web console · <browser> on <OS>", stores the
   returned token, loads the boss and opens Today.
3. **Boss token (disclosure).** "Use a boss token instead" reveals a password field. This is the
   path for a person created in People & access.
4. **Nothing paired yet (disclosure).** States that the first boss is created from the machine
   that deployed the server, with the command in a copy block. The bootstrap secret is never typed
   into the browser.
5. **Different server (disclosure).** Reveals the Server URL field, prefilled with the origin.
   Used by local development and by a console hosted apart from its server.

Rules:

- The screen has the language select and the appearance toggle, because the reader has no
  account menu yet. The island scene is used here as onboarding art.
- Errors appear under the field that caused them and say what to do: "That code has expired.
  Create a new one in the app.", "This token was revoked.", "The server refused this browser's
  origin."
- After connecting, a session that the server rejects (401) returns to Connect with "You were
  signed out: this browser's access was revoked."; the unsent draft, if any, is kept for the visit.
- The closing note states that this browser is listed as its own device and can be revoked.
- A first-time admin with no agents lands on Today with one card instead of the all-clear scene:
  "Connect your first machine", linking to Agents › Join requests with the install command in a
  copy block.

## Accessibility

- **Contrast.** Every text token meets 4.5:1 on every fill it is used on, in both themes
  (lowest pairs: Settled on Ground 4.5, Signal on SignalSoft 4.7 in light; Signal on SignalSoft
  5.2 in dark). Field outlines meet 3:1. State is never carried by colour alone: every dot has
  words beside it and every badge is text.
- **Focus.** Visible 2 px Live outline on every focusable element. Opening a detail on a phone
  moves focus to its title; going back returns focus to the row. A dialog traps focus and returns
  it to its opener. A skip link is the first focusable element.
- **Keyboard.** Everything works without a pointer. Tab order follows reading order. Enter opens
  a row; Escape closes a menu, dialog or viewer; Ctrl/⌘ + Enter sends from a focused text area.
  There are no single-key shortcuts except `/` to focus search on Messages and Sessions, which is
  off while a field has focus. Options are ordinary buttons in order; no option is preselected by
  focus, and no shortcut answers a decision.
- **Structure.** One `h1` per screen; section headers are `h2`; cards are `article` with an
  accessible name; navigation regions are labelled; the transcript is a `feed`; tables have
  column headers with `scope`.
- **Names.** Icon-only buttons have labels ("Switch between light and dark", "Account: Robin,
  admin"). A reaction button's name is its meaning ("React: seen"). A grid checkbox is named by
  person and agent. A switch is named by channel and agent. Decorative tiles and dots are hidden.
- **Live regions.** New decisions are announced once, politely ("New decision from atlas-api").
  A resolved decision announces its outcome. Freshness ticks and countdowns are not announced;
  a deadline is announced at five minutes and at one minute.
- **Zoom and reflow.** No loss of content or function at 200 % text size or at 320 px of width.
- **Forms.** Visible labels, never placeholder-only; errors tied to fields; required fields
  marked in text.

## Motion

| Where | Motion | Duration |
|---|---|---|
| Hover and pressed | Fill change; 98 % scale on press | 100 ms |
| Switch | Thumb slides | 150 ms |
| A decision arrives | The card fades in and the list makes room | 200 ms ease-out |
| A decision resolves | Options cross-fade to the resolved banner; the card stays in place for the visit and leaves Your call on the next load | 200 ms |
| Detail opens on a phone | None; it is a navigation | — |
| Dialog and menu | Fade and 4 px rise | 150 ms |
| Skeleton, spinner | Opacity pulse; rotation | continuous |
| All-clear scene | Still | — |

Under `prefers-reduced-motion: reduce` every transition and animation is removed; the spinner
becomes the label change alone. Nothing moves to draw attention, nothing auto-scrolls, and a
countdown changes its digits only.

## Internationalisation

Dictionaries exist for English, Simplified Chinese, Japanese and Korean; English is the key
source. The design must also hold a language about 40 % longer than English.

- **No fixed widths on text.** Buttons, chips, tabs and badges size to their label. Buttons wrap
  to two lines instead of truncating; paired option buttons stack when either label wraps.
- **Navigation.** Sidebar labels may wrap to two lines within 244 px. Tab bar labels are one
  word in every language; a language without a short form uses the icon with the full label as
  the accessible name.
- **Rows.** Only titles and second lines truncate, always with the full text one step away.
  Labels, badges and times never truncate.
- **CJK.** Use `line-break: strict` and `word-break: normal` with `overflow-wrap: anywhere` for
  long tokens; add `word-break: keep-all` for Korean. No letter-spacing on CJK text; the large
  title's negative tracking applies to Latin script only. No italics for emphasis in CJK:
  emphasis renders as weight 600. Set `lang` on `<html>` from the chosen locale so the font stack
  picks the right glyph variants, and on message content only when its language is known.
- **Line height.** The type tokens leave room for CJK and for stacked diacritics; do not tighten
  line heights per locale.
- **Sentences are whole strings with parameters.** "No answer in {time} picks “{option}”. That
  is not approval." is one key; word order differs by language. Counts use the plural helper.
- **Dates, times and numbers** come from `Intl` with the chosen locale; relative times from
  `Intl.RelativeTimeFormat`. Quotation marks around option names are part of each translation.
- **Not translated:** agent, project, session and integration names, message content, key and
  token prefixes, command text in copy blocks.
- **Direction.** The four languages are left to right. Spacing uses logical properties
  (`margin-inline`, `padding-inline`, `inset-inline`), so a right-to-left language needs no
  layout rewrite.
- New strings in this design are added to all four dictionaries in the same change; the i18n
  test fails on a missing key.
