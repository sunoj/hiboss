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
| `reply` | A decision reply was returned without the automatic-default flag | Returned message ID | String if supplied by reply metadata, otherwise null |
| `auto_default` | The server produced a timeout-default reply | Returned message ID | null |
| `local_default` | Polling returned no replies and the CLI used its configured fallback | null | null |
| `timeout` | Polling returned no replies and no default was configured | null | null |

Every result also contains the original `message_id` and the answer `body` (null
when absent). For example:

```json
{"message_id":"ask-1","reply_id":"reply-1","outcome":"auto_default","body":"Wait","action":null}
```

Only a decision reply counts: a `boss_to_agent` row for an ask to the boss, or a row written by
the other agent for an `--to` ask. The asking agent's own follow-ups and forward copies of the ask
are never an outcome. After the last poll window the CLI reads
`GET /api/messages/:id?replies=decisions`, which applies the same rule on the server, and the CLI
filters again before choosing an outcome.

An `--to` ask is answered only by a reply from a different agent profile. A reply written by the
asking agent never answers it, from whichever session it comes. So an `--to` ask addressed to
another session of the same agent profile is never answered: it times out with `local_default`
or `timeout`. Peers on different agent profiles work as usual.

Only a reply that counts as an answer closes an ask. The asker's follow-ups and boss rows on an
agent-to-agent ask are stored but leave it open, so the deadline still expires it. The boss inbox
answers only `agent_to_boss` messages and returns 404 for any other parent.

The server writes an automatic default only when an ask to the boss times out. An `--to` ask
that times out expires once without an answer, so its outcome is `local_default` or `timeout`.
An ask superseded by a newer ask with options from the same session expires immediately without
its default; its waiting CLI reports `local_default` or `timeout`, never `auto_default`.

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

## Release order

Deploy the Worker before or together with the CLI. The decision read (`?replies=decisions`),
the closing rule and the boss inbox guards are server-side. A new CLI against an older Worker
gets every reply from its final read and filters them itself, so its outcomes stay correct, but
nothing the CLI does can stop a boss-agent answering its own ask on an older Worker. The reply
request and its signed payload are unchanged, so either CLI works with either Worker.

## Known limitations

- An agent-to-agent ask has no claim step. A peer reply that arrives after the deadline expired
  the ask is still stored and counted as its answer by the decision read.
- If the server cannot record a timeout default (the conditional insert fails without the ask
  closing), the ask stays open until a later sweep or session end closes it.

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
