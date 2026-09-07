# Live Panel Protocol Proposal

Status: proposed, unimplemented. Date: 2026-09-07.
Parent: [Live Panels design](../live-panels-design.md).
This document owns wire semantics; transport mechanics are in [runtime](runtime.md).

## 1. Protocol principles

- Use a versioned HiBoss envelope around an upstream json-render spec.
- Keep UI definition, producer data, local input, and authoritative decisions separate.
- Publish immutable definitions; use explicit revisions and compare-and-set writes.
- Treat every network input as unknown until schema and authorization validation pass.
- Return typed errors. Unsupported versions fail explicitly; do not silently interpret
  them as an older format or strip unfamiliar fields that could change meaning.
- Use opaque string IDs, integer revisions, and ISO-8601 UTC server timestamps.
  IDs become branded types in TypeScript and dedicated wrappers in Swift/Rust.
- UI visibility is presentation logic, never permission enforcement.

## 2. Catalog and capability contract

`catalogId` and `catalogVersion` identify an immutable set of component definitions,
prop schemas, action schemas, supported expressions, and validation rules. A
manifest also declares the HiBoss protocol version and renderer feature profile.

The initial catalog is `hiboss.panel`, version `1`. This is a proposed product
version, not a json-render package version. Pin an upstream package version and
commit during Phase 0; never load `latest` from a CDN at runtime.

| Component family | Initial components | Planned extension |
| --- | --- | --- |
| Layout | Stack, Grid, Section | Tabs and bounded step navigation |
| Display | Text, Metric, Progress, Status, Table | Timeline and richer report sections |
| Charts | LineChart, BarChart | Catalog-owned VegaChart or graph component |
| Input | TextInput, TextArea, NumberInput, Select, MultiSelect, Toggle, Slider | DateTime, ranked choice, item review |
| Actions | Button | Always bound to a registered action |

Every custom name and prop above needs a HiBoss implementation; they are not a
claim that json-render ships this exact catalog. The catalog defines field labels,
units, missing-value display, bounds, stable selection IDs, and accessibility text.
Chart values use finite numbers; gaps are explicit nulls, never silently zeros.

Supported initial expressions are `$state`, `$bindState`, `$item`, `$index`,
`$bindItem`, and bounded visibility conditions. Repetition requires stable item IDs.
Custom computed functions, watchers, and directives are disabled until explicitly
registered in a later catalog. No function bodies or expression evaluation via `eval`.

Discover capabilities before publication. An agent targeting an unsupported feature
receives an actionable error. A device unable to render an accepted catalog shows
the native summary and an update-required state; it cannot submit a partial form.
This is capability negotiation, not a compatibility shim.

