# Destinations phase 2b validation

Implemented on `feat/destinations-console`; local commit only. No deployment,
hosted D1 migration, production mode change, push, or PR was performed.

## FIX round on c404163

All required checks ran on `the Linux build box` in the isolated checkout
`/tmp/hiboss-fix-2b-c404163`. The requested source Wrangler file was copied into
`server/` first. The final server command was exactly `npm test && npm run check:schema
&& npm run typecheck`; the final web command was `npm run check && npm test`.

| FIX-round check | Final result |
| --- | --- |
| Server Worker suite | 877 passed, 80 files; 0 failed |
| Server schema/backfill suite | 15 passed, 4 files; 0 failed |
| `check:schema` | 43 migrations through 0042; 36 tables, 101 indexes |
| Server typecheck | Passed |
| Web check | 0 errors, 0 warnings |
| Web tests | 129 passed, 16 files; 0 failed |
| Parent/current HTTP comparison | 43 passed, 1 file; 0 failed |
| Wrangler local D1 migration apply, twice | 0042 applied; second pass: no migrations to apply |
| Guarded Cargo check | Not completed: target-directory sandbox denial before compilation |

Final remote logs use prefix `/tmp/hiboss-fix-2b-` and suffixes `server.log`,
`schema.log`, `typecheck.log`, `web-check.log`, `web-test.log`, `comparison.log`,
`wrangler-first.log`, and `wrangler-second.log`. Local Cargo output is
`/tmp/hiboss-fix-2b-cargo.log`. These are host-local artifacts, not public URLs.
The Worker suite includes authenticated API E2E and real D1 migration probes.
This FIX round did not rerun browser UI scripts or live provider delivery, query
production identities, or perform the production parity week. Historical browser
and build evidence is retained below and is not claimed as a new run.

The independent audit's F1/F2/F3 failures are addressed. Target identity now uses
the effective credential hash and effective chat/thread through one helper shared
by dispatch and shadow. Migration 0042 backfills SHA-256, consolidates existing
duplicate providers without dropping destinations or delivery attribution, and
enforces credential uniqueness. Provider creation returns a credential-free 409
for duplicate credentials, including concurrent requests and changed app IDs.
The simpler operational choice is one self-contained SQL migration, with no
credential export, application backfill job, or extra delivery/retry mechanism.

The exact audit fixture (two provider rows, identical token, two bosses, Telegram
chat `<chat id>`) now produces one adapter call, one canonical delivery row, and
one merged attribution row. Shadow produces the identical canonical key and zero
mismatch audits without sending. After migration, one provider remains and both
destinations plus all four on/shadow delivery rows survive. D1 backfill hashes
match Web Crypto for empty/ASCII/UTF-8 input and 55/56/63/64/65/119/120/200-byte
boundaries. Webhook credentials take precedence over unused bot/app credentials.

Boss HTTP validation wording, text content types, field order, lenient non-string
name/role handling, and original trimming rules are restored. IDs use the schema
default (32 lowercase hex), with both external-account writes in the same batch.
POST identity conflict text 409 is an intentional improvement over the parent's
uncaught 500. PATCH conflicts retain the parent's 500 and roll back the batch.
Existing JSON admin-denial responses are unchanged. Both preference write paths
now use the same validator to reject removed keys and validate quiet hours.
Valid merges prune removed stored keys. The CLI restores timezone-only empty
updates and suppresses preference lines after raw-string PATCH responses.

Source comparison against `37ce778` found all eight non-preference clap structs
and ten implementations byte-identical; retained quiet-hours payload construction
is also byte-identical. Defaults remain `add --role admin` and `inbox --limit 20`.
No Rust runtime test is claimed. `CARGO_DISK_GUARD_MIN_FREE_GB=1 cargo check -p hiboss`
failed before compilation because the configured `~/.cargo-target/hiboss/debug`
directory was outside the writable sandbox; Cargo check was not run to completion.
No alternate target-directory retry or formatter was used.

### Parent/current HTTP comparison (remote)

The actual router from `git show 37ce778:server/src/routes/bosses.ts` was loaded
beside the fixed router on `the Linux build box`. The harness reset each fixture
before each request and compared status, content type, and response body. Only
random creation IDs/timestamps and issued token values were normalized; creation
IDs were separately checked against `^[0-9a-f]{32}$`. All eight existing endpoint
shapes, prefix lookup, validation order, admin mutations, viewer reads, and viewer
denials were covered. Removed preferences and POST conflict improvements are
intentional differences tested separately in the committed regression suite.

```text
$ ../node_modules/.bin/vitest run src/comparison-bosses.test.ts --reporter=verbose
PATCH /api/bosses/target {"role":"junk"} -> 400: parent=current
PATCH /api/bosses/target {"name":"Two","role":123} -> 200: parent=current
PATCH /api/bosses/target {"role":" admin "} -> 400: parent=current
PATCH /api/bosses/target {"preferences":{}} -> 200: parent=current
PATCH /api/bosses/target {"preferences":{"quiet_hours":{"timezone":"UTC"}}} -> 400: parent=current
Test Files  1 passed (1)
     Tests  43 passed (43)
```

For both routers, `role:"junk"` and `role:" admin "` return the exact text
`invalid role` with `text/plain; charset=UTF-8`. `name:"Two",role:123` updates
the name while retaining the role. Empty preferences return a raw `"{}"` string;
timezone-only quiet-hours objects return the same text requiring start/end.

Comparison source and original parent module are retained remotely under
`/tmp/hiboss-fix-2b-comparison-source/`; full output is
`/tmp/hiboss-fix-2b-comparison.log`. They are excluded from the full suite counts.
The initial harness had three fixture/normalization errors (missing access grant
and normalizing two denied responses as successes); these were corrected before
the 43-pass comparison. No product change was needed for those harness errors.

