KB consulted: `kb 'hiboss iOS Today startup connection error'`. Related records
cover blocked reads, reconnect storms, and freshness versus liveness; no exact
recipe matched the required-input transport.

# Today readiness and startup loading

## Required-input readiness

Today requires both a complete HTTP pending-input snapshot and the dedicated
SSE stream's `ready` event. HTTP history success alone cannot authorize all-clear.
The server emits `ready` after its first complete scan in
`server/src/routes/boss-required-input-stream.ts`. Frames end with a blank line.

Foundation's async byte `lines` sequence omits these empty lines. The required-input
decoder therefore never receives a frame delimiter while the response remains
open. The eight-second coverage watchdog then reports that the requests connection
is not ready even though other HTTP sources have loaded.

The required-input transport now consumes bytes and preserves empty LF/CRLF lines.
UTF-8 decoding occurs after complete lines, including when chunks split an emoji.
The existing event decoder still rejects malformed or incomplete recognized frames;
its readiness and pagination contracts are unchanged.

`RequiredInputStreamTests.testReadyArrivesBeforeTheStreamCloses` uses a real
Foundation async byte response supplied by URLProtocol, with no response EOF.
The original transport failed the two-second readiness assertion. The corrected
transport passed it. A second test verifies fragmented Unicode request updates,
keepalive comments, and resolved events arrive in order without duplicate delivery.
The four original required-input client tests remain unchanged and pass.

## First appearance and refresh ownership

`InboxStore.start` owns the initial message snapshot and required-input discovery.
Today no longer starts a second full history refresh when its view first appears.
Foreground history reconciliation remains owned by the root tab shell. The panel
model is created without autoload; Today's existing task owns its initial load.
Manual pull-to-refresh fetches messages and panels concurrently.

`InboxStoreTests.testTodayFirstAppearanceDoesNotRepeatCompletedStartupHistory`
hosts the real Today view after initial inbox loading. It failed on the original
view with two history reads and passed on the corrected view with one read and the
same displayed history. The focused inbox, input coverage, input liveness, and Home
coverage suites passed 27 tests.

## Verification boundaries

These tests confirm a native SSE framing failure and duplicate startup history
loading. They do not establish the cause of an individual panel's offline status
or an unacknowledged questionnaire wall connection. Loaded panel values, source
errors, retry actions, and conservative all-clear coverage remain visible.

## Live input reconciliation

The iOS store previously canceled and restarted its complete input fetch for every
stream event, including duplicate readiness. A slow snapshot could therefore be
starved by live events. Readiness now initiates a fetch only when none is active;
message and resolution events update the list immediately and are merged over a
snapshot that began earlier. Disconnects and epoch changes still invalidate old
results. Failed snapshots retry with bounded backoff while the stream stays ready.

Three controlled-service regressions failed before this change and passed after it.
They cover live updates during a held fetch, duplicate readiness, and updates after
coverage has completed. Additional tests cover retry recovery and stop cancellation.
The original late-result, reconnect, and silent-stream coverage checks are retained.

## Panel coverage versus producer freshness

A connected panel projection can report an offline or stale producer. Its snapshot
has still been read; retrying the client cannot restore the producer's lease.
Today previously treated either freshness label as unfinished panel coverage and
could remain checking forever even after requests and questionnaires were known.

`PanelsModel.hasPanelCoverage(for:)` now requires a received checkpoint on a live
relay for running server panels. Producer freshness remains visible on each tile.
Unread projections and lost relays still prevent all-clear; questionnaire coverage
is checked independently. A Home regression failed with both expired leases and
stale observations before the change, then passed while retaining these guards.
Relay diagnostics record acknowledgement, phase, error domain/code, and HTTP status
without recording tickets, credentials, payloads, or request URLs.

## Compact all-clear presentation

Both native apps use the same 120-by-72-point transparent vector illustration.
Semantic text and state colours adapt its line art to light and dark appearance.
The illustration sits beside status copy and has no animation timer. The iOS
all-clear row no longer reserves 360 points of height. UI checks retain light and
dark screenshots and require the ordinary-size row to stay within 120 points.

## Retained content during refresh

A refresh of verified Today content previously replaced the idle row with an incomplete
coverage layout. The screen now retains the known decision and questionnaire projection
while displaying `Refreshing…` in its existing status positions. This presentation is used
only after complete coverage has been observed, while both connections remain healthy and
panel projections remain available. It does not alter reply admission or authoritative
coverage. Initial loading, lost connections, unread projections, and request failures still
show the coverage and recovery interface.

The pull gesture returns to its resting position while the asynchronous refresh continues.
The compact illustration moves only the palm, around its base, during this refresh. The
render schedule is absent while idle and when Reduce Motion is enabled.

A native UI regression checks that a held refresh preserves the idle row's height, shows
its small refresh label, and does not mount the large incomplete-coverage view.
