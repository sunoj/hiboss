# Security review — 2026-09-23

Baseline: commit `38c8570` plus the existing working tree. The three findings are
now fixed in the working tree with security regression tests. Deployment and
production cache remediation have not been performed. Existing uncommitted
CLI/MCP/documentation work was preserved.

The descriptions and line references below document the original vulnerable
baseline. Priority reflects impact and the stated preconditions, not a calculated
CVSS score. The implementation notes describe the fixes.

## SEC-01 — High: foreign-session SSE interception

Locations: `server/src/routes/stream.ts:18`, `:98`, and `:67`.

`GET /api/messages/stream?session=...` accepts an arbitrary session ID without
checking its owner. The session-specific query's final OR branch filters only on
`target_session_id`, `direction = 'agent_to_agent'`, and `status = 'sent'`.
It does not restrict the recipient to the authenticated agent.

An attacker needs a valid agent credential and a victim session ID. Session IDs
are caller-supplied identifiers, not authorization credentials. The attacker can
receive another sender's pending A2A message to that session. The stream then
marks it `delivered`, potentially preventing the intended recipient's SSE stream
from receiving it. This is both a confidentiality and delivery-integrity failure.

Local reproduction uses three different agents: sender, recipient, and attacker.
The attacker receives `private review payload` through the public Worker endpoint;
the database then reports the victim message as `delivered`. A future fixture
timestamp avoids test timing dependence on the stream's starting watermark.

Implemented: session ownership is checked before opening the stream; every A2A
query branch and the delivery update constrain the authenticated recipient. The
update also retains the selected session scope. Unknown and foreign sessions
return 404. Regression tests verify that rejected subscriptions leave messages
unread and that the intended recipient can still receive them. Positive tests
cover agent-wide, own-session, and NULL-target-session delivery.

## SEC-02 — High: active attachments execute on the dashboard origin

Locations: `server/src/routes/attachments.ts:83`, `:114`;
`server/src/attachments/index.ts:49`; `server/src/dashboard.html:1133`.

Multipart upload accepts caller-controlled HTML and SVG MIME types. Downloads
preserve that type, use `Content-Disposition: inline`, and carry no sandbox CSP.
The returned attachment URL shares the origin of `/dashboard`, which persists
the user's credential as `localStorage.hiboss_key`.

An attacker with an agent key can upload active content and induce a dashboard
user to open the attachment URL as a document. Its script runs in the dashboard
origin and can access that origin's stored credential. The impact depends on the
victim's credential privileges. A separate-origin console is not implicated by
this localStorage path. Rendering SVG only as an image is not the same trigger
as opening it as a document.

Local HTTP reproductions confirm both HTML and SVG are accepted, served unchanged
without authentication, and returned inline under the dashboard origin without
CSP. The harmless fixture only assigns the stored value to `document.title`;
it sends no data anywhere. Browser script execution was not automated in this
review; the execution impact follows from the returned document policy.

Implemented: only PNG, JPEG, GIF, WebP, AVIF, and MP4 retain inline delivery.
Other types, including HTML and SVG, are served as `application/octet-stream`
with attachment disposition and `Cache-Control: no-store`. All object responses
include `nosniff` and a restrictive sandbox CSP; filenames use an ASCII fallback
and a UTF-8 encoded parameter. The policy is applied at download time, including
legacy objects, HEAD, and byte ranges. Uploads remain available for arbitrary
document downloads. Media range and inline-response regressions pass; browser
playback/script execution was not automated.

Deployment follow-up: after deploying, purge cached attachment responses at any
configured CDN/cache layer and verify headers on an existing HTML/SVG object.
Previously issued year-long immutable responses may remain in browser caches;
server changes and CDN purges cannot revoke those copies. If active attachments
were distributed, require affected users to clear the API origin's cached files
before reopening old links, and assess whether their credentials need revocation.
Fresh download responses are protected; this patch does not claim to neutralize
already cached documents. No cache purge or credential revocation was performed.

## SEC-03 — High: join bypasses the bootstrap secret

Locations: `server/src/routes/join.ts:37`; `server/src/routes/bootstrap.ts:17`.

When `api_keys` is empty, unauthenticated `POST /api/join` immediately creates the
first agent and returns its key. It never checks `BOOTSTRAP_SECRET`, even though
`POST /api/bootstrap` enforces that configured secret.

An unauthenticated caller can claim the first agent on a fresh deployment or
after all agent identities are removed, despite configuring protected bootstrap.
The issued credential has ordinary agent access; this review does not claim that
the new agent is an administrator. Initialized deployments with existing agents
take the pending-approval branch instead.

Local reproduction sets a bootstrap secret on an empty test database, observes
401 from unauthenticated bootstrap, then 201/approved from unauthenticated join.
The returned credential successfully authenticates to `/api/agents/me`.

Implemented: `middleware/bootstrap-secret.ts` provides the shared policy used by
bootstrap and first-agent join. Missing or incorrect configured secrets return
401 before any agent or join-request insertion. Both existing secret header
forms remain supported. Tests cover authenticated first join, open first join
when no secret is configured, and unauthenticated pending approval on initialized
deployments. The atomic first-agent guard is unchanged.

## Validation and scope

Original audit validation: 9 test files / 67 tests passed, including four
vulnerability reproductions. Fix validation: 6 test files / 57 tests passed;
server TypeScript checking passed.

Regressions: `server/src/routes/security-review-2026-09-23.test.ts`. The original
vulnerability assertions have been replaced with rejection/isolation assertions
and authorized-path checks. Additional coverage lives in `stream.test.ts` and
`attachments/download.e2e.test.ts`.

Run from `server`:

```sh
npx vitest run src/routes/security-review-2026-09-23.test.ts src/routes/stream.test.ts src/routes/bootstrap.test.ts src/routes/join-flow.test.ts src/routes/attachments.test.ts src/attachments/download.e2e.test.ts
npm run typecheck
```

The local setup uses Node 22.22.0, lockfile dependencies installed with
`npm ci --ignore-scripts --no-audit --no-fund`, and an ignored `wrangler.toml`
copied from the example. Tests use local workerd/D1/R2 with synthetic credentials.
No production endpoint was probed.

Focused review covered route wiring, auth and credential lifecycle, join/bootstrap,
pairing, attachment handling, message/session streaming, and selected project and
panel access policies. Project profiles/aliases are documented as shared rather
than creator-owned, so shared writes were not reported as an ownership bypass.

This is not an exhaustive audit of native clients, CLI/MCP, dependencies, deployed
edge policies, or every panel/webhook path. Existing key-revocation, role/scope,
pairing, and webhook tests provide supporting checks only within their tested cases.
