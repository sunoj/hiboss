# Sign in with iPhone

A signed-out Mac (HiBoss Island) signs in by asking a signed-in iPhone. The Mac
shows a QR code, the iPhone approves it and then displays a 6-digit code, and
the Mac's user types that code on the Mac. The Mac then receives its own boss
token for the approving boss.

## Why the code goes from the iPhone to the Mac

Approving a QR code alone would let anyone who shows the boss a QR code collect
a token: the boss would be approving a request opened on someone else's machine.
The code is generated at approval and displayed only on the approving iPhone,
and the server releases the token only to the request whose poll token comes
with that code. Typing the code on the Mac proves that the person approving is
at that Mac.

## Flow

1. **Mac opens a request.** `POST /api/signin/requests` with `{"device_label"}`,
   no authentication. Returns 201
   `{"request_id", "poll_token", "expires_at"}`. `request_id` is 32 lowercase hex
   characters; `poll_token` is `st_` plus 64 hex characters and is a credential.
   429 when 200 requests are already open server-wide.
2. **Mac shows the QR code** for `hiboss://signin?server=<server URL>&request=<request_id>`
   (HTTPS, or plain HTTP only for a loopback server).
3. **Mac polls** `GET /api/signin/status` with header `X-Signin-Token: <poll_token>`.
   Returns `{"status", "expires_at"}` where status is `pending`, `approved`,
   `rejected`, `completed` or `expired`. 404 for an unknown token.
4. **iPhone scans and reviews.** `GET /api/boss/signin-requests/<request_id>` with the
   boss bearer token returns `{"request_id", "device_label", "origin", "status",
   "created_at", "expires_at"}`. `origin` is a coarse "country · city" of the
   Mac's network when known; show it so the boss can spot a request from
   somewhere unexpected. Admin or manager only (403 for a viewer).
5. **iPhone approves** with `POST /api/boss/signin-requests/<request_id>/approve`.
   Returns `{"code", "expires_at", "device_label"}`; 409 when the request is no
   longer pending. The code is not retrievable again; the iPhone keeps showing it
   until the Mac finishes or the request expires. `POST …/reject` ends a pending
   request, or one the same boss approved.
6. **Mac completes** with `POST /api/signin/complete`, header `X-Signin-Token`, body
   `{"code": "123456", "signing"?: {...}}`. Returns
   `{"token", "boss": {"id", "name", "role"}, "signing_key_id"?}`. Every failure
   is a 400 that does not say which check failed.

## Limits

- A request lives ten minutes from creation; approval does not extend it.
- Five wrong codes reject the request.
- Completion succeeds once. It also requires that the approving boss is not
  archived and that the token the iPhone approved with has not been revoked.
- The server stores SHA-256 hashes of the poll token and of the code (salted
  with the request id), never the values. Expired rows are deleted by the cron
  sweep and when a new request is opened.

## Client kind and signing

Without `signing`, the new token's client is kind `web`, as with code pairing.
With `signing`, the registration is the pairing one
(`{"algorithm": "ES256", "client_kind": "macos", "public_key", "proof"}`), but the
proof is an ES256 signature over
`hiboss-signin-v1\n<request_id>\n<client_kind>\n<public_key>`. A pairing-domain
proof (`hiboss-pair-v1`) is refused, so neither proof replays as the other.
