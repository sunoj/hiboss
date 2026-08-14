# Claude Code transcript format: evidence and session-stream decision

## Executive decision

The current `message | reply | status | session_start | session_end` placeholder is not
capable of representing a Claude Code transcript faithfully. The source is a JSONL event
log with 19 observed top-level record types, nested content blocks, a UUID parent graph,
separate child transcript files, and substantial operational metadata.

For `session_events`, use a lossless source envelope plus a normalized `kind` projection:

```jsonc
{
  "id": "server event id",
  "session_id": "owning session id",
  "sequence": 42,
  "kind": "message | tool_call | tool_result | system | hook | compaction |
           control | file_history | error | raw",
  "source": {
    "record_type": "assistant",
    "record_uuid": "uuid-like string or null",
    "parent_uuid": "uuid-like string, null, or null when absent",
    "timestamp": "ISO-8601 string or null",
    "source_version": "version string or null",
    "line_ordinal": 123
  },
  "actor": {
    "role": "user | assistant | system | null",
    "agent_id": "opaque string or null",
    "is_sidechain": false,
    "parent_session_id": "opaque string or null",
    "parent_tool_use_id": "opaque string or null"
  },
  "payload": { "kind-specific normalized fields": "..." },
  "raw": { "original source record, retained for replay/debug" }
}
```

`sequence` remains the server cursor. It must not be confused with Claude's absent
source sequence: the local records contain no top-level `sequence`, `index`, or byte
offset that provides a durable global order.

This recommendation is high confidence for the local corpus and medium confidence as a
future-proof public contract. The on-disk format is undocumented; the `raw` envelope and
open-ended strings are therefore part of the design, not escape hatches to remove later.

## Evidence and privacy boundary

I scanned the local `~/.claude/projects/**/*.jsonl` corpus directly. The scan was
structure-only: counts, field names, JSON types, enum values, identifier shape,
cardinality, timestamps, parent relationships, and string lengths. No message text,
project path, file content, credential, URL value, prompt, tool input value, or tool
output value is reproduced here. Tool names and record discriminators are included as
structural enum values.

The directory changed slightly while it was being scanned; counts below are from the
final scan and should be read as a measurement snapshot, not an immutable archive.

### Corpus totals

| Measurement | Observed |
|---|---:|
| JSONL files | 768 |
| JSON records | 554,591 |
| malformed/non-object records | 0 |
| direct transcript files | 336 |
| files under `subagents` directories | 432 |
| path depths under the projects root | 336 at depth 2; 406 at depth 4; 26 at depth 6 |
| timestamp-bearing records | about 451,000 |
| records with `isSidechain: true` | 40,622 |

The timestamps span July and August 2026 in this local cache. That is evidence about this
cache, not a claim about all Claude Code releases.

## 1. Characterised source schema

### Top-level record types and frequency

The `type` field was present on every scanned record. Frequency is record count; files is
the number of JSONL files containing the type.

| `type` | Records | Files | Structural role |
|---|---:|---:|---|
| `assistant` | 232,588 | 767 | Model message envelope |
| `user` | 127,289 | 767 | User, injected user-side, or tool-result envelope |
| `attachment` | 42,660 | 735 | Hooks, queued prompts, files, tool/skill/task metadata |
| `last-prompt` | 25,625 | 336 | Resume leaf pointer; `lastPrompt` is optional in this corpus |
| `mode` | 24,872 | 299 | Mode state; observed value `normal` |
| `permission-mode` | 24,793 | 298 | Permission state; `auto`, `plan`, `acceptEdits` observed |
| `ai-title` | 24,463 | 315 | Generated title metadata |
| `queue-operation` | 24,084 | 331 | Queue bookkeeping; `enqueue`, `dequeue`, `remove`, `popAll` |
| `system` | 18,134 | 300 | Hooks/turns/compaction/refusal/away/system status |
| `file-history-delta` | 5,554 | 290 | File-history backup delta |
| `file-history-snapshot` | 3,130 | 298 | File-history checkpoint |
| `pr-link` | 729 | 25 | PR metadata |
| `relocated` | 215 | 2 | Relocation metadata |
| `worktree-state` | 214 | 2 | Worktree metadata |
| `agent-name` | 163 | 4 | Agent display-name metadata |
| `result` | 25 | 1 | Non-session result record; no `sessionId` observed |
| `started` | 25 | 1 | Non-session start record; no `sessionId` observed |
| `agent-setting` | 22 | 1 | Agent setting metadata |
| `frame-link` | 6 | 1 | Frame/link metadata |

