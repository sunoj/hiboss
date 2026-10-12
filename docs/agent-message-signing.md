# Agent Message Signing

Covers the server, the CLI and the MCP plugin. Companion to `docs/message-signing.md`, which
covers the boss → agent direction. The native boss clients do not verify agent signatures;
see Limitations.

## Goal

An agent's message carries an ES256 signature from a key that never leaves the agent's
machine. The server, boss-agents and peer agents verify that signature before they show
the body or act on it. Without signing, an agent's identity is only a bearer credential, so
anyone who holds that string, or the server itself, can author an "agent" message.

Signing proves who wrote a message and that it was not altered. It does not prove that the
content is true or safe. Prompt-injection handling still applies to every body.

## Threat model

What this design defends against:

1. **A leaked bearer credential.** The credential goes out on every HTTP request and sits in
   env vars, MCP configs and shell history. A signing key never goes out over the network.
   Once an agent has a signing key, an attacker who holds only a bearer string cannot send
   a message as that agent, **including from a credential minted with the leaked one**
   (§ Enforcement).
2. **Tampering after admission.** This covers database edits, buggy migrations, and a Worker
   that rewrites a stored message. Peer agents and boss-agents detect it.
3. **Peer impersonation into model context.** A forged `agent_to_agent` message is a
   prompt-injection vector. The receiving CLI or MCP plugin rejects an invalid signature
   before the body reaches the model.

What this design does not defend against:

- **Filesystem compromise of the agent's machine.** The software key file sits next to the
  config that holds the bearer.
- **A malicious server, for any client that does not pin keys.** The server remains the key
  directory, exactly as it is for boss keys.
- **Discord and Telegram readers.** These channels cannot verify a signature. They display server-attested text.

## Server-owned metadata

Client-supplied `metadata` on `POST /api/messages` loses every server-owned key before it is
stored: `provenance`, `source`, `boss_id`, `boss_name`, `auto_default`,
`ask_deadline`, `options`, `file_url`, resolution state, reactions and delivery bookkeeping
(`server/src/message-security/metadata.ts`), so an agent cannot store its own
`provenance`, a forged `source: "ios"`, or `options_resolved: true` on its message.

Every agent-authored row now carries server-written provenance. An unsigned row looks like this:

```json
{ "source": "agent", "provenance": { "version": 1, "source": "agent",
  "actor": { "kind": "agent", "id": "<agent id>" },
  "authentication": { "kind": "api_key", "credential_id": "<agent_keys.id | null>" },
  "signature": { "status": "not_configured" } } }
```

## Keys, enrollment, admission, verification

### Keys

- Algorithm: **ES256 (P-256)**. It reuses the verifiers that already exist in the server, the
  CLI (`ring`), MCP (Web Crypto) and HibossKit (CryptoKit).
- There is one key per **credential** (`agent_keys.id`), stored in `agent_signing_keys`
  (migration `0055`). Revoking a credential retires its key.
- Key ID = `base64url(SHA-256(uncompressed SEC1 public key))`.
- Local storage is `<dir of the real config.json>/signing/<hex(SHA-256(bearer))[0..32]>.json`
  with mode `0600` inside a `0700` directory. The file contains `{version, agent_id,
  agent_key_id, key_id, pkcs8}`. The key is kept out of `config.json` because older CLI and
  MCP builds reject unknown config fields. The path follows symlinks, so a symlinked config
  still finds its key. The MCP plugin derives the same path from `HIBOSS_CONFIG` and the bearer.

### Enforcement is per agent identity

Any credential can mint another credential (`POST /api/agents/me/keys`). If the binding were
enforced per credential, someone holding a leaked bearer could mint a fresh credential that
has no key and send unsigned messages from it. So the rule is:

