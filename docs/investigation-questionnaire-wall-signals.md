KB consulted: `questionnaire mutation wall invalidation` matched
`rust/quote-cache-freshness-signature-completeness.md`: freshness coverage must
include every source that can change the discovered state.

# Questionnaire mutation invalidation

Questionnaire publication, replacement, withdrawal, and acceptance previously
committed D1 changes without notifying wall subscribers. An old empty discovery
response could therefore complete Home coverage after a blocking publication.

The four HTTP mutation handlers now await one shared `notifyRequestWall` helper
after their mutation succeeds and before returning success. The helper reads the
authoritative panel record for its target boss, owning producer, and lifecycle
expiry, then calls the existing identity-scoped, content-free `notifyWall` path.
It does not use questionnaire expiry as panel expiry or change ticket/auth behavior.
Rejected mutations do not reach the helper. Publication, withdrawal, and accepted
submission retries with matching receipts signal again; replacement remains a
revision compare-and-swap and a stale retry returns a conflict without signaling.

As with existing panel publication, notification failures after commit are caught:
the durable mutation remains committed and the HTTP response remains successful.
There is no durable signal queue or guaranteed delivery during a relay outage.
Later client reconciliation, reconnection, or a safe mutation retry recovers the
missed invalidation. An unavailable relay binding also follows `notifyWall`'s
existing no-op behavior. Thus prompt invalidation depends on successful signaling;
this change does not promise all-clear freshness through a lost signal.

## Validation design

The Worker/D1/relay regression uses authenticated real wall sockets for the boss,
owning producer, and another authorized producer. A test-only interception of the
internal relay fetch holds notification after the D1 commit: HTTP discovery must
already expose the blocking request while mutation HTTP success is still pending.
The interception forwards to the real relay and records completion before HTTP
success. Further cases cover blocking/expiry revisions, accepted submissions,
withdrawal, safe retries, rejected mutations, and a failed post-commit signal.

The controlled Swift regression starts with no pending questionnaire, holds an
empty response, installs a new blocking request in the controlled API, and receives
`wallChanged`. It asserts coverage stays incomplete while current reconciliation
is held and observes zero empty complete snapshots, including when the current
row is installed. Other existing tests retain known-row preservation coverage.

These tests compose at the wall invalidation contract; they do not run a native
client against a live Worker or test physical network transport to Home.

## Executed checks

Local macOS command:
`swift test --package-path HibossKit --scratch-path /private/tmp/hiboss-questionnaire-signals-swift --filter PanelsQuestionnaireCoverageTests`

Final output: `Executed 10 tests, with 0 failures (0 unexpected) in 0.735 (0.738) seconds`.
Log: `/private/tmp/hiboss-questionnaire-signals-swift.log`. The initial sandboxed
attempt could not write the compiler cache; the successful run had cache access.

Remote `npm run typecheck --workspace server` passed (`tsc --noEmit`, no errors).
The initial test launch found no ignored `server/wrangler.toml`; the remote-only
fixture now uses the tracked `wrangler.toml.example`, without private config.

After `rbox ensure` and a shared-load check, the final locked run on
a remote build host executed:
`npm exec --workspace server -- vitest run src/panels/requests src/panels/relay/wall.e2e.test.ts src/panels/lifecycle`.
Exact summary: `Test Files 9 passed (9)`; `Tests 46 passed (46)`;
`Duration 21.75s`; `rbox: job d32d58dedd8e49cbbb57afe18d3bfc1d exited with code 0`.
The new questionnaire wall suite accounts for five passing tests.
Full output: `/private/tmp/hiboss-questionnaire-signals-server.log`.

The first executable server run had 45 passes and one test-harness failure:
sharing a held promise across Durable Object contexts violated workerd I/O
ownership. The final gate waits inside its Durable Object context. A subsequent
clean sync removed dependencies; reinstalling them preceded the final passing
typecheck and test run. No production correction was needed for these harness issues.
The additional KB query for Durable Object test I/O matched the eviction-testing
limitation article, not a direct explanation of this promise-context failure.

`git diff --check` passed. All changed source files are below 300 lines; the
longest is the existing Swift test file at 287 lines. No server checks ran locally.
No new iOS UI run, live network/native integration, independent release audit,
commit, push, merge, or deployment was performed.

## Changed files

- `server/src/panels/requests/index.ts`: await notification after successful mutations.
- `server/src/panels/requests/signals.ts`: read the panel and signal with publication recovery semantics.
- `server/src/panels/requests/tests/wall-support.ts`: real socket and controlled relay boundary helpers.
- `server/src/panels/requests/tests/wall.e2e.test.ts`: mutation/discovery/relay regression coverage.
- `HibossKit/Tests/HibossKitTests/PanelsQuestionnaireCoverageTests.swift`: publish during a held empty fetch.
- `docs/investigation-questionnaire-wall-signals.md`: findings, evidence, and limits.
