# Agent Message Signing — Design Draft

Status: draft for review. Companion to `docs/message-signing.md`, which covers the
boss → agent direction.

## Goal

An agent's message carries an ES256 signature from a key that never leaves the agent's
machine. Boss clients, boss-agents and peer agents verify that signature before they
show the body or act on it. Today an agent's identity is only a bearer credential, so
anyone who holds that string, or the server itself, can author an "agent" message.

Signing proves who wrote a message and that it was not altered. It does not prove that the
content is true or safe. Prompt-injection handling still applies to every body.

## Current state

| Fact | Where |
| --- | --- |
| Agent credential is `hb_` + 32 random bytes; the server stores only its SHA-256 | `server/src/agent-keys/repository.ts` |
| One agent identity (`api_keys`) can hold several credentials (`agent_keys`), one per device or rotation | migration `0045_agent_keys.sql` |
| Credentials sit in plain text in `config.json` profiles, or in `HIBOSS_KEY` for the MCP plugin | `cli/src/config.rs`, `mcp/config.ts` |
| `agent_to_boss` and `agent_to_agent` rows carry no provenance; only group fan-out uses `agentApiMetadata` | `server/src/routes/message-send.ts`, `groups.ts` |
| Client-supplied `metadata` is stored unfiltered; an agent can write its own `provenance`/`source` keys | `normalizeMetadata` in `message-helpers.ts` |
| CLI and MCP verifiers label every non-`boss_to_agent` message `agent` without checking it | `cli/src/message_security.rs`, `mcp/message-security.ts` |
| A boss's signed reply covers the parent message **id**, not the parent's content | `SignedBossPayload.action` |
| Agents may edit the body of their `agent_to_boss` messages | `PATCH /api/messages/:id` |

## Threat model

What this design defends against:

1. **A leaked bearer credential.** The credential goes out on every HTTP request and sits in
   env vars, MCP configs and shell history. A signing key never goes out over the network.
   Once a credential has a signing key bound to it, an attacker who holds only the bearer string cannot send
   a message as that agent.
2. **Tampering after admission.** This covers database edits, buggy migrations, and a compromised
   Worker that rewrites a stored question. Boss clients that pin agent keys (§ Pinning) detect it.
3. **Approve-a-different-question.** A server rewrites an `ask` after the boss has seen it,
   and then attaches the boss's signed "Approve" to the new text. Bound replies
   (§ Reply binding) close this gap.
4. **Peer impersonation into model context.** A forged `agent_to_agent` message is a
   prompt-injection vector. The receiving agent rejects an invalid signature before the
   body reaches the model.

What this design does not defend against:

- **Filesystem compromise of the agent's machine.** With software keys (phase 1), whoever can read
  `config.json` can usually read the key file too. Hardware-backed keys (phase 3) narrow this.
- **A malicious server, for any client that does not pin keys.** The server remains the key
  directory, exactly as it is for boss keys today.
- **Discord and Telegram readers.** These channels cannot verify a signature. They display server-attested text.

## Design

### 1. Key and binding

- Algorithm: **ES256 (P-256)**. This reuses the existing verifiers in the server (Web Crypto),
  the CLI (`ring`), MCP (Web Crypto) and HibossKit (CryptoKit). Ed25519 was considered and
  rejected because it would need a second verifier stack on four clients.
- One signing key per **credential** (`agent_keys.id`), not per agent identity. This mirrors
  `boss_signing_keys.boss_token_id`. Revoking a credential retires its key.
- Key ID = `base64url(SHA-256(uncompressed SEC1 public key))`, the same derivation the boss side uses.
- Storage (phase 1): a PKCS#8 file at `<config dir>/hiboss/signing/<agent_key_id>.p8` with mode
  `0600`. It lives outside `config.json`, so a config dump or paste does not leak it. `ring` and
  Bun Web Crypto both import PKCS#8. MCP finds the file through `HIBOSS_SIGNING_KEY`, or by
  credential ID when it shares the CLI config.

New table, in a new migration:

```sql
CREATE TABLE agent_signing_keys (
  id TEXT PRIMARY KEY,                -- key ID
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  agent_key_id TEXT NOT NULL UNIQUE REFERENCES agent_keys(id),
  algorithm TEXT NOT NULL CHECK (algorithm = 'ES256'),
  public_key TEXT NOT NULL,
  enrolled_via TEXT NOT NULL CHECK (enrolled_via IN ('join', 'rotation', 'enroll', 'recovery')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  revoked_at TEXT
);
```

