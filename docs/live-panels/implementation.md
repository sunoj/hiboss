# Lifecycle v2 implementation and rollout

Updated: 2026-09-08. The core protocol is implemented and tested. Migration 0035
and the v2 production Worker are deployed; the local macOS Dashboard and CLI
are installed. All seven retained production panels now use v2 definitions.
See [the rollout record](rollout-2026-09-08.md) for exact scope and verification.

See the [2026-09-11 native UI record](native-ui-2026-09-11.md) for questionnaire discovery,
form improvements, and current macOS/iOS build evidence.

## Implemented

- Running, paused, completed, failed, and cancelled task states, independent of
  boss placement and local subscription state.
- Server-issued producer epochs, 45-second leases, 15-second CLI renewal, explicit
  takeover, and rejection of expired or fenced writers.
- Per-panel queues shared by HTTP controls and every WebSocket connection.
- Schema-validated atomic JSON Pointer patches, including array insertion/removal,
  task namespace confinement, duplicate-update receipts, and sequence conflicts.
- Actual observations through `state.update` and `state.unchanged`. Heartbeats
  renew ownership without moving the observation or stale deadline.
- Configurable visibility windows from 60 seconds to 7 days, defaulting to 3600 seconds;
  publication stores `expiresAt`, and only an explicit owner renewal moves it. Streaming
  data alone does not keep a card alive; a lapse hides the card without changing task
  state, and renewal brings it back.
- Final state and metadata CAS, permanent terminal outcomes, idempotent command
  receipts, D1/DO prepare-commit recovery, recovery alarms, and a periodic repair
  sweep for lost or exhausted alarms.
- Definition replacement with a validated baseline and summary, a new revision, reset sequence,
  and producer fencing. A retry of an ended task uses a new panel and can declare
  `supersedesPanelId`.
  Replacement omits the old summary unless a new schema-valid summary is supplied.
- Boss-owned automatic/pinned/archived placement and separate seen/acknowledged
  terminal versions. Archive never stops the producer. Results remain available
  after a timed card leaves Active.
- Native Active/Needs input/Results/Archived filters, result presentation, placement actions,
  version reconciliation, and preservation of selection and stores during refresh.
- Paginated discovery polling every ten seconds, plus per-panel metadata hints.
  Newly discovered panels append without sorting by observation time.
- Server clock anchors and monotonic progression for native freshness/retirement.
  A terminal or paused task never degrades into an Offline task status.
- CLI commands `panel publish`, `panel stream`, `panel state`, `panel update`,
  `panel complete|fail|cancel|pause|resume|renew`, `panel doctor`, `panel lifecycle`,
  `panel definition`, and `panel guide`, plus `setup agents` for refreshable
  Codex/Claude instructions.

## HTTP and relay contract

| Endpoint | Caller | Purpose |
| --- | --- | --- |
| POST /api/panels | Agent | Publish protocol v2 with a stable Idempotency-Key |
| GET /api/panels | Agent / boss | Paginated metadata, lifecycle, preferences, final snapshot |
| GET /api/panels/:id | Agent / boss | Current immutable definition and metadata |
| GET /api/panels/:id/state | Agent / boss | Current checkpoint or durable final state |
| POST /api/panels/:id/producer-lease | Owner | Claim/renew with protocolVersion 2 |
| POST /api/panels/:id/lifecycle | Owner | Versioned pause/resume/complete/fail/cancel |
| PUT /api/panels/:id/definition | Owner | Versioned definition replacement |
| GET /api/panels/:id/operations/:operationId | Agent / boss | Committed receipt or pending status |
| PUT /api/panels/:id/preferences | Boss | Preference CAS and result receipts |

Connection tickets remain scoped to one recipient, panel, role, and identity.
Every subscription/update rechecks access. Send `protocolVersion: 2` on relay
commands. Producer tickets include `lease.release`; a clean producer EOF sends
`lease.release` with its epoch and receives an acknowledgement. A server without
that frame reports a protocol version mismatch rather than a delivery failure.
`lease.claim` takes a unique `requestId`, `definitionRevision`, and an
optional exact `takeoverEpoch`. Its acknowledgement includes the server epoch and
full baseline. `lease.renew` uses that epoch and revision.

Updates carry `updateId`, `epoch`, `definitionRevision`, and `baseSequence`.
`state.update` carries `ops`; `state.unchanged` carries no state modifications.
Update receipt retention is ten minutes, bounded to 256 entries per current epoch.
Control receipts are durable with the panel. A new epoch resets sequence to zero
and preserves the last observation until a genuine new observation arrives.

