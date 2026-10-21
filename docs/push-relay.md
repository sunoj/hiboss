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
`POST` and `PUT` requests must carry `Content-Length` of at most 8,192 bytes; a missing or larger
value is answered with 400 before the body is read, and the limit is also enforced while reading.
Malformed JSON, non-object bodies, wrong types and unknown fields are answered with 400
`{"error":"invalid_request"}`.

| Request | Success | Other responses |
|---|---|---|
| `POST /v1/registrations` `{ apnsToken, environment }` | 201 `{ handle, deviceSecret }` | 400, 429, 503 |
| `PUT /v1/registrations/self` `{ apnsToken, environment }` | 204 | 400, 410, 429 |
| `DELETE /v1/registrations/self` | 204 | 429 |
| `POST /v1/push` `{ handle, kind, ciphertext, collapseId?, priority, interruption, sound }` | 202 | 400, 410, 429, 502, 503 |

- `apnsToken` is 64–200 hexadecimal characters (stored lower-case); `environment` is `sandbox`
  or `production`. The APNs topic is fixed to `ai.hiboss.app`; clients cannot choose a bundle.
- `/self` routes authenticate with `Authorization: Bearer <deviceSecret>`. `PUT` rotates the APNs
  token and environment and keeps the handle. `DELETE` removes the registration and is
  idempotent: it answers 204 whether or not the secret matched anything.
- `POST /v1/push` has no other authentication: the handle is the capability.
  - `kind` is `decision`, `message` or `system`.
  - `ciphertext` is unpadded base64url, 28–2,048 bytes decoded (28 is the nonce plus the GCM tag).
  - `collapseId` is 1–64 characters of `[A-Za-z0-9_-]`.
  - The delivery level is required: `priority` is the number `5` or `10`, `interruption` is
    `passive`, `active` or `time-sensitive`, and `sound` is a boolean. A missing field or any
    other value is answered with 400. These fields are urgency metadata, not content; the Server
    derives them from the payload it would send directly.
- A handle or secret that is unknown, deleted, malformed or wrong gets exactly the same response:
  410 `{"error":"gone"}` for `PUT` and `POST /v1/push`, 204 for `DELETE`. There is no oracle that
  distinguishes them. On 410 from `/v1/push` the Server drops the handle.
- Stored digests are confirmed with a constant-time comparison after the indexed lookup.

### APNs request

For an accepted push the relay sends one APNs alert:

- `aps.alert` = `{ "title-loc-key": "HIBOSS_PUSH_TITLE", "loc-key": <by kind> }` with
  `HIBOSS_PUSH_DECISION`, `HIBOSS_PUSH_MESSAGE` or `HIBOSS_PUSH_SYSTEM`. No Server text reaches
  the alert. The app bundle defines these localization keys.
- `aps.interruption-level` = `interruption`; `aps.sound` = `default` when `sound` is true and
  absent when it is false; `aps.mutable-content` = 1; `aps.thread-id` = `collapseId` when given.
- Custom key `e` = the ciphertext, unchanged.
- Headers: `apns-topic: ai.hiboss.app`, `apns-push-type: alert`, `apns-priority` = `priority`,
  `apns-collapse-id` = `collapseId` when given. Kind selects only the loc-key.
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

Cloudflare has no spending cap, so every relay path has a ceiling. Request rates are limited per
source by the Workers Rate Limiting binding, outside D1, before any D1 access. Delivery is limited
by fixed UTC-window counters in D1 that only a valid handle or a successful registration can write.

| Limit | Ceiling | Over the ceiling |
|---|---|---|
| Push requests per source (`PUSH_RATE_LIMITER`) | 600 per minute | 429, no D1 access |
| Registration calls per source (`REGISTRATION_RATE_LIMITER`; `POST`, `PUT`, `DELETE`) | 30 per minute | 429, no D1 access |
| Pushes per handle | 60 per hour and 500 per day | 429, nothing sent |
| Pushes APNs accepted, across the relay | `GLOBAL_DAILY_PUSH_LIMIT` per UTC day (default 200,000) | 503, nothing sent |
| New registrations, across the relay | 5,000 per UTC hour | 503, nothing stored |

- **Source.** The `CF-Worker` header when present (the calling Worker's zone, because Worker
  subrequests share Cloudflare egress addresses), else the IPv6 /64 prefix of `CF-Connecting-IP`,
  else the full IPv4 address. The per-source limits bound request cost, not delivery. There is no
  per-IP push limit: a shared egress address would let one caller block every Worker-hosted
  Server. The binding's counters are per Cloudflare location and approximate.
- **Order of a push.** `Content-Length`, source rate, body, handle, per-handle limits, global
  ceiling, APNs. An unknown or invalid handle writes nothing to D1.
- **Per-handle counters** increment before the comparison, so rejected attempts count too.
- **Global push ceiling** is read before sending and incremented only after APNs answers 200. A
  rejected token (APNs 410, or 400 `BadDeviceToken`) is not counted and deletes the registration;
  other APNs failures are not counted either. Concurrent pushes can overshoot it slightly.
- **Global registration ceiling** is read before inserting and incremented only by a stored
  registration. Token rotation and deletion do not count.
- D1 holds no IP address or IP-derived value.
- A daily cron trigger deletes registrations unused for 90 days (no delivered push and no token
  rotation) and rate counters whose window has ended.

### Operator steps for the deployed host

- Add a zone-level Cloudflare rate-limiting rule on the relay hostname as the outer bound on
  request volume, for example 1,200 requests per minute per IP on `/v1/*`, answering 429. Match
  only requests without a `cf-worker` header
  (`not any(http.request.headers.names[*] == "cf-worker")`), so the shared egress address of
  Worker-hosted Servers is not one bucket. The rule runs before the Worker, so blocked requests
  cost no Worker invocation.
- After the first deploy, run the source probe. Deploy a throwaway echo Worker on the relay's
  zone (for example `probe.hiboss.org`) that returns the `CF-Connecting-IP` and `CF-Worker`
  request headers it received; the relay itself logs nothing. Call it with `fetch` from a second
  throwaway Worker on a different zone, as a self-hosted Server would. Expected: `CF-Worker` holds
  the calling zone and `CF-Connecting-IP` is a shared Cloudflare address. If `CF-Worker` is
  absent, Worker-hosted Servers share one source bucket; raise `PUSH_RATE_LIMITER` before relying
  on it. Delete both probe Workers afterwards.

## Relay storage and configuration

- `registrations`: `handle_hash`, `secret_hash`, `apns_token`, `environment`, `created_at`,
  `last_used_at`. No content and no server identity.
- `rate_counters`: `key` (scope, window length, window number), `count`, `expires_at`. Scopes are
  `handle:<handle_hash>`, `global` (accepted pushes) and `global:reg` (new registrations).
- Secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY` (PKCS#8 PEM). Variable:
  `GLOBAL_DAILY_PUSH_LIMIT`. Rate Limiting bindings: `PUSH_RATE_LIMITER`,
  `REGISTRATION_RATE_LIMITER` (`[[ratelimits]]`). See `relay/wrangler.toml.example`.
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
