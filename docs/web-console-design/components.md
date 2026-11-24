<!-- Component inventory for the HiBoss web console, with the states each component must implement.
     Part of docs/web-console-design.md; drawn in docs/design-web/states.html and the screen mockups. -->
# Web console components

Class names in parentheses are the ones used in `docs/design-web/console.css`. Every component is
drawn in at least one mockup; [`states.html`](../design-web/states.html) shows the states.

## States every interactive component has

| State | Rule |
|---|---|
| Default | As drawn. |
| Hover | Pointer devices only. Rows and bordered buttons take `--surface-2`; the filled button drops to 88 % opacity; navigation items and chips take `--neutral-soft`. No movement, no shadow. |
| Focus | `:focus-visible` draws a 2 px `--live` outline with a 2 px offset on every focusable element, in both themes. Never removed, never replaced by a colour change alone. |
| Pressed | Buttons scale to 98 %; skipped under reduced motion. |
| Disabled | 45 % opacity, `not-allowed` cursor, the native `disabled` attribute. A disabled control states why in adjacent help text ("No changes to save."). A control the role cannot use is absent instead. |
| Loading | A control that started a request shows a spinner before its label, changes the label to the action in progress ("Sending…"), sets `aria-busy` and ignores further activation. Its size does not change. |
| Error | The message appears next to the control that caused it, in `--danger`, with `role="alert"`. Typed text and choices are kept. |

## Shell

| Component | Description | States and rules |
|---|---|---|
| Sidebar (`.sidebar`, `.nav`) | Brand, primary items, Manage and Admin groups, footer with the connection chip and server host. | Current item: `--neutral-soft` fill, weight 600, `aria-current="page"`. Today shows the open-decision count in Signal; "Loading" until the list has loaded; no badge at zero. Groups the role cannot open are absent. |
| Tab bar (`.tabbar`) | Four destinations below 1024 px. | Current tab in Ink at weight 600; others `--text-2`. Today carries the same count as a badge. Labels never truncate: they are the four shortest strings in the product. |
| Page header (`.head`) | Optional eyebrow (date, or a back link), the screen title, then tools: at most one screen action, and the account button. | One `h1` per screen. No subtitle. |
| Account menu | Opened by the account button: name and role, Devices, Language, Appearance, Sign out. | A menu button with `aria-expanded`; Escape closes it and returns focus. |
| Connection chip | "Live · updated 6s ago", "Connecting…", "Offline · last updated 09:12". | Settled dot only when the stream is accepted by the server. Offline uses Signal and adds a banner with Retry at the top of the content. |

## Attention and status