Checkpoints contain task, epoch, sequence, observationVersion, lastObservedAt,
staleAt, expiresAt, leaseExpiresAt, persistedAt, and serverTime. `serverTime` is response clock
context, not a change to the retained terminal task or its observation history.
The stale deadline is lastObservedAt plus max(15, 2 × expected cadence) seconds.
Publication cadence is an integer from 5 to 3600 seconds, defaulting to 15.
Publication `ttlSeconds` is an integer from 60 to 604800 seconds, defaulting to 3600.
`expiresAt` is stored at publication and changes only through the explicit owner renewal
operation. A lapsed running or paused card leaves Active but stays running or paused;
pins keep it visible. No expiry sweep writes task state or archives records.

A lifecycle command requires expectedMetadataVersion, expectedDefinitionRevision,
expectedEpoch, expectedState, and an open-request policy. Use `openRequests: "reject"`
by default; terminal commands may use `withdraw` with `withdrawalReason`. Terminal commands can
provide a schema-valid finalTask. Failure needs a result title and code;
cancellation needs a result title explaining the reason. D1 uncertainty returns
202 with an operation ID, never an uncommitted completed result.

Renewal is a separate owner operation at `POST /api/panels/:id/renew`. It uses
Idempotency-Key, expectedMetadataVersion, and expectedDefinitionRevision; it does not
need a live producer lease, returns the new `expiresAt`, and can replace `ttlSeconds`.

Success defaults to ten-minute retention; cancellation defaults to one minute;
failure defaults to manual acknowledgement. A producer can request `dismissal`
with `policy: default | immediate | after | manual` for a non-failure outcome;
`after` requires afterSeconds from 0 to 86400. Failure cannot be automatically
hidden by its producer. Pins override retirement and Results preserve outcomes.

## Agent discovery and report delivery

The global entry points are `~/.codex/AGENTS.md` and `~/.claude/CLAUDE.md`, with a
managed `hiboss:panels` block. `hiboss setup agents` updates that block without
replacing unrelated instructions and installs the full guide at
`~/.config/hiboss/panel-agent-guide.md`. It supports `--dry-run` and a target
`--home-dir` for controlled installation/testing.

The same [agent guide](../../cli/resources/panel-agent-guide.md) is embedded in
`hiboss panel guide`. It includes an executable test-report example, real recipient
and session discovery, final state verification, and exact retry semantics.
A report card references its artifact; publication does not upload or host a local
HTML report directory. Never claim a workspace path is a publicly accessible link.

## Verification

E2E execution host: the authorized remote Linux host, isolated checkout under
`/tmp/hiboss-panels-e2e.xFY4uy`. No production credentials or channels are required.
The server suite covers D1 failures before and after commit, engine reconstruction,
lost alarms, expiry, takeover, concurrent writers, schema failures, and durable
results. The real Rust CLI harness exercises four report/card definitions from
publication through final readback, including an idle 15-second lease renewal.

```bash
npm ci
npm test --workspace server -- --run
cargo build --manifest-path cli/Cargo.toml --examples --bins
cargo test --manifest-path cli/Cargo.toml
python3 cli/scripts/test-agent-guidance.py
python3 cli/scripts/run-panel-e2e.py
```

Run these E2E commands on the authorized remote host. The wrapper creates isolated
D1 state and test identities, chooses a local port on that host, and cleans up its
Worker process. Native builds can be checked locally. Remote Linux cannot run
SwiftUI or ActivityKit UI automation; do not report simulator compilation as a
physical-device Live Activity test.

## Durable questionnaires

The production Worker now includes versioned intake questionnaires, atomic typed answers,
explicit terminal withdrawal, CLI request commands, and native panel-detail entry
points. See [questionnaires](questionnaires.md) for migration order, exact scope,
retry semantics, and verification. Migration 0038 and the Worker were deployed on
2026-09-11; see the [rollout record](rollout-2026-09-11.md) for client distribution.

## Remaining product scope

Shared attention/inbox integration, boss-scoped discovery push, execution authorization
forms, and system Live Activity projection remain separate work. Existing standalone
form previews retain local drafts/captured answers. Only published questionnaires use
durable server submissions; no defaults or withdrawals produce synthetic approval.

The [Dynamic Island feasibility plan](dynamic-island.md) describes reusing the
existing iOS ActivityKit extension, bounded summary data, per-device dismissal,
and an APNs update/end path. Panels do not yet render on Dynamic Island.

## Coordinated rollout

The production Worker, database, local CLI, and macOS client were upgraded on
2026-09-08, and the agent channel followed on 2026-09-09 ([record](rollout-2026-09-09.md)):
Worker first, then the local and primary remote CLI, with one agent host left on its
older binary because it was offline. The iOS source builds but has not been installed on a device. Retained
panels were adopted through versioned definition replacement, preserving their
IDs and captured data. Producers must reconnect using the v2 CLI. This is a breaking
protocol change; do not install a v2 producer against the old production relay
and call the lifecycle feature shipped. Do not silently restore a v1 path.

The migration adds fields and tables without deleting panel data. Live v1 producer
leases/checkpoints use a different storage format; stop/restart those producers
with authoritative state as part of the rollout. Retained initial definitions
alone are not proof of the latest live observations.
