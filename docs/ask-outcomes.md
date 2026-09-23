# Ask outcomes and automatic defaults

Status: implemented locally during SAFE-01; not deployed or distributed.

An answer equal to a configured default is not evidence that a Boss chose it.
The server marks timeout-generated replies with `metadata.auto_default: true`.
Clients must preserve that distinction when exposing the answer to an agent.

## CLI contract

Use `hiboss ask --json` for automation. Stdout contains one JSON object; progress
and attachment diagnostics remain on stderr. JSON mode omits the optional unread
message pre-warning to preserve a parseable stdout stream.

| Outcome | Meaning | reply_id | action |
| --- | --- | --- | --- |
| `reply` | A reply message was returned without the automatic-default flag | Returned message ID | String if supplied by reply metadata, otherwise null |
| `auto_default` | The server produced a timeout-default reply | Returned message ID | null |
| `local_default` | Polling returned no replies and the CLI used its configured fallback | null | null |
| `timeout` | Polling returned no replies and no default was configured | null | null |

Every result also contains the original `message_id` and the answer `body` (null
when absent). For example:

```json
{"message_id":"ask-1","reply_id":"reply-1","outcome":"auto_default","body":"Wait","action":null}
```

`reply` deliberately does not mean human approval. An Agent can be a Boss, and
provenance and authorization must be checked in the actual execution context.
An explicit reply that happens to equal the default remains `reply`.

The local polling timeout can occur before server-side expiry. A `local_default`
is therefore not proof of a persisted answer. Recover using the original message
ID before relying on server state. This change does not modify server expiration,
selection, signature verification, or HTTP contracts.

Plain text retains ordinary reply bodies. Automatic defaults begin with
`[auto_default]` or `[local_default]` and explain the lack of authorization.
Default paths never print `Action:` or request acknowledgment of a human reply.
For ordinary replies, action commands are displayed only; `ask` does not run them.
Completed polling still exits successfully; transport failures keep existing exit
codes. Consumers must inspect the outcome rather than infer approval from exit 0.

## MCP contract

The ask tool returns the answer in text and adds `structuredContent` with
`message_id`, `reply_id`, `outcome`, and `body`. MCP does not configure a local
fallback, so its outcomes are `reply`, `auto_default`, and `timeout`.

Automatic-default markers also appear in SSE channel content, inbox, and search
formatting. Signature verification runs on the original message before display
formatting; the signed body is not rewritten before verification.

## Compatibility and verification

This intentionally changes automatic-default text output. Scripts comparing raw
answer strings should migrate to CLI JSON or MCP structured content. Ordinary
reply text is unchanged. Older clients still need direct metadata inspection.

Regression cases cover server defaults, action suppression, explicit replies
matching defaults, missing/empty reply lists, timeout recovery IDs, bodyless
replies, JSON opt-in, and MCP text/structured output. The takeover work log records
actual test results and outstanding rollout scope.