- Once the agent has enrolled **any** key that a boss has not reset, every message write must be
  signed by the live key bound to the calling credential. An unsigned write gets `401 signed
  message required`. Revoking credentials does not lift the requirement: otherwise a bearer
  holder could mint a credential, revoke every signing credential and send unsigned. If every
  signing credential is revoked, the agent cannot write until a boss resets its keys.
- A credential with no key cannot bind one through first use while the requirement holds. It
  needs an endorsement from a live key (see Registration).
- An unsigned write admitted just before an enrollment commits is stored. That is equivalent to
  an unsigned write sent just before the enrollment, which any bearer holder could send.

### Registration

`POST /api/agents/me/signing-keys` with `{public_key, proof, endorsement?}`. The proof is
`ES256("hiboss-agent-key-v1\n" + agent_key_id + "\n" + agent_id + "\n" + public_key)`.

| Path | When | Trust |
| --- | --- | --- |
| **First use** | `hiboss key enroll`, and the agent has no live keys | Trust on first use. The boss receives a system message with the key fingerprint, and an audit row is written. |
| **Endorsed** | `hiboss key rotate`, or another credential of an agent that already signs | `endorsement` is a `hiboss-agent-key+jws` token signed by one of the agent's live keys. It covers `{agent_id, agent_key_id, key_id, issued_at}` and must be no more than 300 s old. |
| **Reset** | Lost key, or a suspected compromise | `DELETE /api/boss/agents/:agentId/signing-keys[/:keyId]` (admin or manager). With no live keys left, the agent can enroll by first use again. Re-enrolling on the same device reuses the local key file, so delete that file to rotate the key. |

`GET /api/agents/me/signing-keys` and `GET /api/boss/agents/:agentId/signing-keys` list the
live keys with their fingerprints. `hiboss setup` does not enroll automatically.

### Signed message format

The token is a compact JWS with header `{alg: "ES256", kid, typ: "hiboss-agent-message+jws"}`. The
payload has exactly these keys:

```json
{
  "version": 1, "purpose": "hiboss.agent-message", "message_id": "<uuid v4>",
  "issued_at": 1791763200, "agent_id": "<agent id>",
  "session_id": "<id> | null",
  "action": { "kind": "send", "audience": { "kind": "boss" } },
  "body": "Deploy finished", "mode": "async", "timeout": null,
  "file_url": null, "options": null, "metadata": { "content": "…" }
}
```

| `action.kind` | Endpoint | Other fields |
| --- | --- | --- |
| `send` | `POST /api/messages` | `audience`: `{kind: "boss"}` or the resolved `{kind: "agent", agent_id, session_id}` |
| `reply` | `POST /api/messages/:id/reply` | `message_id` of the parent; `audience` derived from the parent |
| `forward` | `POST /api/messages/:id/forward` | `message_id`, `channel`; `body` is `""` |
| `boss_reply` | `POST /api/boss/inbox/:id/reply` (an agent acting as boss) | `message_id` |

A signer learns a peer recipient from `POST /api/messages/resolve-target` (`{to, session_id}`),
the same resolution a send performs. The server compares the signed audience with its own
resolution, so a recipient that changed in between yields 401. Except where the table says
otherwise, the server compares `mode`, `timeout`, `file_url`, `options`, `metadata` and
`session_id` against `null`. Signed values are compared in the
server's normalized form: body and options are trimmed, `metadata` has its server-owned keys
removed, and `mode` defaults to `async`. Signers send the normalized values. Priority, channel
routing, title and `option_media` are delivery hints and are not signed. `file_url` is signed
as a URL; the attachment content is not signed.

### Server admission (`server/src/message-security/agent-message.ts`)

1. The server looks up the live key of the calling credential. If there is none, it rejects
   `signed_message` (400) and rejects an unsigned write when the agent has any live key (401).
   Otherwise the write stays bearer-only and gets `not_configured` provenance.
2. It verifies the header, the signature and the exact payload key set. It checks that
   `agent_id` matches the caller and that the content deep-equals the request, and it allows
   a clock window of 300 s.
