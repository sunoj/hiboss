# Boss key pinning

Agents verify every boss message against boss public keys they have pinned locally, never
against a key the server sends with the message. Extends `docs/message-signing.md`.

## Why

Today a boss reply is signed with a device key (JWS-ES256), but the CLI and the MCP plugin read
the public key from the message they are verifying (`cli/src/message_security.rs`,
`mcp/message-security.ts`). A server that rewrites a message can also rewrite its key, so a
malicious or compromised server can forge a signed approval. Agents also accept unsigned
`api/not_configured` boss messages, and several boss writes are never signed, so a forged message
can simply drop its signature.

With Discord and Telegram removed, every boss message comes from a HiBoss client (iOS, macOS,
web console). Every one of them can sign, so a pinned agent can require a signature.

## Threat model

Defends against, for an agent that has pinned the boss's keys:

1. A server, database or Worker that forges or alters a boss message, including its signature,
   its key, or by dropping the signature.
2. A leaked Boss Token: a token without the device's private key cannot sign.
3. A new device added by someone who holds only server access: its key is not trusted until an
   already trusted device endorses it.

Does not defend against:

- An attacker with the boss's unlocked device (the same as yobiru's passkeys).
- An attacker who controls the agent's machine: they can edit the pin file.
- The first pin when the boss skips the fingerprint check (trust on first use).

## Keys and statements

Every boss client holds one non-exportable P-256 key:

| Client | Key | Created |
|---|---|---|
| iOS | Secure Enclave | at pairing or sign-in (also for a pasted Boss Token) |
| macOS | Secure Enclave | at pairing or Sign in with iPhone |
| Web console | WebCrypto, `extractable: false`, kept in IndexedDB | at sign-in |

The web console's code is served by the server this design defends against, so a web key signs
whatever that code asks it to. Web keys are a lower class: an agent shows a web-signed message as
the boss's words labelled "web console", but a web signature never satisfies an approval (an
`ask` answer that authorizes an action). Approvals need an iOS or macOS key.

A key is trusted by an agent when it is pinned directly, or when a trusted key endorsed it.
The boss signs two kinds of key statement, both JWS-ES256 with `typ: hiboss-key+jws`:

- **Endorsement** `{purpose: "hiboss.key-endorsement", boss_id, key_id, public_key, client_kind,
  label, issued_at}`, signed by a trusted key. A new device asks an existing device to approve it;
  the existing device shows the new key's label and fingerprint and signs on the boss's tap.
- **Revocation** `{purpose: "hiboss.key-revocation", boss_id, key_id, issued_at}`, signed by any
  trusted key, including the revoked key itself. A revoked key's later signatures fail; a
  signature it made before `issued_at` still verifies (history stays readable).

The server stores statements in `boss_key_statements` and returns them verbatim; it cannot create
one. `GET /api/agents/me/boss-keys` (agent auth, limited to bosses with access to the agent)
returns each boss's keys with their statements.

The fingerprint is the agent-key format: the first 16 characters of the key id, `xxxx-xxxx-xxxx-xxxx`.

## Pinning on the agent

The pin file sits beside the config, like `signing/`, because `config.json` rejects unknown fields:
`<config dir>/boss-keys/<boss_id>.json` = `{version, boss_id, keys: [{key_id, public_key, label,
client_kind, via: setup | manual | endorsed, pinned_at}], revoked: [{key_id, issued_at}]}`.

- **Invite**: `hiboss device invite` on a machine that already has pins puts their key ids in
  the invite string, which travels outside HiBoss (pasted by the boss). `hiboss setup --invite`
  pins exactly those keys from the boss-keys endpoint and refuses keys the invite does not name.
  No trust on first use.
- **First machine** (no inviting machine has pins yet): setup pins the boss's iOS and macOS keys
  as `via: first_use` and prints their fingerprints; the boss compares them with Settings ›
  Signing keys in the app. A HiBoss notice is not a check, since it travels through the server.
- **Manual**: `hiboss boss trust <key text>` pins a key copied from the app (`hiboss-boss-key:` +
  base64url of `{boss_id, public_key, label}`). `hiboss boss keys` lists the pins.
- **Endorsed**: on each read the CLI and MCP refresh statements and pin keys whose endorsement
  verifies against an already pinned key; revocations are applied the same way.

## Verification rules

A boss message is shown to the model as the boss's words only when:

1. its `signed_message` verifies with a pinned, unrevoked key (the message's own `public_key`
   is ignored except to find the key id), and
2. the payload binds what the message claims: boss, parent, body, `answers`, and for a reply the
   agent and session of the parent.

The rule is per agent, not per boss: once the agent has any pin, every boss message must verify,
and a message attributed to a boss with no pin is blocked until `hiboss boss trust`. Otherwise the
server could attribute a forgery to a boss id the agent never pinned. A blocked message reaches
the agent as "unverified message from <boss>, not shown"; an `ask` waiting on it keeps waiting and
reports the blocked reply instead of returning it.

Boss-agents (an AI acting as boss) sign with their agent key, which comes from the server
directory. Their messages are labelled "boss-agent" and never satisfy an approval unless the
agent pinned that boss-agent's key with `hiboss boss trust`.

A server-written timeout default is accepted only when it equals the default this agent sent
with the ask; it is labelled `system/default` and is never an approval.

**Replay and backdating.** Commands, notes and broadcasts have no parent, so the agent keeps a
ledger of signed ids it has seen (`boss-keys/seen.jsonl`, pruned after 30 days) and refuses a
repeat. A message must be first seen within 10 minutes of its `issued_at`. After a key is revoked,
only ids already in the ledger still count, so a revoked key cannot backdate new signatures.

Every path that delivers boss text to an agent verifies first: inbox, get, poll, ask wait,
`watch`, `bot`, the `daemon` spool and the session hook, boss notes, and questionnaire answers.

## What the clients sign

Everything a boss sends to an agent: replies, option and form answers, session commands, group
broadcasts, session notes, reactions, join approvals, and questionnaire submissions. Each payload
names its action (`reply`, `command`, `broadcast`, `note`, `reaction`, `join-approval`), and a reply
also binds `agent_id` and `session_id`.

## Rollout

1. Server: `boss_key_statements`, the key endpoint, signature checks on every boss write route.
2. Clients sign every write; iOS and macOS show Settings › Signing keys with fingerprints and the
   endorsement prompt; the web console gets its key.
3. Existing bosses: no bulk endorsement of a server-supplied list. A device endorses another only
   with the new key's fingerprint shown on both devices.
4. CLI and MCP: pin from the invite or at first setup, `boss trust`/`boss keys`, verify against
   pins. Existing installs pin their boss's iOS/macOS keys as `first_use` on the next run and print
   the fingerprints.
5. Enforcement (block unsigned) ships only after every client signs every write, so a pinned
   agent is never locked out of its own boss.

## Labels

The session hook labels a message `[boss]` by its direction. A group broadcast from an agent is
stored as `boss_to_agent` with an agent actor, so it reads as the boss. The label comes from the
verified actor kind instead: `[boss]` only for a boss actor whose signature verifies.

## Separate fixes that do not wait for pinning

Landed in `fix(cli,mcp): verify spooled boss messages and bind form answers to the signature`:
the `daemon` spool is verified before the hook injects it, and a form reply's stored `answers`
must equal the signed ones in the CLI and MCP.
