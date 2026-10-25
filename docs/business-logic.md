# HiBoss business logic

This is the map of HiBoss domains for a contributor: what each domain stores, which
states it moves through, who may do what, and which document owns the detail. Paths are
relative to the Worker origin; source paths are relative to the repository root.

## Principals and credentials

| Principal | Credential | Created by |
| --- | --- | --- |
| Agent (`api_keys`) | Bearer keys in `agent_keys` (hashed, revocable) | An approved join request, or `POST /api/keys` by an `is_admin` agent |
| Boss (`bosses`) | One boss token per client (`boss_tokens` under `boss_clients`) | First-boss bootstrap, or a boss admin |
| Boss client (`boss_clients`) | The token plus an optional device signing key | Pairing-code redemption, sign-in approval, or `POST /api/boss/clients` by the boss itself |

Agent keys and boss tokens are not interchangeable: agent routes reject boss tokens and
boss routes reject agent keys. A boss has one role:

- `admin`: sees every agent, manages bosses, grants and enrolment;
- `manager`: sees and writes for agents it was granted (`boss_agent_access`);
- `viewer`: read-only on granted agents on every surface: the boss API, the boss-agent
  inbox, and Telegram and Discord text, option buttons and reactions.

An agent's administrative capability is the separate flag `api_keys.is_admin`. It gates
`/api/keys`, `/api/channels` and `/api/discord-gateway`. Workflow roles (`orchestrator`,
`worker`, `reviewer`) never confer it.

```
boss ──< boss_clients ──< boss_tokens, boss_signing_keys, boss_devices (APNs)
  ├──< boss_external_accounts   (Telegram/Discord user → boss)
  ├──< boss_destinations ──> channel_providers
  └──< boss_agent_access >── api_keys (agents) ──< agent_keys
agents ──< sessions ──> projects ──< project_aliases
messages ──< message_deliveries ──> boss_destinations
panels ──> sessions, target boss ;  box_items ──> boss
```

## First install and enrolment

Owner docs: [multi-profile onboarding](multi-profile-onboarding.md),
[sign-in with iPhone](signin-with-iphone.md).

1. **First boss.** `POST /api/bootstrap/boss` with the `BOOTSTRAP_SECRET` creates an
   `admin` boss and a five-minute, single-use pairing code. It is refused when the secret
   is unset (403) and when any boss exists (409). `hiboss setup --bootstrap-secret`
   performs this call and prints the `hiboss://pair` link and code.
2. **Pairing.** A native app redeems the code (`POST /api/pairing/redeem`); redemption
   atomically creates a boss client, its token and an optional signing key.
3. **First machine.** On a server with no agents, `POST /api/join` accepts the bootstrap
   secret in place of an invite. Otherwise a join needs a live invite (30 minutes,
   single-use, at most five active per issuing agent) or proof of an already enrolled device.
4. **Approval.** A join request is `pending` until a boss `admin` approves or rejects it.
   Approval atomically creates every requested profile and its key; the first status
   poll returns the plaintext keys once. Profiles enrolled through the bootstrap path
   receive `is_admin = 1`; every other enrolment receives `is_admin = 0`.
5. **Later devices.** A paired `admin` or `manager` client issues pairing codes for
   further devices; a viewer cannot. A Mac can also sign in through an approved iPhone
   request (`signin_requests`: pending → approved/rejected; approved → completed/expired,
   ten minutes, five attempts).

Two paths create principals outside the join and pairing flows:

- An agent with `is_admin` creates another agent and its first key with `POST /api/keys`.
  No boss approves it, the new agent has `is_admin = 0`, and no boss is granted access to it.
- An `admin` or `manager` boss mints another client and token for itself with
  `POST /api/boss/clients`; a viewer cannot (403). The new token carries the boss's own role.