### 2. Registration

Every registration carries a proof that is domain-separated from the boss proofs:

```text
ES256("hiboss-agent-key-v1\n" + <subject> + "\n" + agent_id_or_profile + "\n" + base64url(public_key))
```

| Path | Subject | Trust |
| --- | --- | --- |
| **Join** (`POST /api/join`): each profile entry carries `signing` | join request ID | The boss approves the join on a native client, and the sheet shows each key's fingerprint next to the existing verification code. The server binds the key to the minted credential in the same batch. This is the strongest path and the default for new devices. |
| **Rotation** (`hiboss key rotate`): the new credential's key | new credential ID | The request is also signed by the **current** signing key, so trust carries forward without asking the boss again. |
| **Enroll** (existing unsigned credential) | credential ID | Bearer authentication plus proof. This is trust-on-first-use: the boss gets a notification and an audit row. Allowed only while the credential has no key. |
| **Recovery** (lost key) | credential ID | Same request as Enroll, but it waits for boss approval, like a join. Replacement never happens silently. |

Once a credential has a bound key, **every message write made with that credential must be
signed**. An unsigned request gets `401 signed message required`, so the request cannot
downgrade itself. This is the same rule that boss tokens follow.

### 3. Signed message format

Compact JWS, the same shape as boss messages, with a distinct type and purpose so neither
can be replayed as the other:

```json
{ "alg": "ES256", "kid": "<key-id>", "typ": "hiboss-agent-message+jws" }
```

```json
{
  "version": 1,
  "purpose": "hiboss.agent-message",
  "message_id": "<client uuid>",
  "issued_at": 1791763200,
  "agent_id": "<agent id>",
  "session_id": "<session id> | null",
  "action": { "kind": "send" } ,
  "audience": { "kind": "boss" },
  "body": "Deploy finished",
  "mode": "async",
  "options": null,
  "default_option": null,
  "attachments": []
}
```

- `action.kind`: `send`, `ask`, `reply` (with `message_id` of the parent), or `edit`
  (with `message_id` of the message being replaced).
- `audience`: `{kind: "boss"}` or `{kind: "agent", selector: "<--to value>"}`. The
  selector is signed as the sender typed it. Server-side resolution is recorded unsigned
  (see open question 3). `--broadcast` already sends one request per peer, so each
  message gets its own signature.
- `options`, `default_option` and `timeout` are signed because they shape what the boss can
  choose and what is chosen if the boss does nothing.
- `attachments`: `[{ "url": "...", "sha256": "<base64url>" }]` for `file_url` and option media.
  The CLI already holds the bytes when it uploads them. Clients that download a file check the digest.
- Priority, channel routing and title are delivery hints and stay unsigned.

### 4. Server admission

`authenticateAgentMessage` sits next to `authenticateBossReply` in `server/src/message-security/`:

1. It looks up a key by `c.agentKeyId`. With no key, the message stays bearer-only and
   gets provenance `api/not_configured`. With a key, the message must carry `signed_message`.
2. It verifies the header, signature and payload shape, checks `agent_id` against the caller,
   checks that body, mode, options, default, attachments and parent match the request, and
   enforces a 300-second freshness window.
3. Idempotency key: `sig:<kid>:<message_id>`. A replay returns the stored row.
4. It writes server-owned provenance and **strips every client-supplied `provenance`, `source`,
   `boss_id`, `boss_name` and `auto_default` key** from `metadata` before merging. This
   stripping fixes an existing spoofing gap and ships first, independent of signing.

Agent provenance:

```json
{
  "version": 1,
  "source": "agent",
  "actor": { "kind": "agent", "id": "...", "name": "..." },
  "authentication": { "kind": "agent_signature", "credential_id": "<agent_key_id>" },
  "signature": {
    "scheme": "JWS-ES256", "key_id": "...", "public_key": "...", "signed_message": "..."
  }
}
```

A bearer-only message uses the same envelope with `authentication.kind = "api_key"` and
`signature.status = "not_configured"`.

### 5. Verification on receipt

