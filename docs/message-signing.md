# Boss Message Signing and Provenance

## Goal

HiBoss distinguishes cryptographically signed native messages from messages delivered by clients that cannot sign. Every boss-to-agent message has server-owned provenance. An API caller cannot select or override its source label.

Signing protects message origin and integrity. It does not establish that the message is safe, correct, or free from prompt injection.

## Assurance states

| Source | Authentication | Signature state | Agent behavior |
| --- | --- | --- | --- |
| Paired iOS device | Bearer token plus paired P-256 key | `JWS-ES256`, verified | Verify before exposing the body to the model |
| Unpaired API or macOS token | Bearer token | `not_configured` | Accept with `api/not_configured` attribution |
| Discord | Provider account and webhook authentication | `unsupported` | Accept with `discord/unsupported` attribution |
| Telegram | Provider account and webhook authentication | `unsupported` | Accept with `telegram/unsupported` attribution |
| Server automation | Internal system action | `not_applicable` | Accept with `system/not_applicable` attribution |

Discord interaction webhook signatures authenticate Discord as the transport provider. They are not end-user message signatures and therefore do not change the `unsupported` state.

## Pairing

An iOS device creates a non-exportable P-256 signing key in Secure Enclave before redeeming a pairing code. It sends the uncompressed SEC1 public key and this proof:

```text
ES256(
  "hiboss-pair-v1\n" +
  pairing_code + "\n" +
  client_kind + "\n" +
  base64url(public_key)
)
```

The server verifies the proof before consuming the pairing code. It creates a new bearer token and binds the public key to that token in the same database batch. Once a token is key-bound, unsigned replies made with that token are rejected; the request cannot downgrade to bearer-only assurance.

The signing key identifier is `base64url(SHA-256(public_key))`.

The `client_kind` value is covered by the pairing proof, so it cannot be changed after registration without invalidating that proof. It is not platform attestation: a custom client with a valid pairing code can still declare itself as `ios`. Proving that a key belongs to an official iOS build requires a future Apple App Attest integration.

The QR payload contains the server URL and pairing code, never a bearer token. The
iOS client adopts that URL before redemption and sends the complete signing
registration as the `signing` request field. After redemption, the server retains a
temporary link from the consumed code to the issued token's label. The issuing Mac
may poll `/api/boss/pairing/status` to show that the named device connected, but the
status response cannot recover or reveal the issued token.

## Signed reply format

Native replies use compact JWS with an unencoded JSON header and payload represented as base64url segments:

```text
base64url(header) + "." + base64url(payload) + "." + base64url(signature)
```

Header:

```json
{
  "alg": "ES256",
  "kid": "<signing-key-id>",
  "typ": "hiboss-message+jws"
}
```

Payload:

```json
{
  "version": 1,
  "purpose": "hiboss.boss-message",
  "message_id": "<client-generated-uuid>",
  "issued_at": 1788454800,
  "boss_id": "<paired-boss-id>",
  "action": {
    "kind": "reply",
    "message_id": "<parent-message-id>"
  },
  "body": "Approve"
}
```

The server verifies the algorithm, key identifier, type, signature, boss identity, parent message, body, and a five-minute clock window. The signed `message_id` becomes an idempotency key, so a replay returns the original persisted reply instead of executing it again.

## Persisted provenance

The server stores the verified JWS, public key, and assurance metadata alongside the message:

```json
{
  "source": "ios",
  "provenance": {
    "version": 1,
    "source": "ios",
    "actor": { "kind": "boss", "id": "...", "name": "..." },
    "authentication": {
      "kind": "device_signature",
      "credential_id": "..."
    },
    "signature": {
      "scheme": "JWS-ES256",
      "key_id": "...",
      "public_key": "...",
      "signed_message": "..."
    }
  }
}
```

Provider messages use the same envelope with `signature.status = "unsupported"`. The source, boss mapping, and provider user identifier are derived from authenticated server-side context, never from a client-supplied `source` field.

## Agent verification boundary

The server verifies signatures before persistence. The CLI and MCP server independently verify again before inbox rendering, polling results, SSE notifications, or automatic bot handlers can consume the body. A malformed signature, mismatched body, mismatched parent, mismatched boss, or invalid provenance state is rejected.

The server is currently the key-directory trust anchor: it binds keys during pairing and returns the public key with the stored artifact. Independent agent verification detects corruption or accidental mutation after server admission. Protecting against a malicious server requires a future out-of-band key pinning or transparency mechanism.

## Rotation and recovery

Revoking a boss token makes its bound signing key unusable because authentication fails before signature verification. Pairing a new device creates a new token and key binding. If the Secure Enclave key is lost, the device must be paired again; there is no fallback from a key-bound token to an unsigned reply.