The full-suite reruns corrected old expectations that self preferences accepted a
removed key and PATCH identity conflicts returned 409. The conflict test now
checks the unchanged application-level JSON 500 envelope and retained ownership.
A subsequent assertion initially expected Hono's default text 500 instead of that
application envelope; it was corrected. Typecheck also caught an inferred optional
field in the new credential test table, fixed with an explicit record type.
An initial web command could not find `svelte-kit`; linking the already-installed
remote web dependencies resolved it without a dependency install.

Edited TypeScript/Rust files stay within 300 lines and functions within 50 lines.
Boss message, stream, access, and write-test sections were extracted to meet those
limits; existing route bodies were retained. The consolidated schema retains its
existing structure with targeted column/index additions rather than regeneration.
`result-audit-2b.md` was already staged when this round began and remains byte-for-byte
unchanged; `result.md` is also unchanged. HiBoss panel delivery remains unavailable
because the CLI cannot resolve this execution's session.

## Delivered behavior

- Migration 0041 adds external accounts, backfills both legacy identity columns,
  and adds canonical target keys plus `merged_into` delivery references. It leaves
  `messages`, `channel_configs`, and `delivery_queue` unchanged.
- Shared external targets have one adapter call and one retry claim. Merged rows
  retain boss attribution and copy canonical status/external receipt. Earliest due
  time wins when quiet-hours settings differ; destination ID breaks ties.
- Telegram topics and Discord threads stay distinct. Discord bot thread IDs are
  effective channel IDs; webhook base-channel configuration is ignored because
  the webhook itself fixes the base channel. Shadow compares fingerprint sets
  and never sends through the destination path.
- Own-account CRUD and admin account management enforce ownership, uniqueness,
  and viewer read-only access. Telegram and signed Discord interactions prefer
  the new identity table. Existing admin identity edits synchronize both stores;
  account deletion clears a matching legacy fallback.
- Notifications replaces Channels in navigation. The old route remains available.
  Four locales cover destination CRUD, controls, provider creation, and probe hints.
  Provider credentials are write-only; managers receive safe provider choices.
- Explicit probes require `on`, ownership, and a non-viewer role. They bypass
  destination preferences and create no message. Native live streams have no push
  adapter, so their test control remains disabled with an explanation.
- Removed the unused preference controls and CLI flags. Quiet hours remain.
  Small-screen shell styles prevent the fixed sidebar from squeezing the new page.

## Original phase 2b checks (historical, before the FIX round)

All Worker suites and browser interaction checks ran on `the Linux build box`
in `/tmp/hiboss-phase2b-5uTm2n`. The other authorized hostname did not resolve.
The requested Wrangler file was copied before testing; Vitest explicitly injects
`DESTINATIONS_MODE=off`, and mode-specific tests inject their own values.

| Check | Result |
| --- | --- |
| `cd server && npm test` — Worker pool | 854 passed, 77 files |
| Same command — schema/backfill pool | 15 passed, 4 files |
| `cd server && npm run check:schema` | 42 migrations through 0041; 36 tables, 99 indexes |
| `cd server && npm run typecheck` | Passed |
| `cd web && npm run check` | 0 errors, 0 warnings |
| `cd web && npm test` | 129 passed, 16 files |
| `cd web && npm run build` | Passed |
| `cd cli && cargo check` | Passed locally; no formatter run |
| Remote Playwright control, creation, and permission scenarios | 3 scripts completed without assertion failures |

The initial archive transport included macOS metadata files that Vitest tried to
parse as source. Those files were removed from the isolated remote checkout; the
reported final run excludes them. Local Cargo used `CARGO_TARGET_DIR` under `/tmp`
and direct Clang after the ambient sccache compiler wrapper failed in the sandbox.

The original browser checks used the real Svelte page with isolated HTTP fixtures. They covered
shadow/on probe gating, enabled/priority/quiet-hours changes, destination creation
and deletion, provider creation and secret-field clearing, four locales, viewer
restrictions, manager provider visibility, desktop layout, and 390px mobile layout.
The mobile document width equals its 390px viewport after the responsive fix.
Real authenticated Worker/D1 tests separately cover API behavior and signed inbound
Discord identity precedence. Live Telegram/Discord/APNs delivery and the production
parity week were not exercised.

## Evidence locations

Remote logs are `/tmp/hiboss-phase2b-server-final.log`,
`/tmp/hiboss-phase2b-schema-final.log`, `/tmp/hiboss-phase2b-types-final.log`,
`/tmp/hiboss-phase2b-web-check-final.log`, `/tmp/hiboss-phase2b-web-test-final.log`,
and `/tmp/hiboss-phase2b-web-build.log` on `the Linux build box`.
Local Cargo output is `/tmp/hiboss-phase2b-cargo.log`.

Screenshots are under the remote checkout's `output/playwright/`:
`notifications-desktop.png`, `notifications-mobile.png`, and `notifications-viewer.png`.
The three browser scenario sources and logs are remote `/tmp/hiboss-phase2b-browser-`
`controls.js/.log`, `forms.js/.log`, and `permissions.js/.log`; fixtures are in
`/tmp/hiboss-phase2b-browser-setup.js`. These are host-local artifacts, not public URLs.

New source modules stay within 300 lines. Existing large dashboard/schema artifacts
retain their structure with targeted deletions/additions; the CLI argument and boss
preference test extractions bring those edited code files within the limit.
HiBoss panel delivery was unavailable because this execution had no resolved session.
