# Agent keys rollout — phase 4

`api_keys = agents`: the table name and every existing identity ID stay the same.
Migration 0045 copies each existing SHA-256 hash to one `agent_keys` row labelled
`migrated`. Installed bearer values do not change. All seven production agents and
the Mac/Linux hook installations can continue using their existing configuration.
Rotation is optional. This document describes the rollout; this branch does not deploy it.

## Migration detail

The model change retains every legacy column and adds `agent_keys` and `is_admin`.
One physical exception is necessary: the old `key_hash TEXT NOT NULL UNIQUE` has no
default. SQLite cannot relax that constraint with `ADD COLUMN`. Migration 0045
rebuilds only the small `api_keys` table, making the retained hash nullable, with
foreign-key validation deferred. It preserves its final name, IDs, other fields,
hashes and name index. New identities omit the old column entirely.

No existing incoming FK cascades deletes; `agent_keys` and its cascade are created
after the rebuild. The migration fixture checks all existing child tables' SQL,
root pages and row contents, including 29,006 messages. Neither `messages` nor its
indexes/FKs are rebuilt or modified. Check this assumption before deploying if any
new migration adds an incoming cascading FK. `DESTINATIONS_MODE` is unchanged.

Existing `role = 'admin'` gains `is_admin = 1` and keeps its legacy role marker so
the old Worker retains admin access during deployment. The new Worker authorizes
agents only through `is_admin`. Self configuration still accepts only workflow roles
orchestrator, worker, reviewer or null and cannot grant admin. Clear legacy
`role = 'admin'` values in a later phase after all old Workers are retired.
Boss roles remain admin/manager/viewer, independently of agent capabilities.

## Deploy order

1. Back up D1 and verify that the seven agent names are distinct. Record agent IDs,
   key counts and message counts without exporting bearer values or printing hashes.
2. Review and apply migration 0045 before deploying the Worker. Apply it as one
   migration transaction, not as independently committed statements. The old Worker
   still reads the preserved hashes and admin role during this window, so existing
   bearer authentication and admin access continue. Avoid enrolling agents in
   the interval between migration and Worker deployment.
3. Deploy the Worker. Check the old bearers with `GET /api/agents/me` on each box;
   `id` must be unchanged and the added `agent_key_id` must be non-null. Check one
   admin agent's existing `/api/keys` access. Do not rotate as part of deployment.
4. Confirm one migrated key per pre-existing identity, preserved usage timestamps,
   no foreign-key violations and unchanged message counts. Verify that revoking a
   disposable test key gives 401 through both agent-only and dual authentication.
5. Deploy the console and distribute CLI 1.10.0. Old CLIs remain supported without
   re-enrolment. Before optional rotation, account for copies of a shared bearer:
   revoking it affects every installation using that same value.

Authentication reads non-revoked `agent_keys` first. The temporary legacy fallback
applies only when **no** row has the hash, including revoked rows. A revoked migrated
key therefore cannot regain access through `api_keys.key_hash`. If the Worker goes
live before 0045, only the D1 `no such table: agent_keys` error triggers a direct
legacy hash lookup, with one warning per isolate. Agent-only and dual authentication
remain available; other database errors propagate. Every request retries the
credential query so migration takes effect without an isolate restart. This bridge
covers existing authentication; key management, the new admin capability gate and
enrollment require migration. Credential activity uses a conditional update at most
once per minute; agent activity keeps its existing
per-request timestamp semantics. Remove the fallback and legacy column in a later
phase after parity has been observed. Do not roll back to a legacy Worker after key
revocation: it would still accept legacy hashes and cannot use newly minted keys.

## Rotate a box

Install CLI 1.10.0 on that box, then run:

```sh
hiboss key list
hiboss key rotate --label "Mac development"
hiboss key list
```

On a Linux installation use a distinct label such as `the Linux build box` or
`the Linux build box`. Commands operate on the current configured agent, not the current
project. Rotation fetches the current identity/key ID, mints with the existing
bearer, verifies the new bearer with `GET /api/agents/me`, checks both identity and
credential IDs, writes the config atomically, then revokes the old key using the
new bearer. Success never prints the new secret. Other config fields are retained.

The replacement and previous-config backup are owner-only files. A rotation lock
prevents concurrent rotations. The config is checked for unexpected edits before
replacement and before restoration. A failed pre-swap write leaves the original
config intact. `hiboss key revoke <full-key-id>` revokes a specific credential;
self-service cannot revoke the current key if it is the last live one.

## Failure and recovery

- Mint, verification or pre-swap write failure: the old active config stays intact;
  the command exits with an error stating that the previous key is retained.