Absent from this 768-file snapshot are `progress`, `summary`, `custom-title`,
`bridge-session`, and other types supported by some community parsers. Absence is not
evidence that Claude Code never emits them.

### Per-type top-level fields

Fields in the “always” column were present on every observed record of that type. Fields
in “optional” were present on some records. A field being always present locally is not
promoted to a universal contract when community evidence contradicts it.

| Type | Always observed | Optional observed |
|---|---|---|
| `assistant` | `type`, `cwd`, `entrypoint`, `gitBranch`, `isSidechain`, `message`, `parentUuid`, `sessionId`, `timestamp`, `userType`, `uuid`, `version` | `advisorModel`, `agentId`, `apiErrorStatus`, `attributionAgent`, `attributionMcpServer`, `attributionMcpTool`, `attributionPlugin`, `attributionSkill`, `error`, `isAbortedMidStream`, `isApiErrorMessage`, `requestId`, `sessionKind`, `session_id`, `slug`, `supersedesUuids`, plus the always-field values may be null only where noted below |
| `user` | `type`, `cwd`, `entrypoint`, `isSidechain`, `message`, `parentUuid`, `sessionId`, `timestamp`, `userType`, `uuid`, `version` | `agentId`, `classifierMetaLines`, `imagePasteIds`, `interruptedByShutdown`, `interruptedMessageId`, `isCompactSummary`, `isMeta`, `isVisibleInTranscriptOnly`, `mcpMeta`, `origin`, `permissionMode`, `promptId`, `promptSource`, `queuePriority`, `sessionKind`, `session_id`, `slug`, `sourceToolAssistantUUID`, `sourceToolUseID`, `toolDenialKind`, `toolEndsTurn`, `toolUseResult`, `userFeedback` |
| `attachment` | `type`, `attachment`, `cwd`, `entrypoint`, `gitBranch`, `isSidechain`, `parentUuid`, `sessionId`, `timestamp`, `userType`, `uuid`, `version` | `agentId`, `sessionKind`, `session_id`, `slug` |
| `system` | `type`, `cwd`, `entrypoint`, `isSidechain`, `parentUuid`, `sessionId`, `subtype`, `timestamp`, `userType`, `uuid`, `version` | `apiRefusalCategory`, `apiRefusalExplanation`, `commands`, `compactMetadata`, `content`, `direction`, `durationMs`, `fallbackModel`, `hasOutput`, `hookAdditionalContext`, `hookCount`, `hookErrors`, `hookInfos`, `isMeta`, `level`, `logicalParentUuid`, `messageCount`, `originalModel`, `pendingBackgroundAgentCount`, `pendingWorkflowCount`, `preventedContinuation`, `refusedUserMessageUuid`, `requestId`, `retractedMessageUuids`, `scope`, `sessionKind`, `session_id`, `slug`, `stopReason`, `toolUseID`, `trigger` |
| `last-prompt` | `type`, `leafUuid`, `sessionId` | `lastPrompt` (25,355/25,625) |
| `queue-operation` | `type`, `sessionId`, `timestamp`, `operation` | `content` (18,707/24,084) |
| `mode` | `type`, `mode`, `sessionId` | none observed |
| `permission-mode` | `type`, `permissionMode`, `sessionId` | none observed |
| `ai-title` | `type`, `aiTitle`, `sessionId` | none observed |
| `agent-name` | `type`, `agentName`, `sessionId` | none observed |
| `agent-setting` | `type`, `agentSetting`, `sessionId` | none observed |
| `pr-link` | `type`, `prNumber`, `prRepository`, `prUrl`, `sessionId`, `timestamp` | none observed |
| `relocated` | `type`, `relocatedCwd`, `sessionId` | none observed |
| `file-history-delta` | `type`, `backup`, `messageId`, `snapshotMessageId`, `timestamp`, `trackingPath` | none observed |
| `file-history-snapshot` | `type`, `isSnapshotUpdate`, `messageId`, `snapshot` | none observed |
| `worktree-state` | `type`, `sessionId`, `worktreeSession` | none observed |
| `frame-link` | `type`, `frameUrl`, `path`, `sessionId`, `timestamp`, `title` | none observed |
| `started` | `type`, `agentId`, `key` | none observed |
| `result` | `type`, `agentId`, `key`, `result` | none observed |

`parentUuid` was present on the message-like and system/attachment records, but was
null on 785 records. `sessionId` was present on every observed type except `started` and
`result`. Do not make either field a universal database invariant without retaining an
absent/null distinction.

