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

- `handle`: `base64url(id || HMAC-SHA256(HANDLE_KEY, id)[0..16])`, where `id` is 16 CSPRNG bytes,
  minted by the relay at registration (43 characters). It is the capability to push to one
  install. The relay checks the MAC before any D1 access and stores only the handle's SHA-256.
  `HANDLE_KEY` is a Worker secret; rotating it invalidates every handle and must be followed by
  deleting every registration (see [Operator steps](#operator-steps-for-the-deployed-host)). The
  App gives the handle to its Server.
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
| `POST /v1/registrations` `{ apnsToken, environment }` | 201 `{ handle, deviceSecret }` | 400, 429, 503 (also when `HANDLE_KEY` is not set) |
| `PUT /v1/registrations/self` `{ apnsToken, environment }` | 204 | 400, 410, 429, 503 |
| `DELETE /v1/registrations/self` | 204 | 429 |
| `POST /v1/push` `{ handle, kind, ciphertext, collapseId?, priority, interruption, sound }` for kind `decision`, `message` or `system`; `{ handle, kind, ciphertext, priority }` for kind `resolved` | 202 | 400, 410, 429, 502, 503 (APNs key or `HANDLE_KEY` not configured) |

- `apnsToken` is 64–200 hexadecimal characters (stored lower-case); `environment` is `sandbox`
  or `production`. The APNs topic is fixed to `ai.hiboss.app`; clients cannot choose a bundle.
- A registration is stored only for a token APNs accepts for that topic. Before `POST` stores a
  row, and before `PUT` rotates to a token, the relay sends the token one background push in the
  requested environment (see [Token check](#token-check)). APNs 200 stores it. An APNs rejection
  (400 or 410) is answered with 400 `{"error":"invalid_token"}`; any other APNs status, a
  transport error, the 5-second timeout or missing APNs secrets with 503. Neither writes anything.
  `PUT` checks the secret first, so an unknown secret gets 410 without an APNs call.
- There is one registration per APNs token. `POST` with a token that already has a registration
  replaces it, and `PUT` to a token another registration holds deletes that registration: the
  old handle and secret then get 410, and the old Server drops the handle.
- `/self` routes authenticate with `Authorization: Bearer <deviceSecret>`. `PUT` rotates the APNs
  token and environment and keeps the handle. `DELETE` removes the registration and is
  idempotent: it answers 204 whether or not the secret matched anything.
- `POST /v1/push` has no other authentication: the handle is the capability.
  - `kind` is `decision`, `message`, `system` (alerts) or `resolved` (a background push that
    tells the App an ask closed).
  - `ciphertext` is unpadded base64url, 28–2,048 bytes decoded (28 is the nonce plus the GCM tag).
  - `collapseId` is 1–64 characters of `[A-Za-z0-9_-]`.
  - The delivery level is required: `priority` is the number `5` or `10`, `interruption` is
    `passive`, `active` or `time-sensitive`, and `sound` is a boolean. A missing field or any
    other value is answered with 400. These fields are urgency metadata, not content; the Server
    derives them from the payload it would send directly.
  - For `resolved`, `priority` must be `5`, and `interruption`, `sound` and `collapseId` must be
    absent; any other body is answered with 400.
- A handle or secret that is unknown, deleted, malformed, forged or wrong gets exactly the same response:
  410 `{"error":"gone"}` for `PUT` and `POST /v1/push`, 204 for `DELETE`. There is no oracle that
  distinguishes them. On 410 from `/v1/push` the Server drops the handle.
- Stored digests are confirmed with a constant-time comparison after the indexed lookup.

### Token check

For `POST /v1/registrations` and `PUT /v1/registrations/self` the relay sends one background push
to the token, which the device does not show:

- Headers: `apns-topic: ai.hiboss.app`, `apns-push-type: background`, `apns-priority: 5`.
- Body: `{"aps":{"content-available":1}}`.
- Host: `api.push.apple.com` for `production`, `api.sandbox.push.apple.com` for `sandbox`.

### APNs request

For an accepted `decision`, `message` or `system` push the relay sends one APNs alert:

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

For an accepted `resolved` push the relay sends one APNs background push, which shows nothing:

- Body: `{"aps":{"content-available":1},"e":"<ciphertext>"}`.
- Headers: `apns-topic: ai.hiboss.app`, `apns-push-type: background`, `apns-priority: 5`; no
  `apns-collapse-id`.
- The same 410, 502 and 503 rules apply.

## Ciphertext (Server to App, opaque to the relay and Apple)

```
ciphertext = nonce(12) || AES-256-GCM(pushKey, nonce, plaintext, aad = "hiboss-push-v1|" + kind)
```

The plaintext is the JSON the App already understands as direct APNs `userInfo` (message id,
title, body, options, category), trimmed to fit the 2,048-byte limit. The NSE decrypts it and
rewrites title, body and category; on any failure it leaves the generic alert. The kind is
authenticated through the AAD, so the relay cannot swap it.

For kind `resolved` the plaintext is only `{"id":"<message id>","status":"replied|expired"}`. The
App decrypts it in `didReceiveRemoteNotification`; a decryption failure does nothing.

## Abuse limits

Cloudflare has no spending cap, so every relay path is bounded. A shared ceiling is also a lever to
deny service to everyone, so the relay has none. Request rates are limited by Workers Rate
Limiting bindings, outside D1 and before any D1 access: per address and per APNs token for
registrations, per handle for pushes. A push handle carries a MAC, so a push request that reaches
D1 carries a handle the relay minted, possibly one whose registration has since been replaced. Delivery is limited per device by fixed UTC-window counters in D1. Registrations need no
ceiling: only tokens APNs accepts are stored, one row per token, so rows are bounded by real
installs.

| Limit | Ceiling | Over the ceiling |
|---|---|---|
| Push requests per handle (`HANDLE_RATE_LIMITER`), after the MAC check | 60 per minute | 429, no D1 access |
| `POST /v1/registrations` per address (`REGISTRATION_RATE_LIMITER`) | 5 per minute | 429, no D1 access |
| `POST /v1/registrations` per APNs token (`TOKEN_RATE_LIMITER`), before the token check | 2 per minute | 429, no D1 access, no APNs call |
| `PUT`/`DELETE /v1/registrations/self` per address (`SELF_RATE_LIMITER`) | 30 per minute | 429, no D1 access |
| Alert pushes per device (APNs token) | 60 per hour and 500 per day | 429, nothing sent, nothing written |
| `resolved` pushes per device (APNs token), a separate bucket | 60 per hour and 500 per day | 429, nothing sent, nothing written |

- **Address key.** The IPv6 /64 prefix or the full IPv4 address of `CF-Connecting-IP`, for
  `POST`, `PUT` and `DELETE` on `/v1/registrations`. `CF-Worker` is ignored.
- **Token key.** SHA-256 of the lower-cased APNs token, for `POST /v1/registrations` only. It
  bounds how fast one real token can mint handles, whatever addresses the caller holds.
- **Device key.** SHA-256 of the APNs token. Alerts and `resolved` pushes count in separate
  buckets, so resolutions never consume the alert budget and alerts never starve resolutions.
- **Handle key.** SHA-256 of the handle, applied only once the MAC has verified. A forged or
  garbled handle is answered 410 before the limiter and before D1.
- The rate-limit bindings bound request cost, not delivery. Their counters are per Cloudflare
  location and approximate.
- **Per device.** The counters are keyed on SHA-256 of the APNs token, not on the handle, so
  re-registering a token keeps its counts. One guarded upsert increments the hourly and daily
  counters only while both are under their limits; a push over either limit writes nothing.
- **Order of a push.** `Content-Length`, body, handle MAC, per-handle rate, handle lookup,
  per-device limits, APNs. A handle that fails its MAC causes no D1 access at all; an unknown
  genuine handle costs one D1 read and writes nothing.
- D1 holds no IP address or IP-derived value.
- A daily cron trigger deletes registrations unused for 30 days (no delivered push and no token
  rotation) and rate counters whose window has ended. A purged install registers again (see
  **Lost registration** below).

### Cost and availability bound per outsider lever

Totals are per day. "Address" is an IPv6 /64 or an IPv4 address; the zone rule below allows
1,200 requests per minute per IP before the Worker runs.

| Lever | Cost per day | Bound |
|---|---|---|
| Register fake tokens | 7,200 Worker requests and 7,200 APNs calls per address; no D1 access | Only per address: the total is 7,200 × the addresses the caller holds. Apple publishes no throttling rule for provider requests to invalid tokens, so the operator sets a Cloudflare usage alert. |
| Register real tokens | One D1 row per token | Rows are bounded by real installs. |
| `PUT`/`DELETE` with wrong secrets | 43,200 Worker requests and 43,200 D1 reads per address (one indexed read each); no write, no APNs call | 30 per minute per address; the total scales with the addresses the caller holds. |
| Push with forged or garbled handles | One Worker request and one HMAC each; no D1 access, no limiter, no APNs call | Requests from outside Cloudflare: the zone rule, at most 1,728,000 per IP; blocked requests cost nothing. Requests from a Worker are exempt from that rule and are bounded only by the caller's own request rate; the usage alert covers them. |
| Push with one genuine handle | At most 86,400 requests reach D1 (one lookup and one guarded counter statement each) | 60 per minute per handle per Cloudflare location; at most 500 APNs alerts, 500 background pushes and 3,000 D1 row writes (two counters and `last_used_at` per delivered push). |
| Push with replaced handles | Each registration of a real token mints a handle whose MAC stays valid after the row is replaced; a push with it costs one D1 read and gets 410, with no write and no APNs call | Minting: 5 registrations per minute per address and 2 per minute per token, so at most 2,880 handles per day per real token. Each handle: 60 requests per minute into D1. |
| Push to a real device | At most 500 APNs alerts and 500 background pushes | 60 per hour and 500 per day per device and bucket, however many times its token is registered. |
| Deny other installs or servers | Contention for the relay's one D1 database | No shared counter or ceiling exists to exhaust, and D1 growth is bounded by real installs. The two D1 paths an outsider reaches are wrong-secret `/self` requests (30 per minute per address) and replaced handles (60 per minute each, minted as above); their total is bounded only by the addresses and real tokens the caller holds and by D1 throughput. |

- **Token holders.** Whoever holds an install's raw APNs token can register it, which replaces the
  install's registration (its Server then gets 410), and can push generic alerts to it until that
  device's 500-per-day budget is spent, which also blocks its own Server's pushes for the day. The
  ciphertext of such pushes fails NSE decryption, so only the generic alert shows. The
  relay-capable App never sends its raw APNs token to a Server in relay mode.
- **Lost registration.** On a 410 from `PUT /v1/registrations/self`, or when its Server reports
  that the handle is gone, the App registers again and sends the new handle to its Server.

### Operator steps for the deployed host

- No relay D1 database has been created yet, so migration `0001_init.sql` is still edited in
  place. Once a database exists, schema changes go into new migrations.
- Add a zone-level Cloudflare rate-limiting rule on the relay hostname, for example 1,200 requests
  per minute per IP on `/v1/*`, answering 429. It bounds each IP, not the total: a caller holding
  many IPv6 addresses passes it per address, so also set a Cloudflare usage alert. Match
  only requests that do not come from a Worker, with `cf.worker.upstream_zone eq ""`. Do not
  match on the `CF-Worker` header: Cloudflare adds it after firewall rules run. The rule runs
  before the Worker, so blocked requests cost no Worker invocation.
- Set `HANDLE_KEY` with `wrangler secret put HANDLE_KEY` before the first registration.
- To rotate `HANDLE_KEY`, set the new secret and then delete every registration:
  `wrangler d1 execute hiboss-push-relay --remote --command "DELETE FROM registrations"`.
  Without the delete, `PUT /v1/registrations/self` still answers 204 and refreshes `last_used_at`,
  so no install ever re-registers while every push gets 410. With it, each App's next `PUT` gets
  410 and the App registers again (see **Lost registration**); Servers drop the old handles on
  their next push.
- Optionally, after the first deploy, run the source probe. It is informational only: no relay
  limit depends on its result. Deploy a throwaway echo Worker on the relay's zone (for example
  `probe.hiboss.org`) that returns the `CF-Connecting-IP` and `CF-Worker` request headers it
  received; the relay itself logs nothing. Call it with `fetch` from a throwaway Worker on a
  different custom zone, from one on a `*.workers.dev` subdomain, and with `curl` from a host
  outside Cloudflare, and record what it sees, which shows what the zone rule keys on for
  Worker-hosted Servers. Delete the probe Workers afterwards.

## Relay storage and configuration

- `registrations`: `handle_hash`, `secret_hash`, `apns_token`, `environment`, `created_at`,
  `last_used_at`; `apns_token` is unique. No content and no server identity.
- `rate_counters`: `key` (scope, window length, window number), `count`, `expires_at`. The only
  scope is `token:<SHA-256 of the APNs token>`.
- Secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY` (PKCS#8 PEM), `HANDLE_KEY`. Rate
  Limiting bindings: `HANDLE_RATE_LIMITER`, `REGISTRATION_RATE_LIMITER`, `TOKEN_RATE_LIMITER`,
  `SELF_RATE_LIMITER` (`[[ratelimits]]`). See
  `relay/wrangler.toml.example`.
- The relay writes no logs of handles, secrets, APNs tokens or ciphertext.

## Server behaviour

- The Server reports its push mode to the App in an authenticated capabilities/config response:
  `direct` when `APNS_*` secrets are configured (unchanged behaviour), `relay` when there is no
  APNs key and the relay is enabled, `none` otherwise.
- The relay is used only when no APNs key is configured. `PUSH_RELAY_URL` defaults to
  `https://push.hiboss.org`; `off` (trimmed, any case) disables the relay and an empty value means
  the default. With the relay enabled, the relay sees the
  Server's IP address, the handles and the timing of pushes.
- Device registration accepts `{ relayHandle, pushKey, environment }` as an alternative to an APNs
  token, with the usual boss authentication. These are stored per boss device like tokens, and
  deleting the device deletes them.
- Every alert path (notify, delivery adapters, probe, join notify) sends through one function that
  picks direct or relay. Quiet hours, priority rules and private-push preferences apply before the
  relay is called. A relay 410 removes the device row.
- When an agent ask closes, the Server sends each relay device of the ask's bosses one `resolved`
  push (see [Resolution pushes](reference/api-reference.md#resolution-pushes)). Quiet hours,
  priority and private-push preferences do not suppress it.
- The Server never logs handles, push keys or ciphertext.

## App behaviour

- An NSE target (bundle `ai.hiboss.app.NotificationService`) shares an app group and keychain
  access group with the app to read `pushKey`.
- When the Server reports `relay`, the App registers with the relay, keeps `deviceSecret` in the
  keychain and sends `{ relayHandle, pushKey, environment }` to the Server. On an APNs token change
  it calls `PUT /v1/registrations/self`. On a 410 from that call, or when the Server reports that the handle is gone, it registers again
  and sends the new handle to the Server. It never sends its raw APNs token to a Server in relay
  mode. On sign-out it deletes at the relay and at the Server,
  then erases the secret and the key.
- When the Server reports `none`, Settings → Notifications states that push is unavailable for
  this server and why, and the App does not prompt for notification permission.
- Live Activity pushes are not relayed: activity tokens are not APNs-verified registrations, and
  an NSE cannot decrypt a Live Activity push. With the relay, Live Activities update while the
  app runs, and a `resolved` push or the next launch ends the activity of a closed ask.

## Invariants

- The relay stores no content, no server identity beyond rate-limit counters, and only hashes of
  handle and deviceSecret. The APNs key exists only as a Worker secret.
- No path lets a Server push to an install that did not register with it, except for a holder of
  the install's raw APNs token (see [Token holders](#cost-and-availability-bound-per-outsider-lever)).
- The relay stores a registration only for a token APNs accepted for `ai.hiboss.app`.
- Tests cover: every relay API rule, the token check, each limit, one registration per token, 410 cleanup, the purge and the
  no-oracle property (`relay/test/`); server mode selection, an encryption round-trip decrypted
  with WebCrypto, and 410 handling; an iOS unit test for NSE decryption (valid, wrong key, wrong
  AAD, truncated) and a test for the `none` notice.
