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