- Revoke failure with a still-authenticating old key: the original config bytes are
  restored atomically. The newly minted key may remain live; inspect the inventory
  and revoke that unused key after resolving the failure.
- Revoke response failure with an unusable or unverifiable old key: the revocation
  may have succeeded remotely. The verified new config remains active; the error
  explicitly reports the uncertainty. The old key is retained in the backup, but
  its server-side validity cannot be guaranteed after a lost response. Restoring an
  already revoked bearer would lock the box out.
- A process interruption or concurrent external config change leaves recovery
  material available. Inspect the current identity and inventory before changing
  the config or removing stale rotation files; never blindly restore a revoked key.

Recovery files sit beside the OS-specific `hiboss/config.json`: `config.key-previous`
contains the previous config, `config.key-next` is the temporary replacement, and
`config.key-lock` is the lock. Successful rotation removes its backup and lock.
Failure retains the backup and blocks another rotation until it is deliberately
resolved. Copy failures in the console leave the one-time bearer visible for manual
selection. Do not paste recovery files or bearers into logs or progress reports.

## Boss recovery and inventory

An admin, or a manager with an explicit grant to the agent, can use Agents → select
agent → Agent keys to list labels/creation/last-use times, create a key and copy its
bearer once, or revoke a credential. Viewers cannot use these endpoints. The boss
may revoke even the final key, because boss-side minting can recover access later.
Use that recovery path to provision a box whose old key is unavailable:

```sh
hiboss config set key <new-bearer>
hiboss key list
```

Self routes are `/api/agents/me/keys` and `/:id`; boss routes are
`/api/boss/agents/:agentId/keys` and `/:id`. Mint accepts `{ "label": "box name" }`.
Inventories contain metadata only. Bearers are returned only by the mint response;
the database stores hashes. List/mint/revoke operations are audited, and key
mutations and their audit writes share a D1 batch transaction. Repeated revocation
is idempotent and does not add another mutation audit.

## Validation

The migration regression applies all real migrations to seven pre-existing agents,
including an admin, and checks unchanged child storage and credentials. Worker
tests cover migrated/fallback bearers, last-key guards, cross-agent access, workflow
roles and boss permissions. CLI tests use loopback mock servers and isolated config
files. Server E2E and browser checks run only on authorized remote grok hosts.

Validated on 2026-09-12:

| Check | Result |
| --- | --- |
| Remote `cd server && npm test` | 925 Worker tests + 19 schema/migration tests passed; 0 failed |
| `npm run check:schema` | 46 migrations through 0045, 38 tables, 109 indexes match |
| Server `npm run typecheck` | Passed |
| `cd web && npm run check && npm test` | 0 errors/warnings; 135 tests passed |
| `cd cli && env -u RUSTC_WRAPPER aid test -p hiboss` | 230 tests passed, 0 ignored; includes 7 rotation mock-server tests |
| `aid build check -p hiboss` | 0 errors, 0 warnings; shared `CARGO_TARGET_DIR` unchanged |
| Remote Chromium UI checks | 6 passed: four locales' key lifecycle/copy and manager/viewer controls |

The remote host was `the Linux build box` , in `/tmp/hiboss-agent-keys-xEIZqr`. Server evidence is
`server-final.log`; UI evidence is `browser-test.log`, `agent-keys-browser.mjs` and
`output/playwright/{en,zh-CN,ja,ko}.png` under that directory. Browser checks used
scoped HTTP fixtures; Worker tests exercised real D1 authorization and persistence.
The final enrollment/router cleanup also passed 28 focused Worker tests and typecheck.
No production migration, deployment, installed-key rotation or push was performed.

### Audit 4 fix validation — 2026-09-12

Reran on `the Linux build box` at `/tmp/hiboss-fix-4-LYQWcW` with the authorized Wrangler
config. Both deployment regressions failed before the fix and passed afterward.
SELF tests exercise the legacy hash/admin predicate before and after migration,
agent and dual boss auth with `agent_keys` dropped, then migration and revocation
in the same isolate. Separate tests check one warning and unrelated error propagation.

- `cd server && npm test`: 928 Worker tests and 19 schema/migration tests passed.
- `npm run check:schema`: 46 migrations through 0045, 38 tables, 109 indexes match.
- `npm run typecheck`: passed.
- `cd cli && env -u RUSTC_WRAPPER cargo test -p hiboss`: 228 library and 2 binary
  tests passed; 0 failed or ignored. Used an isolated target directory and debug info off.

Evidence: `deployment-red.log`, `deployment-green.log`, `server-final.log`,
`schema-final.log`, `typecheck-final.log` and `cli-final.log` in that remote directory.
Browser/web checks and production deployment were not rerun in this fix round.
