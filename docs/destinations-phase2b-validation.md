# Destinations phase 2b validation

Implemented on `feat/destinations-console`; local commit only. No deployment,
remote migration, production mode change, push, or PR was performed.

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

## Checks and actual counts

All Worker suites and browser interaction checks ran on `root@grok-bot-twitter`
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

Browser checks used the real Svelte page with isolated HTTP fixtures. They covered
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
and `/tmp/hiboss-phase2b-web-build.log` on `grok-bot-twitter`.
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
