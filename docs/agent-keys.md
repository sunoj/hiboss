# Agent keys

An agent identity is a row in `api_keys`. Its bearer credentials live in `agent_keys`:
each identity can hold several independently revocable keys. The database stores only
SHA-256 hashes; a bearer value is returned once, by the mint response.

## Model

- `api_keys` keeps its table name and identity IDs. Migration 0045 copies each legacy
  `key_hash` to one `agent_keys` row labelled `migrated`, so installed bearers keep
  working without re-enrolment. New identities never write the legacy hash column.
- Administrative capability is the separate `api_keys.is_admin` flag. Agents are
  authorized for admin-gated routes (`/api/channels`, `/api/keys`, Discord gateway)
  only through `is_admin`. Rows whose legacy `role` was `admin` were migrated to
  `is_admin = 1`.
- Workflow roles (`orchestrator`, `worker`, `reviewer`, or null) are separate from
  `is_admin`. Self configuration accepts only workflow roles and cannot grant admin.
- Boss roles (`admin`, `manager`, `viewer`) are independent of agent capabilities.

## Authentication

Authentication reads non-revoked `agent_keys` rows first. The legacy fallback to
`api_keys.key_hash` applies only when no `agent_keys` row has the hash, including
revoked rows, so a revoked migrated key cannot regain access through the legacy column.
If the `agent_keys` table is missing (a Worker running ahead of migration 0045), only the
D1 `no such table: agent_keys` error triggers a direct legacy hash lookup, with one
warning per isolate; other database errors propagate. Every request retries the
credential query, so the migration takes effect without an isolate restart. Key
management, the admin capability gate and enrolment require the migration.

Credential activity is updated at most once per minute; agent activity keeps its
per-request timestamp.

## Self-service rotation

```sh
hiboss key list
hiboss key rotate --label "Mac development"
hiboss key list
```

Commands operate on the configured agent, not the current project. Rotation:

1. fetches the current identity and key ID;
2. mints a new key with the existing bearer;
3. verifies the new bearer with `GET /api/agents/me`, checking identity and key IDs;
4. writes the config atomically;
5. revokes the old key using the new bearer.

Success never prints the new secret. Other config fields are retained. The replacement
and the previous-config backup are owner-only files; a rotation lock prevents
concurrent rotations, and the config is checked for unexpected edits before replacement
and before restoration. `hiboss key revoke <full-key-id>` revokes a specific credential;
self-service cannot revoke the current key if it is the last live one.

## Failure and recovery

- Mint, verification or pre-swap write failure: the old config stays active and the
  command exits with an error stating that the previous key is retained.
- Revoke failure while the old key still authenticates: the original config bytes are
  restored atomically. The newly minted key may remain live; revoke it after resolving
  the failure.
- Lost revoke response with an unusable or unverifiable old key: the revocation may have
  succeeded remotely. The verified new config stays active and the error reports the
  uncertainty. Restoring an already revoked bearer would lock the machine out.
- A process interruption or a concurrent config change leaves recovery material in
  place. Inspect the current identity and key inventory before changing the config.

Recovery files sit beside `hiboss/config.json`: `config.key-previous` (previous config),
`config.key-next` (temporary replacement) and `config.key-lock` (lock). Successful
rotation removes the backup and lock. A failure keeps the backup and blocks another
rotation until it is resolved. Do not paste recovery files or bearers into logs.

## Boss-side inventory and recovery

An admin boss, or a manager with an explicit grant to the agent, can list key labels and
creation/last-use times, mint a key (copying its bearer once), or revoke a key. Viewers
cannot use these endpoints. A boss may revoke the final key, because boss-side minting
can restore access later:

```sh
hiboss config set key <new-bearer>
hiboss key list
```

| Caller | Routes |
| --- | --- |
| Agent (self) | `/api/agents/me/keys`, `/api/agents/me/keys/:id` |
| Boss | `/api/boss/agents/:agentId/keys`, `/api/boss/agents/:agentId/keys/:id` |

Mint accepts `{ "label": "machine name" }`. Inventories contain metadata only. List,
mint and revoke are audited; key mutations and their audit rows share one D1 batch.
Repeated revocation is idempotent and adds no further mutation audit.

## Known limitations

- The legacy `api_keys.key_hash` column and the authentication fallback remain.
- The legacy `role = 'admin'` marker is kept alongside `is_admin`.
- A Worker version older than migration 0045 still accepts legacy hashes and cannot use
  newly minted keys, so it cannot safely serve a database where keys have been revoked.
