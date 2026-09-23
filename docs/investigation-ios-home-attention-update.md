KB consulted: `kb ios home attention swiftui` matched the SwiftUI silent-view-drop
lesson (`ai-coding/a-view-the-platform-drops-renders-no-error.md`). The review also
used the fixture-contract lesson,
`ai-coding/a-stub-that-agrees-with-the-code-proves-nothing.md`.

# iOS Home attention update

## Observed gaps

The bounded, mixed-direction message history could omit an older unresolved
request. The existing options stream did not deliver blocking text asks. The
priority subset could hide a normal-priority option while Home reported that
nothing needed a reply. A NULL-expiry option could appear but its reply returned
409. Pending blocking questionnaires were also absent from Home's count.

## Implemented contract

- `GET /api/boss/pending-inputs` returns scoped, unresolved option and blocking
  text requests through a complete keyset page sequence. The normal Inbox history
  remains bounded. Missing pages, malformed cursors, and request failures cannot
  authorize Home's all-clear state.
- `GET /api/boss/stream?inputs=true` discovers both kinds of required input and
  reports their resolution. The client applies events immediately, reconciles the
  complete set, and requires a new ready event and successful fetch after a
  disconnect. The existing `options=true` stream remains available.
- Home counts every unresolved option decision regardless of declared priority
  or session status. Priority still orders the rows. Blocking text asks and
  blocking questionnaires also count. Forms are deduplicated by request ID,
  use the panel clock for expiry, and open their owning panel.
- A reply stays counted until the server accepts it. A failed or already-resolved
  reply does not create a temporary all-clear. The server accepts active options
  without an expiry while retaining the one-winner status claim and choice checks.
- Short option pairs remain directly actionable. Long lists stack at accessibility
  sizes. Text asks open the existing reply detail. Empty and incomplete states
  have distinct presentations.
- Demo deadlines remain near enough to show a useful countdown during UI tests.
  The demo choice fixture describes its options in text because its old example
  image URLs did not load. Production option media support remains intact.

## Verification

- iOS simulator build with Xcode 27: passed.
- `HomeAttentionModelTests`, `HomeAttentionFlowTests`, and
  `RequiredInputCoverageTests`: 24 passed.
- `HomeAttentionUITests`: 5 passed on an iPhone 18 Pro simulator, including text
  reply, inline choice, empty state, and accessibility-size option reachability.
- `RequiredInputClientTests`: 4 passed.
- Server TypeScript check and the focused pending-input, access, and options
  stream suites: 14 passed.
- Current simulator captures: `ios/Screenshots/home-attention-populated.png` and
  `ios/Screenshots/home-attention-empty.png`.

The updated iOS Home requires the pending-input endpoint and input stream from
this server revision. An older server cannot provide a complete attention state.