3. Replays: send and reply rows store `idempotency_key = sig:<kid>:<message_id>`,
   so a replay returns the original row.
4. Provenance is written with `authentication.kind = "agent_signature"` and
   `signature = {scheme: "JWS-ES256", key_id, public_key, signed_message}`.
5. If the Worker is deployed before migration 0055, the server treats every agent as having
   no keys and sends keep working.

Forwarded rows and boss-agent replies are not stored with the agent signature: the signature
authorizes the write, and the row keeps an attribution its readers can check. A forward is a
server-composed copy and carries `system` provenance. A boss-agent reply keeps the boss `api`
attribution.

A signed message is immutable: a body edit (`PATCH /api/messages/:id` with `body`) returns 409
when the agent is required to sign or the row carries an agent signature, including after a boss
reset. The agent sends a new message instead. An editable signed row would need
replay and ordering state that every other metadata writer (delivery bookkeeping, reactions,
option resolution) could disturb. Status updates are unaffected. Agents that do not sign keep
editing unchanged.

Group broadcast (`POST /api/groups/:id/broadcast`) returns 409 for a signing agent. A recipient
cannot verify group membership, so a signed fan-out could not be verified on receipt. A signing
agent sends to each member instead (`hiboss send --to` or `--broadcast`), and each of those
messages is bound to its recipient. Agents that do not sign keep group broadcast unchanged.

### Verification on receipt

`cli/src/agent_provenance.rs` and `mcp/agent-provenance.ts` run on every message that is not a
boss reply, before inbox rendering, polling, SSE and hooks:

- A row with no provenance (written before this change) is labelled `agent`.
- `source: "agent"` with `not_configured` is labelled `agent/not_configured`. `source: "system"`
  is accepted as `not_applicable`. Any other source on an agent row is rejected.
- A signed row is accepted only if the key ID matches the public key, the ES256 signature
  verifies, `payload.agent_id` equals `provenance.actor.id` and, for agent-authored
  directions, the row's `agent_id`, and the body matches.
- The action must fit the row: `send` with no parent, `reply` with the same parent, and, for
  both, a direction and recipient (`target_agent_id`, `target_session_id`) equal to the
  signed audience. A row addressed to the boss must name no peer target. No other kind appears
  on a stored row.
- `content`, `summary`, `default_option` and `task_context` must equal the stored values, and
  `options` and `file_url` must match including absence, so a row cannot gain choices or a file.
  The row must have a parseable `created_at` (SQLite UTC or RFC 3339), and
  `|issued_at − created_at| ≤ 300 s` must hold.
- The verifier takes the public key from the row. It proves the row is consistent with a key,
  not that the key belongs to the agent; that rests on server admission, because no client pins
  keys. For the same reason, a row whose provenance was removed reads as a pre-attribution
  `agent` row. Display names are not signed; the MCP plugin passes `sender_id` with each message.
- A verified row is labelled `agent/verified`. Any failure rejects the message.

## Limitations

- iOS and macOS do not verify agent signatures, and no client pins agent keys, so the server
  remains the key directory for every reader.
- A boss reply signs the parent message ID, not the parent's content. A server that rewrites
  an `ask` after the boss saw it can attach the boss's answer to the new text.
- Enrollment is separate from device join; a boss does not see the key fingerprint at approval.
- Agent keys are software keys on disk.
- Attachment content, option media, questionnaires, panels, progress posts and Box items are
  not signed.

## Alternatives considered

- **HMAC with the bearer credential.** It adds nothing against a leaked credential and gives
  verifiers nothing public to check.
- **One key per agent identity, shared across devices.** It requires copying private keys
  between machines, and one device's loss would revoke them all.
- **Enforcement per credential.** Minting a fresh credential would bypass it.
- **Automatic enrollment on first send.** A credential copied to a second machine would break
  there without warning. Enrollment is an explicit step.