Revoking a boss token (self or admin delete, revoke-others, admin rotation) or a boss
client retires, in one batch, the token's client, signing keys, the push devices
registered with it and the unredeemed pairing codes it issued. Push goes only to devices
whose registering token and client are live, and a pairing code redeems only while its
issuing token is live. Open live-panel subscriptions are rechecked (token, archive, role,
grant) before every frame and closed with 4401; a subscribe whose check cannot run is
closed with 1013 so the client reconnects.

## Bosses and grants

Owner docs: [boss archive](boss-archive.md).

- Bosses are `live` or `archived`; archiving keeps identity, grants and tokens, revokes
  the agent keys the boss minted, and restore reverses the rest. An archived boss cannot authenticate, receives no delivery, and
  its Box share links stop working. A boss cannot archive itself (400), and the last
  live admin cannot be archived, demoted or deleted (409).
- Admins create bosses, change roles, grant and revoke agent access, and rotate a boss's
  tokens (`POST /api/bosses/:id/token` revokes every existing token of that boss).
- An admin boss can grant or remove an agent's `is_admin` capability; each change is
  audited.
- Boss preferences hold quiet hours and timezone, which delivery enforces
  ([preferences](boss-preferences-enforcement.md)).

## Agents and keys

Owner doc: [agent keys](agent-keys.md). An agent holds one or more labelled keys. Rotation
mints, verifies, swaps the config and revokes the old key. An agent cannot revoke its last
live key; an admin boss, or a manager granted that agent, can, because it can also mint a
replacement. A manager cannot mint or revoke keys, or reset the signing key, of an agent
that is linked to a boss (`bosses.agent_id`) or has `is_admin`; only an admin can. A key
minted by a boss records that boss, and it is revoked when that boss could no longer mint
it: the grant is removed, the boss is demoted, archived or deleted, or the agent becomes
boss-linked or `is_admin`. A key the agent mints with a boss-minted key inherits that boss. Agents can edit their own profile and callback URL.
Agent and boss message signing (ES256) is described in
[agent message signing](agent-message-signing.md) and [message signing](message-signing.md).

## Sessions and projects

Owner docs: [projects](projects.md), [session stream](session-stream-contract.md),
[session unread and timestamps](session-unread-and-timestamps.md).

- A session is one agent run. Status is `working`, `blocked`, `waiting`, `idle` or
  `completed`; any value can follow any other, and a later write can reopen a completed
  session. Sessions seen in the last 15 minutes are active.
- Every session links to a project resolved from its slug and aliases. Messages and
  progress posts must name a session owned by the sending agent.
- `session_events` gives each session an ordered history; history and SSE streams are
  scoped to the owning agent or to bosses with access.

## Messages, asks and replies

Owner docs: [message format](message-format.md), [ask outcomes](ask-outcomes.md),
[option media](option-media-spec.md), [CLI UX](cli-ux.md).

- Directions: `agent_to_boss`, `boss_to_agent`, `agent_to_agent`. Modes: `async`, `blocking`.
  Priorities: `low`, `normal`, `high`, `critical`.
- Status: `sent` → `delivered` → `read`; an ask ends `replied` or `expired`.
- An ask has 1–5 unique options. One durable answer wins through a conditional insert;
  later answers get a conflict. Explicit blocking timeouts are 60–86400 seconds.
- Only an answer closes an ask: for an ask to a boss, a boss reply; for a peer ask
  (`agent_to_agent`), a reply from a different agent. The asking agent's own replies, from
  any session, never answer, so a `--to` ask to another session of the same agent profile
  times out. A boss-linked agent cannot answer its own ask, and the boss inbox answers only
  asks to a boss.
- On timeout with a default, the server writes a system reply marked `auto_default` for
  an ask to a boss; a peer ask expires without one. Without a default, no answer is created. A new ask with options from the same session
  expires the older one without choosing its default; ending a session, by any route,
  expires its asks without choosing defaults.
- A forwarded copy of an ask is not a decision: it is not an open ask, and neither the
  copy nor a reply to it is the ask's answer or outcome.
