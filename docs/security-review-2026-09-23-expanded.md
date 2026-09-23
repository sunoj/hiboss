# Expanded security review — 2026-09-23

The first batch was committed as `ac6baab`. This second pass extends review to
unread message queries, established HTTP streams and blocking polls, and shared
Discord Gateway administration. Existing unrelated working-tree edits are excluded.
All verification uses synthetic credentials and local services; no production
endpoint, Discord bot, or deployment was changed.

## SEC-04 — High: unread message queries expose foreign-session messages

Baseline: `server/src/routes/message-helpers.ts`, `buildFilters`.

Both `unread=true&target_session=...` and its `direction=agent_to_agent` variant
contained an OR branch selecting A2A messages by session ID without requiring
the authenticated recipient. A valid agent credential and another session's ID
were sufficient to retrieve its pending messages and total count. The ordinary
message-detail ownership filter did not protect these list queries.

Two negative integration tests failed on the baseline, returning a foreign
message and `total: 1` instead of an empty list. The fix applies `target_agent_id`
to the entire A2A session predicate, including agent-wide messages. Regressions
also verify that the intended recipient still sees its message. Existing unread,
self-broadcast exclusion, and pagination/count queries share the corrected filter.

## SEC-05 — High: established HTTP streams outlive authorization

Baseline: `routes/stream.ts`, `routes/boss-api-stream.ts`,
`routes/session-events.ts`, and the blocking poll in `routes/messages.ts`.

Authentication ran at request entry. An agent with a subsequently revoked key
could continue receiving newly inserted messages on the existing stream. Boss
streams also retained their original role and agent access list. Session event
streams retained their initial session visibility. These HTTP requests could
remain active for five minutes. A compromised credential's already-established
connection therefore bypassed subsequent revocation decisions.

The baseline agent-stream regression received content inserted after key
revocation. The fix shares credential lookup with normal authentication and
revalidates before every SSE chunk, including resolution and keepalive events.
Boss streams additionally recheck all originally selected agent grants and close
when that scope shrinks; session event streams recheck session visibility.
Credential changes, role changes, and authorization lookup failures fail closed.
Rejected writes close the response before content is emitted or delivery state
is advanced. Blocking polls recheck credentials while waiting and before replies
or timeout results are returned.

Regression coverage includes agent-key revocation, boss token/client revocation,
role changes, partial grant removal, all three boss stream modes, agent/boss
session event streams, and a pending blocking poll. Positive stream tests verify
normal delivery and multi-client option behavior.

Limits: data already authorized and queued on a connection cannot be recalled.
This is a check-before-emission guarantee, not an atomic transaction combining a
database authorization check with network delivery. Idle SSE connections close
on their next keepalive check rather than through a new push-revocation service.
This adds a credential lookup per chunk and a scope lookup where applicable.
Clients reconnect using current credentials and permissions. Existing connections
on old Worker code need to drain or reconnect after deployment.

## SEC-06 — High: non-admin agents can control the global Discord Gateway

Baseline: `server/src/routes/discord-gateway-api.ts`.

The connect, disconnect, and status handlers required only an agent credential,
but targeted a singleton Durable Object shared by the deployment. An ordinary
agent could disconnect the shared integration or request reconnection with a
different bot token. It could also read gateway status. This conflicts with the
administrative boundary already enforced on channel/key management.

Three route-level tests with a stubbed Durable Object returned 200 for non-admin
requests before the fix. The tests verify that the stub is never reached after
the fix. `middleware/agent-admin.ts` now supplies the same `is_admin = 1` check to
the existing admin router and the Gateway router. Tests explicitly set the
self-editable profile `role` to `admin` while retaining `is_admin = 0`, and verify
rejection; the independent administrative capability still permits each action.

## Validation

Negative baseline runs: all three unread/agent-stream reproductions failed as
expected, and all three Gateway authorization reproductions failed as expected.
The tests now assert the secure behavior and remain in the repository.

Primary regression files:

- `server/src/routes/security-expanded.test.ts`
- `server/src/routes/discord-gateway-api.security.test.ts`

The final validation includes message and stream behavior, auth/schema/deployment
compatibility, agent-key lifecycle, admin access, and existing webhook/interactions
security checks. TypeScript checking is run separately with `npm run typecheck`.

Result: 19 test files / 302 tests passed, and TypeScript checking passed.
Reproduce from `server`:

```sh
npx vitest run src/routes/security-expanded.test.ts src/routes/discord-gateway-api.security.test.ts src/routes/message-helpers.test.ts src/routes/messages.test.ts src/routes/stream.test.ts src/routes/security-review-2026-09-23.test.ts src/routes/boss-feed-stream.test.ts src/routes/boss-option-stream.test.ts src/routes/session-events.test.ts src/middleware/auth.test.ts src/middleware/auth-schema.test.ts src/middleware/deployment.e2e.test.ts src/agent-keys src/routes/admin.test.ts src/routes/webhooks.test.ts src/routes/discord-interactions.test.ts src/routes/telegram-webhook-actions.security.test.ts
npm run typecheck
```

## Remaining review scope

Panel WebSockets use independently issued connection tickets and are not covered
by the HTTP stream wrapper. Preliminary inspection shows socket attachments retain
identity/role without an originating credential reference. Their credential
revocation and post-subscription broadcast authorization require a dedicated
reproduction and design review; this pass does not claim that revoking a bearer
key terminates a Panel socket. Native clients, CLI/MCP, dependency advisories,
and deployment-specific edge policies also remain outside this pass.

The prior attachment cache remediation requirement remains unchanged. No cache
purge, credential rotation, or production deployment was performed.
