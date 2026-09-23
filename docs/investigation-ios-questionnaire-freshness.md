KB consulted: `questionnaire freshness invalidation` matched
`rust/quote-cache-freshness-signature-completeness.md`. Its relevant rule is to
capture a revision before asynchronous work and reject writes after invalidation.

# Questionnaire coverage freshness

Home previously inferred complete questionnaire coverage from a loaded wall and
an idle questionnaire fetch. Wall invalidation and disconnect did not revoke that
inference, and an older empty fetch could overwrite the pending set.

`PanelsModel.hasCompleteQuestionnaires` now requires a successful current fetch.
Metadata reloads, questionnaire reloads, wall changes, subscription loss, and
connection changes revoke it synchronously. A generation guards metadata and
questionnaire installation. The existing reconciliation task coalesces follow-up
work while a fetch is running; no new timer or synchronization abstraction is used.

A real wall subscription must acknowledge its subscription with `wall.changed`
before a subsequent successful fetch can complete coverage, with no metadata
reconciliation still queued. An injected API with
no wall subscription can complete coverage after its fetch. Home uses this state
and retains its checking status while coverage is incomplete. Known questionnaire
rows, panel stores, and drafts remain available during reconciliation.

## Validation

Focused model tests exercise held old-empty responses, repeated invalidation,
metadata reloads, connection changes, disconnect/reconnect, failed fetches, and
injected APIs without sockets. An iOS test checks Home's actual status against the
real model while message-input coverage remains healthy.

`swift test --package-path HibossKit --filter PanelsQuestionnaireCoverageTests`
completed with **10 tests, 0 failures**. The held-fetch case also observes published
coverage and verifies that no transient complete state appears before the current
follow-up finishes. Full output: `/private/tmp/hiboss-questionnaire-swift.log`.

The final iOS simulator run completed with **18 model/flow tests, 0 failures**
(`HomeAttentionFlowTests` and `RequiredInputCoverageTests`) and **5 Home UI tests,
0 failures** (`HomeAttentionUITests`), ending with `TEST SUCCEEDED`. It rebuilt the
checked-in Xcode project against this worktree's local HibossKit package. Full
output: `/private/tmp/hiboss-questionnaire-ios-final.log`. `git diff --check` passed;
every changed Swift file remains below 300 lines.

Live socket ticket acquisition and network reconnect behavior are outside these
controlled model tests; the existing authentication,
ticket, and reconnect transport flow is unchanged. The UI suite uses the injected
demo API; it does not simulate a physical network interruption.

## Changed files

- `HibossKit/Sources/HibossKit/PanelsModel.swift`: published coverage and generation.
- `HibossKit/Sources/HibossKit/Panels/PanelsModel+Loading.swift`: invalidate before
  loading and reject superseded metadata.
- `HibossKit/Sources/HibossKit/Panels/PanelsModel+Questionnaires.swift`: guard result
  installation and coverage; preserve the existing authentication-failure handling.
- `HibossKit/Sources/HibossKit/Panels/PanelsModel+Wall.swift`: connection lifecycle
  invalidation and coalesced reconciliation.
- `HibossKit/Sources/HibossKit/Panels/PanelsModel+Lifecycle.swift`: immediately
  invalidate coverage on tile subscription loss.
- `HibossKit/Sources/HibossKit/PanelRelayConnection.swift`: wall acknowledgement callback.
- `ios/App/Home/HomeView.swift`: consume coverage in the actual Home status gate.
- `ios/App/Shell/RootTabView.swift`: synchronously forward connection changes.
- `HibossKit/Tests/HibossKitTests/PanelsQuestionnaireCoverageTests.swift`: held-fetch
  and connectivity regressions against the actual model.
- `ios/Tests/HomeAttentionFlowTests.swift`: actual Home status regression.
- `docs/investigation-ios-questionnaire-freshness.md`: findings and test evidence.