The parallel `session_id` field is not a harmless alias: it appeared on 204,016 assistant
records, 102,855 user records, 38,797 attachment records, and 8,200 system records, and
the local scan found records where `sessionId` and `session_id` differed. Preserve both
under source metadata; choose `sessionId` as the primary owner only when it is present.

### Message envelopes and content blocks

All 232,588 assistant records had a `message` object whose observed fields were
`id`, `type`, `role`, `model`, `content`, `stop_reason`, `stop_sequence`, `stop_details`,
`usage`, and `diagnostics`. All assistant content was an array in this corpus.

User `message` objects had `role` and `content`. User content was an array in 118,037
records and a string in 9,252 records. Arrays contained text, tool-result, and image
blocks. A parser must not require a single user shape.

| Nested discriminator | Count | Observed fields | Notes |
|---|---:|---|---|
| assistant `text` | 49,688 | `type`, `text` | Text can be very large: p95 1,218 characters, max 181,596 in the scan |
| assistant `thinking` | 64,896 | `type`, `thinking`, `signature` | Every stored `thinking` string was empty; every block had a signature. This is storage/config evidence, not evidence that no reasoning occurred |
| assistant `tool_use` | 117,709 | `type`, `id`, `name`, `input`, `caller` | Tool input is an opaque object whose shape depends on `name` |
| assistant `server_tool_use` | 299 | `type`, `id`, `name`, `input` | Must not be rejected as an ordinary unknown tool block |
| assistant `advisor_tool_result` | 223 | `type`, `tool_use_id`, `content` | A result-like assistant block |
| assistant `fallback` | 4 | `type`, `from`, `to` | Model fallback metadata block |
| user `tool_result` | 117,850 | `type`, `tool_use_id`, `content`, optional `is_error` | `content` was string in 117,012 and array in 838; p95 string length 4,999, max 85,289 |
| user `image` | 25 | `type`, `source` | Image source is structured; do not stringify it into a prompt |

`tool_result.is_error` was `true` on 4,052 blocks, `false` on 86,981, and absent on
26,817. Absence is semantically different from false when diagnosing format drift.

