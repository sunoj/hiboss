# Push relay for self-hosted servers (v1)

The App Store build `ai.hiboss.app` can only be pushed with the APNs key of its bundle. A
self-hosted HiBoss server has no such key, so without help its boss never receives a push. The
push relay lets any HiBoss server ask a relay holding that key to push to an app install that
opted in, without the relay or Apple seeing message content.

This document is the contract for all three components: the relay (`relay/`), the server
(`server/`) and the iOS app (`ios/`).

## Parties

- **App**: the iOS app install and its Notification Service Extension (NSE).
- **Server**: the boss's self-hosted HiBoss Worker. The relay does not trust it.
- **Relay**: `relay/`, a separate Cloudflare Worker with its own D1 database, served at
  `https://push.hiboss.org`. It holds the APNs key for `ai.hiboss.app` as a Worker secret and knows
  nothing about bosses, agents or messages.

## Capabilities and keys

- `handle`: 32 CSPRNG bytes, base64url, minted by the relay at registration. It is the capability
  to push to one install. The relay stores only its SHA-256. The App gives it to its Server.
- `deviceSecret`: 32 CSPRNG bytes minted by the relay at registration and returned once to the
  App. The relay stores only its SHA-256. It authorises token update and deletion and never
  leaves the App.
- `pushKey`: a 32-byte AES-256-GCM key generated on the device and stored in the app-group
  keychain. The App gives it to the Server over the Server's TLS and boss authentication. It is
  never sent to the relay.

## Relay API

All requests and responses are JSON over HTTPS; a plain HTTP request is answered with 403.
Request bodies larger than 8,192 characters, malformed JSON, non-object bodies, wrong types and
unknown fields are answered with 400 `{"error":"invalid_request"}`.

| Request | Success | Other responses |
|---|---|---|
| `POST /v1/registrations` `{ apnsToken, environment }` | 201 `{ handle, deviceSecret }` | 400, 429 |
| `PUT /v1/registrations/self` `{ apnsToken, environment }` | 204 | 400, 410, 429 |
| `DELETE /v1/registrations/self` | 204 | 429 |
| `POST /v1/push` `{ handle, kind, ciphertext, collapseId? }` | 202 | 400, 410, 429, 502, 503 |

- `apnsToken` is 64–200 hexadecimal characters (stored lower-case); `environment` is `sandbox`
  or `production`. The APNs topic is fixed to `ai.hiboss.app`; clients cannot choose a bundle.
- `/self` routes authenticate with `Authorization: Bearer <deviceSecret>`. `PUT` rotates the APNs
  token and environment and keeps the handle. `DELETE` removes the registration and is
  idempotent: it answers 204 whether or not the secret matched anything.
- `POST /v1/push` has no other authentication: the handle is the capability.
  - `kind` is `decision`, `message` or `system`.
  - `ciphertext` is unpadded base64url, 28–2,048 bytes decoded (28 is the nonce plus the GCM tag).
  - `collapseId` is 1–64 characters of `[A-Za-z0-9_-]`.
- A handle or secret that is unknown, deleted, malformed or wrong gets exactly the same response:
  410 `{"error":"gone"}` for `PUT` and `POST /v1/push`, 204 for `DELETE`. There is no oracle that
  distinguishes them. On 410 from `/v1/push` the Server drops the handle.
- Stored digests are confirmed with a constant-time comparison after the indexed lookup.

### APNs request

For an accepted push the relay sends one APNs alert:

- `aps.alert` = `{ "title-loc-key": "HIBOSS_PUSH_TITLE", "loc-key": <by kind> }` with
  `HIBOSS_PUSH_DECISION`, `HIBOSS_PUSH_MESSAGE` or `HIBOSS_PUSH_SYSTEM`. No Server text reaches
  the alert. The app bundle defines these localization keys.
- `aps.sound` = `default`, `aps.mutable-content` = 1, `aps.thread-id` = `collapseId` when given.
- Custom key `e` = the ciphertext, unchanged.
- Headers: `apns-topic: ai.hiboss.app`, `apns-push-type: alert`, `apns-priority` 10 for
  `decision` and 5 otherwise, `apns-collapse-id` = `collapseId` when given.
- APNs 410, or a 400 with reason `BadDeviceToken`, deletes the registration and the relay answers
  410. Any other APNs failure answers 502 and keeps the registration. A relay without APNs
  secrets answers 503 and sends nothing.

