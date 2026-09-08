# HiBoss dynamic notification delivery

Dynamic notifications, live cards, and Panels refer to `hiboss panel`.
Use Panels for task progress, test results, downloads, benchmark comparisons,
and ongoing monitoring. Use `hiboss ask` only when a human decision is actually
required. A completed report does not require a blocking question.

## Discover the installed interface

Run `hiboss panel --help` once. This guide describes protocol v2. The required
commands are `validate`, `publish`, `stream`, `state`, `lifecycle`, and `show`.
If the installed CLI lacks one, report the version mismatch. Do not invent flags,
search unrelated repositories, or repeatedly scan the user's configuration.
Never display API keys or notification credentials.

The lifecycle implementation must be deployed with the matching server. An
`unsupported_protocol` response means the server needs the v2 rollout. Do not
silently fall back to an older protocol or claim the card was delivered.

## Choose the recipient and execution session

Use the current authenticated agent and its actual session. Discover an existing
boss and session with `hiboss boss --help` and `hiboss ss --help`, then their list
commands. Do not create unrelated identities, guess a boss ID, or use a session
owned by another agent. If more than one recipient is plausible, ask which one.

## Publish a report card

Create `report-panel.json` with a stable task key and the actual boss/session IDs:

```json
{
  "protocolVersion": 2,
  "targetBossId": "BOSS_ID",
  "sessionId": "SESSION_ID",
  "taskKey": "remote-e2e-report",
  "title": "Remote E2E report",
  "catalogId": "hiboss.panel",
  "catalogVersion": 1,
  "lifecycle": { "mode": "run", "expectedUpdateIntervalSeconds": 15 },
  "spec": {
    "root": "report",
    "elements": {
      "report": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["counts", "fixes", "scope", "artifact"] },
      "counts": { "type": "Grid", "props": { "columns": 3 }, "children": ["passed", "skipped", "failed"] },
      "passed": { "type": "Metric", "props": { "label": "Passed", "value": { "$state": "/task/passed" } }, "children": [] },
      "skipped": { "type": "Metric", "props": { "label": "Skipped", "value": { "$state": "/task/skipped" } }, "children": [] },
      "failed": { "type": "Metric", "props": { "label": "Failed", "value": { "$state": "/task/failed" } }, "children": [] },
      "fixes": { "type": "Text", "props": { "text": "Fixed modal focus cycling, initial avatar crop, and market connection state. Type check and build passed." }, "children": [] },
      "scope": { "type": "Text", "props": { "text": "Remote UI E2E. On-chain settlement was not tested." }, "children": [] },
      "artifact": { "type": "Text", "props": { "text": "Report: output/playwright/remote-final/report/index.html (workspace-relative artifact)" }, "children": [] }
    }
  },
  "stateSchema": {
    "type": "object", "required": ["task"], "additionalProperties": false,
    "properties": {
      "task": {
        "type": "object", "required": ["passed", "skipped", "failed"], "additionalProperties": false,
        "properties": {
          "passed": { "type": "integer", "minimum": 0 },
          "skipped": { "type": "integer", "minimum": 0 },
          "failed": { "type": "integer", "minimum": 0 }
        }
      }
    }
  },
  "initialState": { "task": { "passed": 13, "skipped": 1, "failed": 0 } }
}
```

Use real report evidence. A workspace-relative HTML path is not a public link.
Include its host/workspace location, or an already authorized accessible artifact
URL. Do not invent a hosted URL or claim the report file was uploaded merely
because the card was published. Put key fixes and material untested scope in the
card so the result remains useful without opening the artifact.

```bash
hiboss panel validate report-panel.json
hiboss panel publish report-panel.json --idempotency-key remote-e2e-RUN_ID
```

Keep the returned `panelId`. The key identifies this execution: reuse it with the
same document on retry; use a new run ID for a new execution. Do not republish a
new card for every progress update.

## Update the same card

`stream` consumes newline-delimited partial task objects, without a `task` wrapper:

```bash
printf '%s\n' '{"passed":14,"skipped":1,"failed":0}' | hiboss panel stream PANEL_ID
```

A long-running stdin stream renews its lease every 15 seconds. A repeated input
observation with unchanged values uses `state.unchanged`. Only submit observations
that were actually checked. Lease renewal alone cannot keep old data fresh.

A new stream must not steal a live producer's lease. If explicitly replacing your
own stopped producer, inspect `hiboss panel state PANEL_ID` and use
`hiboss panel stream PANEL_ID --takeover-epoch EXACT_EPOCH`. A conflict requires
inspection; do not fight another executor in a retry loop.

## Finish and verify

Read both `hiboss panel show PANEL_ID --json` and `hiboss panel state PANEL_ID`.
Create an exact command file using the returned metadata version, definition
revision, and state cursor. `expectedEpoch` is the current unexpired lease epoch,
or null when there is no live lease. `expectedState` is the returned
`{"epoch": ..., "sequence": ...}` cursor, including a null epoch before any lease.

For a just-published card with no stream, the command is:

```json
{
  "protocolVersion": 2,
  "action": "complete",
  "expectedMetadataVersion": 1,
  "expectedDefinitionRevision": 1,
  "expectedEpoch": null,
  "expectedState": { "epoch": null, "sequence": 0 },
  "openRequests": "reject",
  "finalTask": { "passed": 13, "skipped": 1, "failed": 0 },
  "result": { "title": "13 passed · 1 platform skip · 0 failed", "message": "Remote UI E2E completed. On-chain settlement was not tested." }
}
```

```bash
hiboss panel lifecycle PANEL_ID finish.json --idempotency-key remote-e2e-RUN_ID-finish
hiboss panel show PANEL_ID --json
hiboss panel state PANEL_ID
```

Report delivery only after the server confirms a terminal lifecycle and the final
snapshot matches the evidence. A pending/saving response is not completion: retry
the exact same file and key. A revision conflict requires reading the new state;
never overwrite newer work blindly.

Other actions are `pause`, `resume`, `fail`, and `cancel`. Failure needs a result
with a stable `code` and `title`; cancellation needs a reason in `title`.
Paused cards stop accepting observations until resumed and claimed again. Ended
cards cannot reopen. A retry creates a new publication with `supersedesPanelId`.

Boss pin/archive/acknowledgement preferences are separate from task execution.
Do not cancel work because the boss archived a card. Form previews currently
capture local answers; they are not a durable interaction delivery API.