| Reader | Behavior |
| --- | --- |
| Peer agent (CLI, MCP) on `agent_to_agent` | Verifies the signature before inbox rendering, SSE, poll or hooks, the same boundary as for boss messages. Labels: `agent/verified`, `agent/not_configured`. Invalid messages are rejected. |
| Boss-agent (`hiboss boss inbox`, bot handlers) | Same as a peer agent. A boss-agent never acts on an invalid message. |
| iOS / macOS (HibossKit) | CryptoKit verification plus the pinning described below. The body shows with a verified mark, an unsigned mark, or a warning that replaces the decision buttons when the signature is invalid or the key is unpinned. |
| Discord / Telegram | No verification. A link to the native client is the only way to check. |

Clients also check that `|issued_at − created_at| ≤ 300 s`, so a stored message cannot be
re-dated without detection.

### 6. Pinning (boss clients)

The server is the key directory, so pinning is what turns signing into protection against a
compromised server, at least on the boss's devices:

- A key is pinned when the boss approves the join that carried it. The fingerprint was on
  screen at that moment.
- Keys learned any other way, such as enroll or a different boss device, are pinned on first
  use. The client shows a "new key for <agent> on <device>" notice.
- A rotation signed by a pinned key extends the pin to the new key automatically.
- A key the boss never saw that replaces a pinned one shows a blocking warning on that agent's
  decisions until the boss accepts it.
- Pins live in the Keychain and sync through iCloud Keychain, so a second boss device inherits them.

Peer agents do not pin in phase 1. They trust the server's directory, as the boss side does today.

### 7. Reply binding

The boss reply payload gains `action.parent_digest = base64url(SHA-256(parent.signed_message))`
whenever the parent is signed. That makes it boss reply `version: 2`, and version 1 stays valid
for unsigned parents. The asking agent still holds its own JWS while `ask` waits, and it checks
the digest. An approval then authorizes exactly the text the agent sent and nothing the server
substituted.

### 8. Edits

An edit is a new JWS with `action: {kind: "edit", message_id}`. The row keeps the latest
signature in `provenance`, and the replaced signatures move to
`metadata.provenance_history[]` so a client can show that the message was edited. An edit
may not change options or the default after the boss has seen the message. The server
already restricts body edits to `agent_to_boss`.

## Rollout

| Phase | Ships | Gate |
| --- | --- | --- |
| 0 | Strip client-supplied provenance keys from agent metadata | E2E test: a forged `metadata.provenance` does not survive |
| 1 | Table, join/enroll/rotate registration, CLI and MCP signing, server admission, CLI and MCP verification of `agent_to_agent` | Server E2E plus CLI tests: signed send, downgrade rejected, replay deduplicated, peer forgery rejected |
| 2 | HibossKit verification and pinning on iOS and macOS, fingerprint in the join sheet, boss reply v2 `parent_digest` | iOS T3 run, macOS `swift build` and tests |
| 3 | Hardware-backed agent keys on macOS (CryptoKit Secure Enclave key blob through a small helper); signing for questionnaires and box items | Separate design |

Older CLI binaries keep working against credentials that have no bound key. When a newer
CLI enrolls a key on a shared config, older binaries on that machine get the 401 with an
upgrade hint. That outcome is intended, because allowing a fallback would bring the downgrade back.

## Alternatives considered

- **HMAC with the bearer credential.** This adds nothing against a leaked credential and gives
  verifiers nothing public to check. Rejected.
- **One key per agent identity, shared across devices.** This requires copying private keys
  between machines, and one device's loss would revoke all of them. Rejected in favor of
  per-credential keys.
- **Server-side signing.** The server already authenticates the request, so a server
  signature adds no new evidence. Rejected.

## Open questions for review

1. **Enroll as trust-on-first-use with a notification, or require boss approval for every
   existing credential?** The draft uses trust-on-first-use, because migrating many agents
   through approval taps is costly and the exposure lasts only while unenrolled credentials exist.
2. **Should an invalid signature on a boss client hide the body or show it with a warning?**
   The draft shows it with a warning and disables the decision buttons.
3. **Should the sender pre-resolve `--to` and sign the resolved session ID?** This needs a
   resolve-only endpoint. It would stop a server from replaying a peer message to a different
   recipient. The draft signs only the selector.
4. **Should panels, progress posts and questionnaires join phase 1?** Questionnaire answers
   can gate actions, so they are the strongest candidate.