## Ciphertext (Server to App, opaque to the relay and Apple)

```
ciphertext = nonce(12) || AES-256-GCM(pushKey, nonce, plaintext, aad = "hiboss-push-v1|" + kind)
```

The plaintext is the JSON the App already understands as direct APNs `userInfo` (message id,
title, body, options, category), trimmed to fit the 2,048-byte limit. The NSE decrypts it and
rewrites title, body and category; on any failure it leaves the generic alert. The kind is
authenticated through the AAD, so the relay cannot swap it.

## Abuse limits

Cloudflare has no spending cap, so every relay path has a ceiling. Counters are fixed UTC windows
in D1; a request increments its counters before the comparison, so rejected attempts count too.

| Limit | Ceiling | Over the ceiling |
|---|---|---|
| Pushes per handle | 60 per hour and 500 per day | 429, nothing sent |
| Pushes per source IP | 600 per hour | 429, nothing sent |
| Registration calls per source IP (`POST`, `PUT`, `DELETE`) | 30 per hour | 429 |
| Pushes across the relay | `GLOBAL_DAILY_PUSH_LIMIT` per day (default 50,000) | 503, nothing sent |

A push is checked in this order: body, source-IP limit, handle, per-handle limits, global
ceiling, APNs. The source IP comes from `CF-Connecting-IP` and is stored only as SHA-256 inside a
counter key. A daily cron trigger deletes registrations unused for 90 days (no delivered push and
no token rotation) and rate counters whose window has ended.

## Relay storage and configuration

- `registrations`: `handle_hash`, `secret_hash`, `apns_token`, `environment`, `created_at`,
  `last_used_at`. No content and no server identity.
- `rate_counters`: `key` (scope, window length, window number), `count`, `expires_at`.
- Secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY` (PKCS#8 PEM). Variable:
  `GLOBAL_DAILY_PUSH_LIMIT`. See `relay/wrangler.toml.example`.
- The relay writes no logs of handles, secrets, APNs tokens or ciphertext.

## Server behaviour

- The Server reports its push mode to the App in an authenticated capabilities/config response:
  `direct` when `APNS_*` secrets are configured (unchanged behaviour), `relay` when there is no
  APNs key and the relay is enabled, `none` otherwise.
- The relay is used only when no APNs key is configured. `PUSH_RELAY_URL` defaults to
  `https://push.hiboss.org`; `off` disables the relay. With the relay enabled, the relay sees the
  Server's IP address, the handles and the timing of pushes.
- Device registration accepts `{ relayHandle, pushKey, environment }` as an alternative to an APNs
  token, with the usual boss authentication. These are stored per boss device like tokens, and
  deleting the device deletes them.
- Every push path (notify, delivery adapters, probe, join notify) sends through one function that
  picks direct or relay. Quiet hours, priority rules and private-push preferences apply before the
  relay is called. A relay 410 removes the device row.
- The Server never logs handles, push keys or ciphertext.

## App behaviour

- An NSE target (bundle `ai.hiboss.app.NotificationService`) shares an app group and keychain
  access group with the app to read `pushKey`.
- When the Server reports `relay`, the App registers with the relay, keeps `deviceSecret` in the
  keychain and sends `{ relayHandle, pushKey, environment }` to the Server. On an APNs token change
  it calls `PUT /v1/registrations/self`. On sign-out it deletes at the relay and at the Server,
  then erases the secret and the key.
- When the Server reports `none`, Settings → Notifications states that push is unavailable for
  this server and why, and the App does not prompt for notification permission.
- Live Activity push updates are direct-only in v1 because an NSE cannot decrypt them. With the
  relay, Live Activities update while the app runs; Settings help states this.

## Invariants

- The relay stores no content, no server identity beyond rate-limit counters, and only hashes of
  handle and deviceSecret. The APNs key exists only as a Worker secret.
- No path lets a Server push to an install that did not register with it.
- Tests cover: every relay API rule, each limit, the global ceiling, 410 cleanup, the purge and the
  no-oracle property (`relay/test/`); server mode selection, an encryption round-trip decrypted
  with WebCrypto, and 410 handling; an iOS unit test for NSE decryption (valid, wrong key, wrong
  AAD, truncated) and a test for the `none` notice.