| Component | Description | States and rules |
|---|---|---|
| Status chip (`.chip`) | Dot and count: "2 need you", "3 working". On Today each links to its section. | Count unknown: "Loading". Zero "need you" is not shown. |
| Filter chip (`.chip[aria-pressed]`) | A toggle in a filter row. | Selected: Ink fill. The row scrolls sideways on a phone and never wraps to more than two lines on a desktop. |
| Badge (`.badge`) | A short label on a soft fill: neutral, Signal ("Needs you"), Live ("Integration"), Settled ("Answered", role Admin), danger ("Failed"). | Text only, never a bare colour. One badge per row; a second fact goes into the row's second line. |
| Freshness label | "updated 9s ago" beside any live value. | Updates in place once per second up to a minute, then once per minute. Not announced to screen readers on each tick. |
| Banner (`.banner`) | A full-width note inside a card or above content. | Neutral, Signal (deadline, offline), Settled (the boss's answer, a success that must be read, such as a created key), danger (failure). At most one per card. |
| Monogram tile (`.tile`) | First letter of the project, or up to three letters for an agent or file type. | Tint follows the bucket: Signal for needs you, Live for working, neutral otherwise. Decorative: `aria-hidden`. |

## Decisions

| Component | Description | States and rules |
|---|---|---|
| Decision card (`.card` with `.prov`, `.q`, `.opts`) | In order: provenance line (project · branch · agent) with the deadline in Signal or the words "No deadline"; the question; what it changes; options; the default line. | **Open:** options enabled. **Checking:** options disabled and labelled "Checking…" until the required-input list has loaded. **Submitting:** the chosen option shows the spinner, the others are disabled. **Failed:** danger banner with "Try again"; the choice is kept. **Resolved:** options are replaced by a resolved banner. **Read-only (viewer):** options are listed as plain text with the view-only banner. |
| Option button (`.btn.opt`) | Label and optional description, left aligned, full width of its column. Two short options sit side by side; more than two, or any with a description or image, stack. | First option filled Ink, the rest bordered. All options in a group have the same width. An option image sits above its button and opens in the media viewer. |
| Default line (`.default-line`) | "No answer in 18 min picks “Not yet”. That is not approval." | Fixed sentence. Shown only on an open decision with a default; never on a resolved card. |
| Resolved banner | "You chose Deploy · 09:31" on `--settled-soft`. | Timeout default: "Default picked · not approval · “Not yet” at 09:42" on `--neutral-soft`. Closed elsewhere or by the server's 409: "No longer open". Expired without a default: "Expired at 09:42 with no answer. Nothing was chosen." |
| Custom answer field | A text area labelled "Custom answer to: <question>" with a bordered Send button. | Empty: Send disabled. Ctrl/⌘ + Enter sends while the field has focus. A draft is kept per decision ID across navigation. |

## Lists and reading

| Component | Description | States and rules |
|---|---|---|
| Grouped rows (`.rows`, `.row`) | A Surface card of rows divided by hairlines. A row has a leading tile, a title, a second line and a trailing time. | The whole row is one link. Selected in a split view: `--live-soft` and `aria-current="true"`. Titles and second lines truncate to one line with the full text in the detail. |
| Session row | Tile, "project · branch", "agent · current step or last message", relative age. | Needs you rows show the deadline in place of the age. |
| Message row | Tile, title, "project · agent" or "integration name · integration", time, and at most one badge (Needs you, Answered). | An open ask shows Needs you; a resolved one shows its outcome in the second line. |
| Thread message (`.msg`) | Sender name, date and time, then the content. The boss's own messages sit on `--surface-2` with their delivery state ("Read 07:31"). | Long content (over 1,200 characters or 14 lines) collapses to a preview with "Show full message". |
| Reply field (`.composer`) | States its target above the field ("Replying to: …" or "Custom answer to: …"), then the text area and Send. | No eligible target: the field is disabled and says why. If a newer agent message arrives while typing, the target stays and "Reply to the newer message" is offered. |
| Markdown, code, copy block, embed card | See [content and flows](content-and-flows.md). | |
| Key–value list (`.kv`) | Label column and value column. | The label column is at least 96 px. A missing fact is omitted, never shown as a dash. |
| Table (`.table`) | Column headers in footnote style; rows divided by hairlines. | Below 768 px each row becomes a labelled stack. Sortable only where the screen spec says so. |
| Tabs (`.tabs`) | Sections of one screen, each with its own URL. | Current tab underlined in Ink. The row scrolls sideways when it does not fit. |
| Disclosure (`details`) | Hides secondary content: More filters, Details, Completed sessions. | Native element; open state is kept per screen for the visit. |
| Pager | "Load 50 more" under a list, with "Showing 50 of 248". | Loading state on the button; the list does not jump. Audit uses previous and next with the range. |

## Forms and actions

| Component | Description | States and rules |
|---|---|---|
| Button (`.btn`) | Filled (`.primary`), bordered, quiet text (`.quiet`), destructive label (`.danger`), small. 44 px tall; small is 32 px with a pointer and 44 px on touch. | Labels are verbs that name the result ("Create key", "Revoke key"), and wrap instead of truncating. |
| Text field, select, text area (`.input`, `.select`) | A visible label above the control; help text below; 44 px tall; 16 px text. | Invalid: 2 px danger outline, `aria-invalid`, and a message tied by `aria-describedby` that says how to fix it. Validation runs on blur and on submit, not on each key. |
| Switch (`.switch`) | An immediate on or off setting, saved on change. | On is Settled. While saving it is disabled; on failure it returns to the previous position with an error next to it. |
| Checkbox | A grant in the access grid; "Group by session". | Native control with an accessible name that includes the row and the column. |
| Shown-once secret | A Settled banner ("Copy it now. It is shown only once.") above a copy block with the value. | Leaving the screen asks for confirmation until Copy was used. If the clipboard is unavailable the value stays selectable and the message says to copy it by hand. |
| Confirm dialog (`.dialog`) | For destructive or irreversible actions only: revoke, archive, delete, merge, rotate. Title is the question with the object's name; body states the consequence; the confirm button repeats the verb. | Native `dialog` element, focus starts on Cancel, Escape cancels. The confirm button is bordered with a danger label, never filled. |
| Status message (`.toast`) | For a result that has no place on the page, such as a removed row. | `role="status"`, bottom centre above the tab bar, stays until the next action or six seconds, whichever is longer, and never carries the only copy of an error. |

## Page states

| Component | Description |
|---|---|
| Skeleton (`.skel`) | First load only. It has the final layout's rows and heights, so content does not shift. The region sets `aria-busy`. |
| Empty state (`.empty`) | A title that states the fact ("No sessions yet"), one sentence on what makes content appear, and one action when there is one. No illustration. |
| Filtered-empty | "No messages match" with a "Clear filters" action. Distinct from empty. |
| Error state | "Sessions could not be loaded", the cause in plain words with the status code, and "Try again". If earlier data exists it stays visible under a Signal banner with its load time. |
| Forbidden | "Your role cannot open this" with the role named. Used when a URL is opened directly. |
| All clear (`.scene`) | The island scene (day in light, night in dark) above "Nothing needs you" and the live line. Today only, and only when there are no open decisions, the connection is live and coverage is complete. Otherwise Today says what it cannot see. |
