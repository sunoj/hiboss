# macOS Workspace Design

The main window is a native workspace for answering agents and following task
progress. The sidebar uses system selection, typography, and appearance; the
workspace uses one accent color and plain decision rows.

## Information Hierarchy

- **Workspace:** Dashboard, Needs You, All messages, and Completed.
- **Decision filters:** Automatic, Waiting on you, and High priority.
- **Sessions:** searchable session history, identified by stable session IDs.
- **Dashboard:** a ranked preview of three decisions followed by the live panel wall.
  View all opens the complete queue. Panel filters retain Active, Needs input,
  Results, and Archived, including their existing questionnaire workflows.

These filters overlap. High priority can include timed and waiting questions; their
counts must not be added to produce a total. Counts cover loaded recent messages,
not lifetime activity. Unknown counts use a dash. Session search matches labels
and agent names without changing destination counts or the selected session.

## Decision Rules

An unanswered agent question with choices belongs in Needs You, even before its
session heartbeat reports waiting. Ranking remains automatic deadlines first,
explicitly waiting sessions second, declared priorities next, then other questions.
An elapsed deadline removes a question from attention regardless of its priority.
Completed includes locally elapsed question deadlines as well as server-reported
replied, resolved, and expired states. Local expiry never asserts that a default
was executed; that outcome still requires server confirmation.

Counts and lists derive from one snapshot. Live messages merge once into history;
resolved history wins over an older streamed copy. A cancellable deadline task
updates the projection without rebuilding the window every second. History reply
controls also stop accepting input when the question deadline passes.

## Layout and Interaction

The sidebar is 220–280 points wide, with a 244-point preferred width. Below a
760-point window width, the Overview toolbar button switches navigation and content.
The minimum window remains 480 × 400. Dashboard details use the full content area
below 900 points of content width; larger workspaces show a side inspector. Closing
a detail returns to the dashboard, and drafts remain keyed by question ID.

Decision rows have a restrained hover transition; detail opening respects Reduce
Motion. Native focus and selection remain visible. Replies keep the existing
persistent composer and Command-Return shortcut. Command-R refreshes the current
surface; returning to the app refreshes recent history and dashboard panels.

Disconnected, failed, loading, and empty states remain distinct. Cached questions
remain available during connection failures. Panel errors appear once with a retry
action; a failed fetch must not imply there are zero panels.

## Inline Session Reading

Session and history destinations use a single scrolling message stream with a
900-point maximum reading width. Sender, date, and time precede selectable body
text; message rows do not open modal details. Ordinary messages are fully visible.
Long messages (over 1,200 characters or 14 explicit lines) have a preview bounded
by 600 characters and eight explicit lines. Unicode grapheme boundaries are preserved.
Full text remains available with Show full message; Collapse message returns the
scroll position to that message. Expansion state is keyed by message ID.

Search matches body and supporting content and expands matching messages while
search is active. Clearing search restores the user's previous expansion state.
Choices and images stay inline. Write a reply reveals a message-scoped editor;
Command-Return is assigned only to its focused editor. Shared submission state
prevents duplicate sends, preserves failed drafts, and displays errors next to the
action. Resolved and expired messages keep read-only choices in a disclosure.
Notification entry points retain their existing targeted lookup behavior.

## Verification

Run `swift test --package-path macos` and `swift test --package-path HibossKit`.
Pure regression tests cover ordinary questions, streamed questions, manual deadlines,
priority expiry, count agreement, session isolation, deadline invalidation, and
inline reading (collapse thresholds, search expansion, reply closure at the deadline).
Native interaction, appearance, and narrow-window geometry need a macOS UI run; a
build and pure logic tests do not constitute visual verification.