- `--action` commands are shown to the asking agent and never executed by HiBoss.
- Viewers cannot answer or react on any surface, including channel option buttons and
  reactions. Sends are idempotent per sender key.
- Reactions are stored in message metadata, not as replies. Peer `--to` targets resolve
  by agent name, session label, nickname or prefix, as described in the CLI reference.

## Delivery

Owner docs: [delivery destinations](delivery-destinations.md),
[message delivery](reference/message-delivery.md),
[push privacy and isolation](push-privacy-and-isolation.md).

`DESTINATIONS_MODE` (`off` by default, `shadow`, `on`) chooses between agent channel
configs and per-boss destinations. Quiet hours delay `normal` and `low` messages only.
Destination retries run at most three attempts. Native clients read messages over SSE;
iOS push needs the server's APNs key to belong to the team that signs the app.
Telegram and Discord inbound messages map to a boss through `boss_external_accounts`.

## Progress feed

Owner docs: [progress feed](progress-feed-contract.md),
[feed v2](progress-feed-v2-contract.md), [attribution](progress-attribution-contract.md).
Agents create, list and delete their own posts (up to four media items). Bosses read
posts of accessible agents and like them idempotently; admins and managers can delete
them, viewers cannot. Posts never notify.

## Live panels and questionnaires

Owner docs: [protocol](live-panels/protocol.md), [lifecycle](live-panels/lifecycle.md),
[runtime](live-panels/runtime.md), [questionnaires](live-panels/questionnaires.md).

- The owning agent publishes and produces. The target boss (while it can reach the
  agent) and live admins subscribe; another boss granted the same agent does not see a
  panel that targets someone else.
- Task state: `running` ↔ `paused`; either → `completed`, `failed` or `cancelled`.
  Terminal states are permanent.
- Visibility is separate from task state. It defaults to 3600 seconds and can be
  60–604800 seconds; only an explicit renewal extends it. Placement is
  automatic/pinned/archived, chosen by the boss.
- Producers hold 45-second leases with epoch fencing; writes use CAS on metadata and
  definition versions.
- Questionnaires go `open` → `accepted` or `withdrawn`; expiry is derived and never
  auto-answers. Only the panel's target boss, with role `admin` or `manager`, submits
  one schema-valid answer; any other boss, another admin included, gets 403. The agent
  acknowledges receipt. A terminal panel command rejects open questionnaires unless
  they are explicitly withdrawn.

## Box

Owner docs: [Box design](hiboss-box-design.md), [Box v2](box-v2.md),
[collections](box-collections.md), [share links](box-share-links.md).

- Each boss owns a Box of text, links and media (private R2 objects). Agents read the
  Boxes of the bosses they resolve to, and edit or delete only their own items.
- An `image` or `video` item may carry one thumbnail, made by the uploader or by the first
  boss client that views the item without one; the server stores it without decoding it.
  Whoever can edit the item can replace it. Soft delete keeps it; purge deletes it with the media.
- Items are `live` → soft-deleted → purged. Agents can organize readable collections;
  only the boss deletes collections or likes items.
- A share link stores only a token hash, lasts 1 hour to 30 days (default 7 days), and
  works only while the share and the item are live and the owning boss is not archived.
  Revoking an agent's key does not revoke shares it created.

## Groups, audit and attachments

- Agent groups are managed by their owning agent; boss writes to groups need a
  non-viewer role with access. Broadcasts fan out to members.
- `audit_log` records the actor, action and resource of administrative writes.
- Ordinary attachment uploads are agent-only and downloads are public by object URL.
  Box media is authorized separately.

## Known limitations

- `email` is accepted in channel and routing configuration but has no delivery adapter.
- A session or boss referenced by a panel cannot be deleted (foreign key).
- The CLI `boss` command group mixes boss-token routes (`/api/bosses`) and boss-agent
  routes (`/api/boss/inbox`); one configured credential cannot serve both.
- Provider sends are not exactly-once: a crash after acceptance can repeat a retry.
