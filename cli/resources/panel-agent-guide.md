# HiBoss dynamic notification delivery

Dynamic notifications, live cards, and Panels refer to `hiboss panel`.
Use Panels for task progress, test results, downloads, benchmark comparisons,
and ongoing monitoring. Use `hiboss ask` only when a human decision is actually
required. A completed report does not require a blocking question.

## Discover the installed interface

Run `hiboss panel --help` once. This guide describes protocol v2. The required
commands are `validate`, `publish`, `update`, `stream`, `state`, `complete`,
`fail`, `cancel`, `pause`, `resume`, `renew`, `doctor`, and `show`.
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
  "lifecycle": { "mode": "run", "expectedUpdateIntervalSeconds": 15, "ttlSeconds": 3600 },
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
hiboss panel publish report-panel.json --run-id RUN_ID
```

Keep the returned `panelId`. The key identifies this execution: reuse it with the
same document on retry; use a new run ID for a new execution. Do not republish a
new card for every progress update.

## Update the same card

`update` applies one partial task object and exits after the accepted sequence:

```bash
hiboss panel update PANEL_ID '{"passed":14,"skipped":1,"failed":0}'
hiboss panel update PANEL_ID --file progress.json
```

If neither JSON nor `--file` is supplied, `update` reads one JSON object from stdin.
It claims the lease, merges the object exactly like a stream line, sends one
`state.update` (or `state.unchanged`), waits for the acknowledgement, releases the
lease, and prints the accepted sequence. Repeat it as often as needed; no version
numbers are hand-written.

`stream` consumes newline-delimited partial task objects, without a `task` wrapper:

```bash
printf '%s\n' '{"passed":14,"skipped":1,"failed":0}' | hiboss panel stream PANEL_ID
```

A long-running stdin stream renews its lease every 15 seconds. On clean stdin EOF,
it releases the lease after the last acknowledgement. A repeated input observation
with unchanged values uses `state.unchanged`. Only submit observations that were
actually checked. Lease renewal alone cannot keep old data fresh, and streaming
data does not keep a card alive. A long-running producer must deliberately renew
the visibility window:

```bash
hiboss panel renew PANEL_ID
hiboss panel renew PANEL_ID --ttl 7200
```

`ttlSeconds` is optional at publication, defaults to 3600 seconds, and must be an
integer from 60 to 604800. Renewal prints the new expiry. `hiboss panel show <id>`
also prints the stored `expiresAt`. When it lapses, the card leaves the wall but the
task state is untouched; an explicit renewal brings the card back. A boss pin keeps
it visible while lapsed.

A new producer must not steal another executor's live lease. The CLI records the
epoch it claimed for this session. After a crash, a `lease_conflict` is taken over
automatically only when the live epoch equals that recorded epoch. Otherwise inspect
the state and use the exact command named by the error:

```bash
hiboss panel state PANEL_ID
hiboss panel stream PANEL_ID --takeover-epoch EXACT_EPOCH
```

Do not fight another executor in a retry loop.

## Finish and verify

The normal finish commands read `show` and `state` themselves and fill every
metadata, definition, epoch, and state cursor field. Use the same command and its
default idempotency key when retrying:

```bash
hiboss panel complete PANEL_ID --title "13 passed · 1 platform skip · 0 failed" \
  --message "Remote UI E2E completed. On-chain settlement was not tested." \
  --final-task '{"passed":13,"skipped":1,"failed":0}'
hiboss panel fail PANEL_ID --title "Remote UI E2E failed" --code test_failure \
  --message "See the captured report"
hiboss panel cancel PANEL_ID --title "Cancelled by operator"
```

`pause` and `resume` take only the panel ID. `--final-task` accepts inline JSON or
`@path/to/task.json`; `--title`, `--message`, and `--code` are result fields, with
`--code` valid only for `fail`. `--idempotency-key` overrides the retry-safe key.
Use `lifecycle <file>` only when the full versioned command is intentionally needed.

If the full `lifecycle <file>` escape hatch is intentional, a just-published card
with no stream uses the following versioned command; normal agents should use
`complete` instead:

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

Before relying on the channel, run:

```bash
hiboss panel doctor
```

It checks authentication, the resolved session and boss, and confirms a v2 relay
ticket advertises `lease.release` before testing the subscribe handshake without
claiming a lease. A non-zero
result includes the corrective action.
When several bosses are resolved, doctor reports all of them; publication still
requires an explicit `targetBossId`.

Other actions are `pause`, `resume`, `fail`, and `cancel`. Failure needs a result
with a stable `code` and `title`; cancellation needs a reason in `title`.
Paused cards stop accepting observations until resumed and claimed again. Ended
cards cannot reopen. A retry creates a new publication with `supersedesPanelId`.

Boss pin/archive/acknowledgement preferences are separate from task execution.
Do not cancel work because the boss archived a card. Form previews currently
capture local answers; they are not a durable interaction delivery API.