Assistant usage included the four basic token keys on every observed assistant message:
`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, and
`cache_read_input_tokens`. Newer/variant usage keys were also common:
`server_tool_use`, `service_tier`, `cache_creation`, `inference_geo`, `iterations`,
`speed`, and `output_tokens_details`. Preserve the complete usage object rather than
copying only the four familiar counters.

Observed stop reasons were `tool_use` (205,443), `end_turn` (11,007), null-like
`stop_reason` (16,056), and `stop_sequence` (82). These counts include assistant records
whose other metadata may represent a partial or fallback response.

### Tool pairing

The pairing key is `assistant.message.content[].id` for a `tool_use` block and
`user.message.content[].tool_use_id` for a `tool_result` block. It is not the line UUID,
timestamp, or parent UUID.

The final pair scan found:

| Pairing observation | Count |
|---|---:|
| tool-use blocks with a same-file result id | 117,706 of 117,709 |
| tool-use ids without a result | 3 |
| result blocks whose id had a same-file tool use | 117,846 of 117,850 |
| result ids without a same-file tool use | 4 |
| paired result ids whose first result was after the first use in file order | 117,695 |
| one-use/one-result ids | 117,544 |
| ids with another multiplicity/order shape | 151 |

Therefore, use the ID as the primary relation but allow missing, duplicate, repeated,
or late results. A normalized tool-call projection may point to a result, but must also
retain the original message records and the unpaired result event.

The user envelope additionally carried `sourceToolAssistantUUID` on 117,850 records,
`sourceToolUseID` on 44 records, and `toolUseResult` on 116,954 records. `toolUseResult`
was not one stable schema: it appeared as object, string, and array, and its object keys
varied by tool. Treat it as opaque JSON with structural indexing, not as a universal
result object.

### System, hooks, errors, and compaction

Observed `system.subtype` values and counts were:

| Subtype | Count | Structural interpretation |
|---|---:|---|
| `stop_hook_summary` | 8,202 | Hook batch summary; hook counts/errors/info/output and continuation decision |
| `turn_duration` | 7,926 | Duration and message-count bookkeeping |
| `away_summary` | 1,928 | System recap |
| `scheduled_task_fire` | 32 | Scheduled-task lifecycle |
| `compact_boundary` | 20 | Compaction boundary; has `compactMetadata` |
| `local_command` | 19 | Local command marker |
| `model_refusal_fallback` | 6 | Refusal/fallback status |
| `permission_retry` | 1 | Permission retry status |

`compact_boundary` carried `compactMetadata`; the observed nested keys include trigger,
pre/post token counts, duration, preserved-message metadata, and discovered-tool
metadata. `logicalParentUuid` appeared on 20 system records, which is a second lineage
pointer and not interchangeable with `parentUuid`.

There were 17,148 `attachment.hook_success` records. Their complete observed fields were
`type`, `hookName`, `toolUseID`, `hookEvent`, `content`, `stdout`, `stderr`, `exitCode`,
`command`, and `durationMs`. Hook events observed were `SessionStart` (527),
`PostToolUse` (16,648), and `PreToolUse` (25). Other hook attachment types included
`hook_additional_context` (37), `hook_cancelled` (9), `hook_non_blocking_error` (1),
and `hook_system_message` (5).

Error-like evidence is distributed, not one record type: 80 assistant records had
`error`, 82 had `isApiErrorMessage`, 17 had `apiErrorStatus`, 4,052 tool results had
`is_error: true`, 1,234 user records had `toolDenialKind`, and nine attachments were
`hook_cancelled`. A useful normalized error event is a projection; the source record
must remain authoritative.

### Attachments and operational records

The 28 observed `attachment.type` values are:

`agent_listing_delta`, `auto_mode`, `command_permissions`, `compact_file_reference`,
`date_change`, `deferred_tools_delta`, `diagnostics`, `edited_text_file`, `file`,
`goal_status`, `hook_additional_context`, `hook_cancelled`, `hook_non_blocking_error`,
`hook_success`, `hook_system_message`, `invoked_skills`, `mcp_instructions_delta`,
`nested_memory`, `plan_mode`, `plan_mode_exit`, `plan_mode_reentry`, `queued_command`,
`read_truncation_notice`, `skill_listing`, `task_reminder`, `task_status`,
`total_tokens_reminder`.

The largest attachment families were `hook_success` (17,148), `task_reminder` (12,930),
`queued_command` (6,381), `deferred_tools_delta` (776), `skill_listing` (764), and
`agent_listing_delta` (356). Attachment payloads are type-specific and may contain
arrays, nested objects, paths, command output, or prompt-like content. Normalize the
discriminator and retain the complete object; do not make a large closed attachment
enum a crash condition.

The 24,084 queue records had operations `enqueue` (12,101), `remove` (6,546), `dequeue`
(5,377), and `popAll` (60). `content` was a string when present; most such strings were
not JSON objects in this corpus, so a parser must not assume that queue content is a
machine-readable task object.

`file-history-snapshot.snapshot` consistently contained `messageId`,
`trackedFileBackups`, and `timestamp`. `file-history-delta` consistently contained
`backup`, `messageId`, `snapshotMessageId`, `timestamp`, and `trackingPath`.

### Sub-agents and Task/Agent runs

The local format represents child work in multiple coordinated ways:

1. Child files live under `subagents` directories. There were 432 such files; 406 were
   one level below that directory and 26 were deeper, so nesting is real.
2. Child records carry `isSidechain: true`; 40,622 records did so, and every such record
   in the focused scan carried an `agentId`.
3. The current local corpus used the `Agent` tool 413 times. No `Task` tool-use block was
   observed, although task-management tools (`TaskCreate`, `TaskUpdate`, `TaskList`,
   `TaskGet`, `TaskStop`, `TaskOutput`) were present. A parser must support both `Task`
   and `Agent` names because community parsers and Claude Code versions use both.
4. `Agent` input keys varied. The common keys were `description` (413), `prompt` (413),
   `subagent_type` (400), `run_in_background` (175), `model` (59), and `isolation` (14).
5. Tool-result structured payloads carried `agentId` on 409 records, `taskId` on 443,
   and `backgroundTaskId` on 8,704. In a value-only equality check, 403 of 431 distinct
   sidechain `agentId` values intersected result `agentId` values. This is strong but
   incomplete attribution evidence.
6. 13,798 sidechain records carried `sourceToolAssistantUUID`; only five sidechain
   records carried `sourceToolUseID`. The source assistant UUID is therefore a more
   prevalent child-side backlink in this corpus.

The child filename/stem is not the child `sessionId`: in 431 child files with one
observed session id, the session id differed from the filename stem. The safe relation
is a composite of child path, `agentId`, result payload identifiers, source assistant
UUID, and the parent tool call—not a filename equality assumption.

The record-level `parentUuid` graph is per transcript. It connects a child record to a
record in that same file; it does not by itself cross the parent/child file boundary.
Preserve a derived relation with nullable `parent_session_id`, `parent_tool_use_id`,
`child_agent_id`, and `agent_depth` when known. The local records did not expose a
universal depth field.

### Ordering and branches

There is no source sequence. Physical JSONL line order is the best local append order,
but timestamps are not a total order: a chronology pass found 26,658 timestamp
inversions and 10,427 adjacent timestamp ties. Timestamps are useful display metadata,
not replay cursors.

UUIDs are present on most message-like records. A chronology pass found 420,646 UUID
fields, including 178 duplicate UUIDs within a file. Parent references overwhelmingly
point backward: 419,802 pointed to an earlier line and 59 were unresolved in that pass;
no future parent reference was observed. The graph is still partial because roots,
null parents, missing parents, duplicates, and cross-file child relationships exist.

Forks are not rare: 492 files had at least one parent with multiple children; 5,076
parent nodes had multiple children, with a maximum of four. A faithful reader must not
flatten by timestamp and silently discard abandoned branches. It should retain the DAG
and derive an active path only as a view projection.

### Format drift visible in this cache

The cache spans only two months, so it cannot establish long-term release behavior. It
does show intra-cache drift:

- Types present only in newer-looking records include `frame-link` and several metadata
  families that are absent from most files; other types are concentrated in older
  subsets.
- Fields only seen in August in the scan included `advisorModel`, `commands`,
  `frameUrl`, `interruptedByShutdown`, `mcpMeta`, `path`, `scope`, and `title`.
- Fields only seen in July included `attributionPlugin`, `pendingWorkflowCount`,
  `queuePriority`, `toolEndsTurn`, and `userFeedback`.
- Nested blocks `server_tool_use`, `advisor_tool_result`, and `fallback` are real local
  records even though simpler community schemas omit them.
- The local attachment enum has 28 values, while the surveyed tjsonl v0.1 spec lists
  21. That is direct evidence that a closed attachment enum becomes stale quickly.

These are verified observations. The inference is that field/type drift will continue;
the evidence supports detecting it, not predicting the next name.

## 2. Proposed `session_events` taxonomy and payload

### Kinds

The normalized kinds below are deliberately semantic and small. `source.record_type`
and `raw` prevent the normalized taxonomy from becoming a lossy replacement for the
source.

| Kind | Emits for | Payload essentials |
|---|---|---|
| `message` | `user` and `assistant` envelopes | `role`, ordered `blocks`, source message metadata, `is_meta`, `is_sidechain` |
| `tool_call` | `tool_use` and `server_tool_use` blocks | `tool_use_id`, `name`, `input`, `caller`, owning message event id |
| `tool_result` | `tool_result` and `advisor_tool_result` blocks | `tool_use_id`, JSON `content`, `is_error` when present, `toolUseResult` opaque payload, source backlinks |
| `system` | Unclassified `system` records | `subtype`, `level`, `content`, all source metadata |
| `hook` | Hook attachments and hook summary/error system records | `hook_type`, `hook_event`, `hook_name`, tool link, stdout/stderr/content, decision/error metadata |
| `compaction` | `compact_boundary` and compact-summary records | compact metadata, preserved-message/discovered-tool counts, logical parent, summary reference |
| `control` | Titles, mode/permission, queue, PR, relocation, agent/worktree/frame metadata, lifecycle records | `record_type` plus exact source fields; never pretend these are messages |
| `file_history` | File-history snapshot and delta records | snapshot/delta discriminator and exact nested object |
| `error` | A standalone normalized error projection when an API/permission/transport error is detected | error class, source event id, safe summary; source payload remains attached |
| `raw` | Unknown top-level type, unknown block, unknown attachment, malformed line, or failed normalization | `record_type`, structural fingerprint, raw JSON/text if policy allows, parser error if any |

Thinking is an ordered block inside `message.payload.blocks`, with `{type: "thinking",
text, signature}`. It is not split into a second event by default; splitting it would
duplicate assistant ordering and make a mixed text/thinking/tool turn harder to replay.
If a future producer emits token/chunk deltas, add a separate `message_delta` kind with
an explicit parent message id and offset rather than pretending those deltas are whole
messages.

Sub-agent is a relation, not a replacement for the child message kind. Add the nullable
relation fields in `actor` and include `child_session_id`, `parent_tool_use_id`, and
`agent_id` in `tool_call`/`tool_result` payloads when the correlation is verified.

### Field mapping

| Source | Normalized destination |
|---|---|
| top-level `type`, `uuid`, `parentUuid`, `timestamp`, `version` | `source.record_type`, `source.record_uuid`, `source.parent_uuid`, `source.timestamp`, `source.source_version` |
| top-level `sessionId` | event `session_id`; preserve `session_id` separately under `source` when present and different |
| `cwd`, `gitBranch`, `entrypoint`, `userType`, `slug`, `sessionKind` | `source.metadata` / `actor` metadata; do not put paths or branches in display text |
| `isSidechain`, `agentId`, `sourceToolAssistantUUID`, `sourceToolUseID` | `actor` and relation metadata |
| `assistant.message.role`, `content` | `message.payload.role`, ordered `blocks` |
| assistant `message.id`, `model`, `stop_reason`, `stop_sequence`, `stop_details`, `usage`, `diagnostics`, `effort` | `message.payload.turn_metadata`; preserve complete objects |
| user `message.content` string/array | `message.payload.blocks`, with a string represented as one text block |
| assistant `thinking` | message block `{type, text, signature}` |
| assistant `text` | message block `{type, text}` |
| assistant `tool_use` / `server_tool_use` | `tool_call` fields, plus a reference block in the assistant message |
| user `tool_result` / assistant `advisor_tool_result` | `tool_result` fields, plus a reference block in the source message |
| user `toolUseResult` | `tool_result.payload.structured_result` as opaque JSON |
| `system.subtype`, `content`, hook/compaction fields | `system`, `hook`, or `compaction` payload according to subtype; preserve unclassified fields |
| `attachment. type` and nested object | `hook`, `control`, or `raw` according to a known mapping; always retain `attachment_type` and full object |
| `file-history-*` | `file_history.payload` with `snapshot`/`backup` and message ids |
| titles, modes, permissions, queue, PR, relocation, worktree, frame, started/result | `control.payload.record_type` plus exact fields |
| unknown source record/block/attachment | `raw` with an open string discriminator and original payload |

The source message and the derived tool events intentionally share references. The
source event is the replay authority; the derived `tool_call`/`tool_result` rows are an
indexed view for mobile rendering and queries.

### Explicit loss inventory

If the current placeholder were merely expanded to `message` and `reply`, it would lose
tool identity and result pairing, all 64,896 thinking signatures/blocks, all hook output,
all 20 compaction boundaries, sidechain relationships, the 28 attachment subtypes,
file-history checkpoints, queue operations, branch structure, API/permission errors,
usage detail, images, model fallback blocks, and unknown future records.

The proposed normalized projection still intentionally does not promise:

- exact terminal cursor semantics or ANSI replay; none of the observed source evidence
  establishes a terminal-byte stream,
- token/chunk timing inside an assistant message; the JSONL has whole message records,
- a universal parent relation across separate child files; some links remain ambiguous,
- non-sensitive rendering of every raw payload; the product must apply access control and
  output-size limits,
- a stable interpretation of every tool-specific input/result object.

Those are honest losses or policy boundaries. They are not silent drops because `raw`
and source metadata remain available.

## 3. Drift and ingestion strategy

### Ingestion rules

1. Parse each physical line independently. A malformed line becomes a `raw`/ingest-error
   event with line ordinal, byte/character length, and parser error; it must not poison
   the remainder of the file.
2. Treat top-level and nested discriminators as open strings. Unknown `type`, block
   `type`, attachment `type`, subtype, tool name, hook event, or operation must be
   stored, counted, and rendered through a fallback. Never fail the session stream merely
   because a new enum value appeared.
3. Preserve the original JSON object and all fields alongside normalized fields. Do not
   allow an allowlist projection to be the only persisted copy.
4. Pair by `tool_use_id`/`id` when possible, but emit unpaired calls/results and retain
   duplicate/late pair candidates. Pairing is a relation, not a reason to delete a
   source row.
5. Use JSON types as part of the observed schema. A field changing from string to array
   is drift even if the key name is familiar.
6. Preserve the distinction between absent, null, false, empty string, and empty array
   when the source provides it. The local `is_error` counts demonstrate why this matters.

### Detection and alerting

Run an observe-only schema extractor over every ingest batch and store structural
fingerprints keyed by source version/month and record type. The fingerprint should
contain field names, JSON types, nested discriminator values, cardinalities, and counts;
it must not contain free text or raw values in the drift report.

Alert on:

- a new top-level type, block type, attachment type, hook event, or tool name,
- a field type change or a field becoming absent on a previously common shape,
- an unknown record fallback, malformed line, or failed normalization,
- an increase in unpaired/duplicate tool IDs,
- unresolved parent UUIDs, future parent references, duplicate UUIDs, or branch counts,
- a change in sidechain files or child-link success rate,
- raw-payload size growth beyond mobile/server limits,
- a parser version/source-version combination that has not passed fixtures.

The alert should include only the structural fingerprint and counts. A developer can
inspect a private local fixture separately when needed.

### Prior-art trade-offs

| Project | What it actually does | Decision for HiBoss |
|---|---|---|
| [Claude Code Viewer](https://github.com/d-kimuson/claude-code-viewer) | `parseJsonl.ts` parses each line and returns an `x-error` record containing the original line on JSON/Zod failure. Its Claude parser pairs results by tool id, folds branch trees, labels subagents from `Task`/`Agent` calls, and emits a display projection. Its `AttachmentEntrySchema` has a loose fallback for unknown attachment types. | Borrow per-line errors, tool pairing, branch awareness, and loose attachment parsing. Do not make the Zod union the ingestion boundary: an unknown top-level record becomes an error rather than a typed lossless event, and its normalized block schema is narrower than this corpus (`server_tool_use`, `advisor_tool_result`, and `fallback` need preservation). Sources: [parseJsonl.ts](https://github.com/d-kimuson/claude-code-viewer/blob/main/src/server/core/claude-code/functions/parseJsonl.ts), [conversation schema](https://github.com/d-kimuson/claude-code-viewer/blob/main/src/lib/conversation-schema/index.ts), [attachment schema](https://github.com/d-kimuson/claude-code-viewer/blob/main/src/lib/conversation-schema/entry/AttachmentEntrySchema.ts). |
| [Claude Code Trace](https://github.com/delexw/claude-code-trace) | Rust `Entry` defaults many missing/null fields, keeps hook names as strings, classifies messages into user/AI/system/teammate/compact/hook, groups tool calls/results, detects UUID DAGs, and builds a `ProcGraph` for subagents. It also classifies several record types as noise and drops them from its conversation projection. | Borrow permissive deserialization, open hook strings, DAG handling, tool categories, and subagent graph ideas. Keep its display classification separate from our raw event log; dropping `file-history`, queue, progress, or unknown records is acceptable for a view but not for `session_events`. Sources: [entry.rs](https://github.com/delexw/claude-code-trace/blob/main/src-tauri/src/parser/entry.rs), [classify.rs](https://github.com/delexw/claude-code-trace/blob/main/src-tauri/src/parser/classify.rs), [subagent.rs](https://github.com/delexw/claude-code-trace/blob/main/src-tauri/src/parser/subagent.rs). |
| [cc_transcript_viewer](https://github.com/tim-hua-01/cc_transcript_viewer) | `claude_parser.py` pairs tool results, identifies synthetic user records, folds branches, maps child files to parent paths, and emits `user`, `assistant`, `system`, `notice`, `attachment`, `instructions`, and `branch`. `event_schema.py` also defines `raw`, but the Claude parser's normal path ignores many unrecognized source records. | Borrow its separation of source parsing and frontend events, progressive disclosure, notices, and branch markers. Do not copy its closed `BLOCK_TYPES` or its rule that the normalized tool result is a small `{text, images, structured}` object; preserve source result JSON. Sources: [claude_parser.py](https://github.com/tim-hua-01/cc_transcript_viewer/blob/main/claude_parser.py), [event_schema.py](https://github.com/tim-hua-01/cc_transcript_viewer/blob/main/event_schema.py). |
| [tjsonl](https://github.com/coo-labs/tjsonl) | The observed-schema extractor records per-type required/optional fields, nested block types, attachment types, tool names, and input-key sets. The line walker isolates malformed lines. The validator reports unknown event types, missing/unknown fields, attachment types, tool names, and unparseable JSON. | Adopt this as an observe-only drift discipline and CI fixture shape. Do not use its v0.1 closed enum as our runtime gate: this corpus has 19 types versus its 11 and 28 attachment values versus its 21; its “every line has sessionId” rule does not fit local `started`/`result`. Sources: [spec](https://github.com/coo-labs/tjsonl/blob/main/spec/transcript-schema-spec.md), [extractor](https://github.com/coo-labs/tjsonl/blob/main/src/tjsonl/extract.py), [validator](https://github.com/coo-labs/tjsonl/blob/main/src/tjsonl/validate.py), [walker](https://github.com/coo-labs/tjsonl/blob/main/src/tjsonl/walk.py). |
| [AgentsView](https://github.com/kenn-io/agentsview) | Its Claude parser builds a message-centric `ParsedMessage` with role, thinking text, tool calls/results, usage, source type/subtype, and source UUIDs. It detects DAG forks, queued commands, progress-based subagent links, background lineage, persisted tool-result files, and relationship types (`continuation`, `subagent`, `fork`). Its classifier deliberately drops structural/noise types from the conversation projection. | Borrow its indexed projection model and explicit relationship types. Keep the raw source event log independently; message-centric analytics are not enough to reconstruct hooks, file history, queue changes, or unknown future records. Sources: [claude.go](https://github.com/kenn-io/agentsview/blob/main/internal/parser/claude.go), [types.go](https://github.com/kenn-io/agentsview/blob/main/internal/parser/types.go), [claude_lineage.go](https://github.com/kenn-io/agentsview/blob/main/internal/parser/claude_lineage.go). |

The practical rule is: strict validation may fail a fixture or raise an alert, but it
must never block ingestion or silently replace an unknown record with nothing.

## 4. Mobile transcript view

The mobile UI should be a dense transcript projection, not one visually equal row per
JSONL line. The source has 554,591 records, including roughly 118k tool calls and 118k
tool results; most rows are operational or tool machinery rather than conversation.

### Show prominently

- User text and assistant text as the primary chronological rows.
- Assistant turn metadata on demand: model, stop reason, token summary, API-error badge.
- Tool calls inline with name, a compact input summary, and a result state (`pending`,
  `ok`, `error`, `unpaired`, or `duplicate`).
- Tool results collapsed by default. Show a bounded preview, byte/character count, and
  “show full output”/copy actions. The p95 string result is about 5k characters and the
  maximum observed result is about 85k, so eager rendering is a performance and battery
  risk.
- Thinking as a collapsed block. In this cache it is signature-only/empty, so display
  “thinking unavailable” rather than a blank expandable area; future readable thinking
  must remain collapsed by default and retain its signature.
- Hook failures, permission denials, API errors, compaction boundaries, and interrupted
  turns as compact high-signal markers. A compaction marker must say that context was
  compacted and offer its metadata; it should not look like an ordinary assistant reply.
- Agent/Task child runs as expandable subagent cards with status, duration/usage when
  known, and a jump-to-child action. Keep the parent tool call visible while the child
  is open.
- Branch/fork markers and a clear active-path indicator. Abandoned branches belong in a
  collapsed “older branch” section, never silently discarded.

### Collapse or hide by default

- `file-history-snapshot`/`file-history-delta`, mode, permission-mode, titles, PR links,
  relocation, worktree, frame, and queue bookkeeping under an “activity/details” layer.
- Routine successful hooks and `stop_hook_summary` records as compact chips; expand to
  stdout/stderr, command, hook name, and duration.
- Large file attachments and tool outputs behind a size-aware disclosure. Never put all
  output into the initial SwiftUI layout tree.
- Unknown/raw events behind a visible “N unrecognized events” marker with a debug/detail
  screen. They must remain searchable/copyable for diagnosis.

The view should preserve source order for the displayed projection, use the server
sequence for resume, and never use wall-clock sorting to repair the source graph. A
reader who scrolls upward must be scroll-locked while live events accumulate; provide
an unread count and “jump to live”. Batch updates and render a bounded window. These
choices follow from the measured volume and from the existing session-stream contract,
not from treating the source as a chat-bubble feed.

## Verified versus inferred conclusions

Verified locally: the counts, field presence, JSON types, enumerated values, nested block
shapes, tool-id pairing behavior, sidechain/file layout, UUID parent relationships,
timestamp inversions, branch frequency, and string-length distributions above.

Verified in the cited prior-art repositories: their parser taxonomies, pairing keys,
branch/subagent strategies, unknown handling, and intentional projection drops.

Inferred: the format will continue to drift; `session_events` should remain open and
lossless; mobile should progressively disclose most records; and the normalized taxonomy
should be treated as a replaceable view over a durable source envelope. Those inferences
are supported by the observed two-month drift and by the prior art's repeated need for
parser updates, but they are not guarantees from Anthropic.

Confidence: high for the local structural characterization; high for the lossless/raw
ingestion decision; medium for the exact long-term taxonomy because an undocumented
format may add new record families; low for any assumption that current field names or
tool enums will remain stable.
