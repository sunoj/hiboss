# Boss clients phase 1a validation

Validated on 2026-09-11. All server E2E and browser execution ran on
`the Linux build box` in `/tmp/hiboss-clients-b6bfjX`, using isolated test databases.
Production was not deployed or migrated. Native binaries were not executed.

| Command | Result |
| --- | --- |
| `cd server && npm test` | 742 Worker tests + 13 schema/backfill tests passed; 68 files total |
| `cd server && npm run check:schema` | 40 migrations through 0039 match: 30 tables, 83 indexes |
| `cd server && npm run typecheck` | Passed locally |
| `cd web && npm run check` | 0 errors, 0 warnings on the remote box |
| `cd web && npm test` | 113 tests passed in 15 files |
| Final client inventory regression run | 11 tests passed after retaining revoked signing-key attachment metadata |

The server suite covers seeded legacy migration rows, unchanged bearer hashes,
client minting and authentication, current-client resolution, activity throttling,
token/key/push revoke cascade, audit insertion, signed and unsigned pairing,
cross-boss push ownership, admin panel visibility, lifecycle mutations, and viewer
grant removal. One old test assumed admins could not read other bosses' panels;
its denied caller is now a viewer, consistent with decision A.

Remote browser verification exercised paste-login against the real local Worker,
fresh-token persistence, the Devices navigation entry, the current-browser marker,
revoke cancellation, confirmed revocation, and HTTP 401 for the revoked phone token.
The current browser has no Revoke control. The existing favicon request returns
404 in development; it does not affect the verified flow.
English and Chinese Devices views, including translated timestamps, were inspected.

Remote logs: `server-test.log`, `clients-final-test.log`, and `web-test.log` in the
isolated directory above. Browser snapshots are under `.playwright-cli/` there.
The screenshot is `output/playwright/devices-en.png` in that remote workspace.
These are filesystem artifacts, not hosted URLs.

Implementation choices: unsigned pairing defaults to `web`; nullable links retain
compatibility with existing token issuance; any boss can revoke their own other
clients, while cross-boss client revocation remains unavailable even to admins.
Revoked clients remain in inventory, and signing-key attachment remains visible
after its key is revoked. The `boss_devices` rename and native adoption are deferred.

HiBoss report delivery was unavailable because the CLI had no resolved execution
session. Results were delivered in the task conversation instead.