The catalog/spec/registry separation follows upstream's
[catalog](https://json-render.dev/docs/catalog) and
[registry](https://json-render.dev/docs/registry) contracts.

## 3. Panel publication

Proposed request to `POST /api/panels`:

```json
{
  "protocolVersion": 1,
  "targetBossId": "boss_123",
  "taskKey": "benchmark-suite-2026-09",
  "sessionId": "session_123",
  "title": "Benchmark run",
  "catalogId": "hiboss.panel",
  "catalogVersion": 1,
  "spec": {
    "root": "main",
    "elements": {
      "main": {
        "type": "Stack",
        "props": { "direction": "vertical" },
        "children": ["completed"]
      },
      "completed": {
        "type": "Metric",
        "props": {
          "label": "Completed tests",
          "value": { "$state": "/task/completed" }
        },
        "children": []
      }
    }
  },
  "stateSchema": {
    "type": "object",
    "properties": { "completed": { "type": "integer", "minimum": 0 } },
    "required": ["completed"],
    "additionalProperties": false
  },
  "initialState": { "completed": 0 },
  "summary": { "stage": "Preparing", "metricPath": "/task/completed" }
}
```

Creation requires an `Idempotency-Key` header. The server derives `agentId` from
credentials, checks the target boss relationship and session ownership, and assigns
`panelId`, `definitionRevision: 1`, `metadataVersion: 1`, and server timestamps.
`taskKey` is scoped to `(targetBossId, agentId)`; it supports discovery across sessions,
not authorization. Project labels are presentation data and never tenant identifiers.

The accepted response includes `{ panelId, definitionRevision, metadataVersion,
catalogVersion, createdAt }`. It acknowledges a durable definition, not a connected
subscriber, rendered frame, or agent execution outcome.

Validate the entire tree: root exists, child IDs resolve, no cycles, no duplicate JSON
keys, no unknown component/prop/action, bounded depth and node count, and valid bindings.
Reject dangerous object-property paths after JSON Pointer decoding, including
`__proto__`, `prototype`, and `constructor`. Use safe maps rather than prototype writes.

Definition replacement supplies `expectedDefinitionRevision`, the full new spec,
state schema, summary, and initial state. It atomically creates the next revision.
It does not mutate an active interaction's frozen form or the user's draft.

UI generation streams may be assembled in an agent/local preview. Initial publication
accepts only complete validated specs. Never expose a half-generated authorization
form with an active Submit button. Upstream SpecStream can later support staging;
it is not itself our durable publication protocol.
[SpecStream](https://json-render.dev/docs/streaming)

## 4. State ownership and schema

| Runtime namespace | Writer | Persistence | Meaning |
| --- | --- | --- | --- |
| `/task` | Authorized panel producer | Latest accepted snapshot in DO storage | Live task data |
| `/context` | Host, from immutable request record | D1 request revision | Evidence and choices being decided |
| `/form` | User input through approved bindings | Device-local draft | Unsubmitted answers |
| `/ui` | Local renderer interactions | Optional device-local view state | Tabs, filters, expansion |
| `/host` | Native host/server projection | Derived from authoritative records | Identity, freshness, request status |

`stateSchema` validates the object mounted at `/task`. Form answer schemas validate
the submitted object, without a `/form` wrapper. An agent cannot publish writes to
`/form`, `/context`, `/ui`, or `/host`; the renderer cannot write producer/host namespaces.

Adopt a documented bounded subset of JSON Schema 2020-12: scalar types, object
properties/required/additionalProperties, arrays/items/length/uniqueItems, enum,
numeric and string bounds, and non-recursive local `$defs`/`$ref`. Add conditional
`if`/`then`/`else` and bounded `allOf` for dependent fields. Remote references, arbitrary
regex, and custom executable validators are excluded from the first catalog.
Phase 0 must prove server/client parity with shared fixtures before freezing the subset.

Answer-field bindings must resolve to the declared schema. Conditional activation
comes from the same declarative rules used by server validation, not solely an
element's visual `visible` field. Inactive answer paths are omitted; unexpected paths
are rejected. Keep stable IDs for arrays of review items and explicit nullable fields.

## 5. Live frames and ordering

Use one ordered state stream per panel, with one producer lease at a time. A lease
has a server-generated `epoch`. Takeover or definition replacement fences the previous
epoch and requires a complete state baseline before patches resume.

A producer sends an idempotent update command:

```json
{
  "protocolVersion": 1,
  "kind": "state.update",
  "panelId": "panel_123",
  "definitionRevision": 1,
  "epoch": "epoch_456",
  "updateId": "update_789",
  "baseSequence": 17,
  "ops": [{ "op": "replace", "path": "/task/completed", "value": 18 }]
}
```

The DO checks ownership, lease, revision, size, and `baseSequence`; applies the whole
patch to a private candidate; validates the resulting state; then commits the snapshot,
new sequence, and update receipt together. Only after persistence may it acknowledge
`acceptedSequence: 18` and broadcast `state.patch` with `sequence: 18`.

Accepted updates are durable latest-state updates, not a permanent event log.
One producer command may batch many time-series samples. Initial allowed JSON Patch
operations are `add`, `remove`, and `replace`, confined to `/task`. Reject the entire
command on any invalid operation; never partially commit a patch.

Receipts are retained for 10 minutes per active epoch, with bounded count/rate limits.
An identical `updateId` and body returns the original receipt. A different body under
that ID is a conflict. After an ambiguous retry beyond the retention window, reconcile
the snapshot and acquire a new epoch; do not replay stale array appends as new commands.

Client apply rules:

1. Match panel, definition revision, and epoch before applying any frame.
2. Ignore an already-applied sequence. Apply a patch only when its base is current.
3. On a gap, enter resync and request a snapshot; never guess missing operations.
4. Atomically install `{ definitionRevision, epoch, sequence, task, persistedAt }`.
5. Resume patches strictly after that snapshot. Replace only `/task`, preserving drafts.

Subscribe and snapshot capture are serialized in the DO. It sends a snapshot followed
by subsequent patches on the same socket; there is no fetch-then-subscribe race. During
resync it drops that subscriber's unsent deltas and installs a new snapshot boundary.
Initial v1 always recovers from the latest snapshot, not historical patch replay.

Other frame kinds: `hello`, `subscribe`, `unsubscribe`, `state.snapshot`, `state.patch`,
`state.ack`, `panel.changed`, `request.changed`, `subscription.revoked`, `resync`,
`ping`, `pong`, and `error`. Control notifications identify durable records and versions;
they are hints to refetch, never proof that a submission or task operation succeeded.

## 6. Interaction publication and revision

An interaction includes `panelId`, `kind` (`intake`, `decision`, `authorization`,
or `review`), `title`, `blocking`, `priority`, optional `expiresAt`, catalog identity,
`formSpec`, `answerSchema`, `defaults`, and immutable `context`.
Authorization requests additionally require a typed `operation` summary with target,
scope, and relevant limits. The host renders this review independently of form layout.

The server assigns a stable `requestId` and `requestRevision: 1`. Defaults are only
initial draft values; they are never a submitted answer. Blocking requests enter the
shared attention projection. No automatic default selection exists for v1 forms.

Example publication body using proposed HiBoss catalog components:

```json
{
  "kind": "decision",
  "title": "Choose the test rollout",
  "blocking": true,
  "priority": "normal",
  "catalogId": "hiboss.panel",
  "catalogVersion": 1,
  "context": { "candidate": "build-42", "purpose": "Staging evaluation" },
  "defaults": { "strategy": "canary", "trafficPercent": 10 },
  "answerSchema": {
    "type": "object",
    "properties": {
      "strategy": { "type": "string", "enum": ["canary", "full"] },
      "trafficPercent": { "type": "integer", "minimum": 1, "maximum": 100 }
    },
    "required": ["strategy", "trafficPercent"],
    "additionalProperties": false,
    "allOf": [{
      "if": { "properties": { "strategy": { "enum": ["full"] } } },
      "then": { "properties": { "trafficPercent": { "enum": [100] } } }
    }]
  },
  "formSpec": {
    "root": "form",
    "elements": {
      "form": {
        "type": "Stack",
        "props": { "direction": "vertical" },
        "children": ["strategy", "traffic", "submit"]
      },
      "strategy": {
        "type": "Select",
        "props": {
          "label": "Strategy",
          "value": { "$bindState": "/form/strategy" },
          "options": [
            { "id": "canary", "label": "Canary" },
            { "id": "full", "label": "Full rollout" }
          ]
        },
        "children": []
      },
      "traffic": {
        "type": "NumberInput",
        "props": {
          "label": "Traffic percentage",
          "value": { "$bindState": "/form/trafficPercent" },
          "min": 1,
          "max": 100
        },
        "children": []
      },
      "submit": {
        "type": "Button",
        "props": { "label": "Submit selection" },
        "on": { "press": { "action": "submitRequest" } },
        "children": []
      }
    }
  }
}
```

`submitRequest` is a HiBoss host action. It validates against the pinned answer schema
before sending and cannot target an arbitrary request. `openPanel` is local navigation;
`nextStep`/`previousStep` and `requestPreview` are later catalog additions. Their names
must not be confused with upstream example action implementations.
The example collects a decision; it does not itself authorize executing a deployment.
The answer schema also constrains full rollout to 100 percent.

Any change to labels, choices, validation, defaults, operation, or decision context
creates a new revision. A compare-and-set transition supersedes the prior open revision.
Editing and submitting compete for the same authoritative request head in D1.

An open client pins the revision it began editing. On supersession it keeps the old
draft locally, disables submission, and offers an explicit restart on the new revision.
Do not silently transfer answers or reinterpret IDs across changed questions. An
accepted request cannot be revised; publish a new linked request for a correction.

Decision-sensitive values come from `/context`, not mutable `/task` bindings. Live
charts may appear beside a request, but their freshness does not alter the operation
being approved. If new task evidence changes that operation, supersede the request.

## 7. Submission and execution semantics

Proposed logical payload, signed by key-bound clients:

```json
{
  "protocolVersion": 1,
  "purpose": "hiboss.interaction-submit",
  "submissionId": "submission_123",
  "requestId": "request_123",
  "requestRevision": 3,
  "bossId": "boss_123",
  "issuedAt": 1788750000,
  "answers": {
    "environment": "staging",
    "strategy": "canary",
    "trafficPercent": 10,
    "runSmokeTests": true
  }
}
```

The native host assembles this payload from the active request and declared answer
paths. It signs the exact JWS payload bytes. The renderer cannot choose boss identity,
purpose, target request, provenance, or an arbitrary destination URL. A retry preserves
`submissionId` and answers; it may refresh the signature timestamp after revalidation.

Use the existing token-to-key association and ES256 verification infrastructure with
a **new purpose-specific payload**, not the existing string-message signing type.
Key-bound credentials never downgrade to unsigned. Bearer-only callers retain explicit
`not_configured` provenance; sensitive authorization requests may require a paired key.
Viewers may inspect authorized requests but cannot submit v1 structured answers.
Signing proves origin/integrity, not that the requested operation is safe.
[Current signing boundary](../message-signing.md)

Server acceptance sequence:

1. Authenticate; check current role, target visibility, key binding, and signature.
2. Look up `submissionId` within the authenticated boss scope. If already accepted
   with the same semantic payload, return its receipt even if the request is now terminal.
   A changed request/revision/answer under that ID returns `idempotency_conflict`.
3. Check the request head is open, matches the revision, and has not expired at server time.
4. Validate the complete answers, active-field rules, item IDs, and operation constraints.
5. Atomically claim the request, insert the immutable submission/provenance, append the
   session projection event, and insert a durable agent-delivery outbox entry in D1.
6. Return `{ submissionId, requestId, requestRevision, acceptedAt, delivery: "pending" }`.

The D1 operation must be one conditional atomic transaction/batch with constraints;
a claim followed by unrelated writes is insufficient. The implementation proof must
show competing clients, revision changes, expiry, and crashes cannot create a claim
without its answer/outbox. Define the exact SQL in the later storage work package.

Only one submission wins for a request. A losing device receives `request_resolved`
and loads the accepted answer if authorized. Server acceptance ends editing on all
devices; notification delivery may lag without changing that fact.

The outbox delivers at least once to the owning agent/task. An agent deduplicates by
`submissionId` and acknowledges receipt separately. Network delivery cannot guarantee
exactly-once external side effects; execution integrations must use their own idempotency
or reconcile results. `accepted`, `delivered`, and `executed` are distinct UI states.

When offline, preserve the draft and an ambiguous in-flight submission ID. On reconnect,
query that ID first. If absent, refresh the request and require an explicit retry;
never automatically submit old authorization after an unknown interval offline.

## 8. Proposed API surface

All paths below are new. All reads and mutations enforce the same visibility scope.
Unauthorized object lookups return a non-disclosing 404. Reads expose stable typed data.

| Method and path | Caller | Contract |
| --- | --- | --- |
| `GET /api/panel-catalogs/:id/:version` | Agent/boss | Catalog, schema profile, limits, supported actions |
| `POST /api/panels` | Agent | Idempotent publication |
| `GET /api/panels?cursor=...` | Agent/boss | Scoped metadata/summaries, opaque pagination; no per-panel snapshot fan-out |
| `GET /api/panels/:id` | Agent/boss | Metadata, current immutable definition, request summaries |
| `GET /api/panels/:id/definitions/:revision` | Agent/boss | Exact retained definition for a named snapshot |
| `PUT /api/panels/:id/definition` | Owning agent | New revision with expected revision |
| `POST /api/panels/:id/producer-lease` | Owning agent | Claim/renew/fence producer epoch |
| `GET /api/panels/:id/state` | Agent/boss | Latest durable snapshot; response names definition revision |
| `POST /api/panels/:id/lifecycle` | Owning agent | Pause/resume/complete/fail/cancel with metadata CAS |
| `PUT /api/panels/:id/preferences` | Boss | Pin/order/archive preferences, independent of task state |
| `POST /api/panel-connections` | Agent/boss | Scoped, short-lived connection ticket |
| `GET /api/panel-relay` | Ticket holder | WebSocket upgrade; no bearer credentials in URL |
| `POST /api/panels/:id/requests` | Owning agent | Publish immutable form revision |
| `GET /api/interaction-requests/:id?revision=...` | Agent/boss | Current head, or exact authorized revision when specified |
| `PUT /api/interaction-requests/:id` | Owning agent | CAS supersession of an open revision |
| `POST /api/interaction-requests/:id/withdraw` | Owning agent | Terminal withdrawal, no synthetic answer |
| `POST /api/interaction-requests/:id/submissions` | Boss | Durable, validated, idempotent answer |
| `GET /api/interaction-submissions/:id` | Owner/authorized boss | Resolve ambiguous submission and inspect receipt |
| `GET /api/panel-deliveries?after=...` | Owning agent | Durable submission delivery cursor |
| `POST /api/panel-deliveries/:id/ack` | Owning agent | Idempotent receipt acknowledgement |

All creation/control writes carry an idempotency key; updates also carry expected
versions. Reusing a key with a different logical body returns 409. Apply a 24-hour
receipt window for non-submission control writes and return the resulting object ID.
Submission receipts remain for the lifetime of their retained decision record.

Error envelope: `{ error: { code, message, retryable, fieldErrors?, currentRevision? } }`.
Codes include `invalid_spec`, `invalid_state`, `invalid_answers`, `unsupported_catalog`,
`revision_conflict`, `request_resolved`, `request_expired`, `lease_conflict`,
`resync_required`, `idempotency_conflict`, `rate_limited`, and `service_unavailable`.
Use 400/422 for invalid inputs, 409 for conflicts, 410 for expiry, 413 for size,
429 plus retry timing for rate limits, and 503 for unavailable durability.
Successful publication/submission must never be synthesized from a transport timeout.

## 9. Agent-facing workflow

Proposed CLI verbs: `hiboss panel catalog`, `validate`, `publish`, `show`, `list`,
`stream`, `update-definition`, and `finish`; `hiboss request publish`, `show`,
`replace`, `withdraw`, and `wait`. `stream` consumes structured NDJSON from stdin;
the local runtime maintains the lease, batches samples, and reports acknowledgements.

Equivalent MCP tools: `panel_catalog`, `panel_validate`, `panel_publish`,
`panel_update`, `panel_finish`, `request_publish`, `request_replace`, and
`request_wait`. A wait timeout means still pending, not an answer or request expiration.
Long-lived acquisition/streaming belongs to the CLI/daemon, not repeated model calls.

Validation errors include JSON Pointer paths and allowed values so an agent can repair
its declaration. Publish returns IDs and versions in machine-readable output. A task
can resume from those IDs without republishing a duplicate panel or questionnaire.

## 10. Existing attention, history, and agent delivery

Use `request:<requestId>` as the stable attention key. Request revisions replace the
same item's content; they never increase the count. A panel preview links the request
but is not another attention item. Extend the shared attention projection to combine
existing simple choices with open structured requests under the established ranking.
An expired form is history, never an auto-decided item. Rendering a form does not
create a second legacy option message or a synthetic answer string.

Append `panel.created`, `panel.completed`, `interaction.opened`,
`interaction.superseded`, and `interaction.resolved` session events for meaningful
lifecycle changes. Events reference IDs/revisions and safe summaries; charts do not
append an event for every sample. A panel may outlive its session; use its current
authorized session association for new events and retain earlier associations in history.

Formal answer deliveries contain the accepted structured payload, provenance, and
stable submission ID. The MCP/CLI adapter verifies new signed payloads before presenting
them to the agent. Its durable delivery cursor is independent of session SSE cursors.
`request_wait` reads the same accepted record and uses the same identity, so polling
and asynchronous delivery cannot justify executing the answer twice.

## 11. Acceptance invariants

- A draft never changes because producer data or another device's draft changed.
- A submission always names the exact immutable question/context it answers.
- An accepted answer has a durable receipt and recoverable delivery record.
- An acknowledged state update survives a DO restart as part of the latest snapshot.
- A revision change, missing patch, invalid schema, or authorization failure never
  produces a silently partial but apparently valid form.
- The same request appears once in attention and resolves consistently across devices.
