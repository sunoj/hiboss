# Projects rollout — phase 3a

Phase 3a adds project identity to the server and CLI. Apply `0043_projects.sql`
before deploying this Worker, then upgrade CLIs. Server-first is recommended, but
either CLI/server upgrade order is safe: new CLIs retain the old text wire field.
This change does not deploy itself.
`DESTINATIONS_MODE` remains unchanged, including the deployed `shadow` setting.
No message columns or historical message rows are migrated. `boss_devices` is unchanged.

## Migration and verification

Back up D1 before applying the migration. The migration first checks duplicate
`api_keys.name` values and fails with `duplicate_api_keys_names` if any exist.
Resolve actual duplicate identities deliberately; the migration never picks a winner.
A unique index then enforces names. Exact agent names take precedence over ID prefixes
in `send --to`; the existing prefix path remains available.

Each distinct nonempty team name, post project, or session label prefix becomes a
project and an exact, case-sensitive alias. Labels without `/` use the entire label.
Empty and ASCII-space-only values are skipped. Slugs are lowercase ASCII letters, digits,
underscores and dashes; runs of punctuation become one dash. Distinct legacy values
that normalize to the same nonempty slug are merged, matching runtime grouping.
Backfill-generated `--<UTF-8 hex>` collision slugs remain registered as aliases,
including those of absorbed projects. Empty normalized slugs use
`project--<UTF-8 hex>` and remain distinct. Runtime ASCII normalization is tested
against the migration SQL on the same inputs, including Unicode edge cases.
If a generated slug exceeds 256 characters, use a short random identity suffix
instead; the original name remains an alias. A literal historical alias matching
a generated slug joins that identity, so both spellings remain usable.

The backfill also merges a session label-prefix project with a progress-text
project when a post from the same agent names the basename of that session's
`cwd`. The session label is the historical origin name; trailing path separators
are ignored. Connected rename chains merge together, preferring an origin-side
identity, then the oldest project (slug and ID break ties). Different agents'
cwd/post coincidences alone do not establish equivalence. Sessions, posts, routes
and aliases all move together; `audit_log` records `project.merge` and absorbed IDs.

Team profiles retain handle uniqueness, display name, bio, avatar URL, creator and
timestamps. Other projects start without a handle and use generated avatars.
Creator remains attribution, not project ownership: any authenticated agent can
update a project profile, as with the former team endpoint. Existing boss/agent
access controls still scope feeds and Home; there is no project ACL.

Sessions and posts link through aliases. Routes first use their text project alias,
then their session's project when no text alias exists. Route-only text names do not
create projects during backfill. Empty or unknown historical relationships may stay
null. The old text columns retain their stored values.

Useful post-migration inspection queries:

```sql
SELECT name, COUNT(*) FROM api_keys GROUP BY name HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM projects;
SELECT source, COUNT(*) FROM project_aliases GROUP BY source;
SELECT COUNT(*) FROM sessions WHERE project_id IS NULL;
SELECT COUNT(*) FROM progress_posts WHERE project_id IS NULL;
SELECT COUNT(*) FROM destination_routes WHERE project_id IS NULL;
PRAGMA foreign_key_check;
```

## Old and new clients

Old progress clients may continue sending `project: "checkout-name"`. The server
resolves that text as an alias and auto-creates an identity when it is unknown.
An omitted progress project still uses the agent name, through the same resolver.
Old session registration derives an alias from the label prefix; registration with
only an ID can stay unlinked. An explicitly supplied legacy label is retained in storage; session listing derives
the displayed label from the linked slug and branch.
Both endpoints also accept:

```json
{
  "project": "hiboss",
  "project_identity": {
    "slug": "hiboss",
    "aliases": ["hiboss", "renamed-checkout"],
    "display_name": "HiBoss",
    "repo_url": "https://github.com/sunoj/hiboss"
  }
}
```

The new server prefers `project_identity` when present, otherwise legacy text.
Old servers ignore `project_identity` and receive the text slug in `project`.
An alias match wins over an unknown requested slug. Otherwise the canonical or
normalized slug can match an existing project, or the server creates one.
All supplied aliases, including the raw and canonical slug, are registered atomically.
When aliases identify several projects, merge into the one whose alias matches the
presented slug, otherwise the oldest (ID breaks timestamp ties). Repoint sessions,
posts, routes and aliases, delete absorbed projects and record their IDs in
`audit_log` as `project.merge`, in the same D1 batch. The winning project's profile
is retained; historical team profiles remain available in the migration snapshot.
Concurrent first sightings retry identity resolution;
failed batches leave no orphan projects or partially registered alias sets.
Optional display name and repository URL initialize a new project; subsequent
profile changes use `PUT /api/progress/teams/:project`.
Text and object aliases are nonempty, at most 256 characters and contain no C0/C1
control characters. Objects accept at most 32 additional aliases, display names
up to 256 characters and repository URLs up to 2048. Team updates use the same
alias and display-name limits. Duplicate agent names return HTTP 409 text from
key creation, boss join approval and Telegram/Discord callback approval.

The new CLI uses the origin repository basename, stripping `.git`, as its slug;
it falls back to the resolved checkout directory basename. Aliases include origin,
checkout, and nonempty `HIBOSS_PROJECT`. `--project` supplies an explicit slug and
alias; it is a grouping assertion, not an unconditional redirect. If checkout
aliases identify an existing project, an unknown explicit slug joins that project.
If both already exist, the presented-slug identity wins the merge.
The working directory resolves through `HIBOSS_PROJECT_DIR`, Git root, then cwd,
so subdirectory invocations remain consistent. Session registration sends the full
resolved directory path and a `slug/branch` label. `hiboss ss` displays that label;
`send --to` accepts it and the retained legacy label, both exactly and by prefix.
Hooks and progress share the same resolver. `.hiboss/team.json` and its sync hash
remain supported; the same endpoint now writes the project profile.

Projects listing includes accessible session-only projects with zero posts and a
null last-post timestamp. Progress filtering accepts aliases or canonical slugs.
Home and feeds use the project FK, falling back to legacy text only for unlinked
rows; unlinked posts can still obtain a project profile through their text alias.

Messages and progress reject missing or foreign `session_id` values with 400.
Old CLIs with stale local session markers must register a fresh session before
sending again. Sessions are not auto-created by message/progress requests.

## Phase 3b cleanup

`progress_teams` is an application-level read-only migration snapshot: this Worker
never writes it. It is retained for inspection until 3b; no database triggers prevent
an operator or an older Worker from modifying it. Avoid rolling back to a Worker
that writes the snapshot after project profiles have changed.

Drop `progress_teams` and legacy project text columns only in 3b, after all deployed
readers/writers use project IDs, remaining null links are reviewed, and destination
route readers/writers have adopted IDs. Keep the legacy JSON text input adapter as
long as old CLIs remain installed; accepting text does not require a text DB column.
Destination routing still uses its current text/session semantics in 3a. The new
route FK is additive backfill only; phase 3b owns route identity cutover.

Agent-qualified local session slot keys, removal of `api_keys.session_info`, and
removal of stored labels are also deferred. Keep project aliases: they are the durable
record of renamed checkouts, not a temporary migration shim. Reconciliation is
automatic in the shared resolver and backfill; there is no separate merge API.

## Validation

Run Worker/API E2E tests only on an authorized grok box in an isolated checkout.
Copy the approved `server/wrangler.toml` before tests. Required commands are
`npm test`, `npm run check:schema`, and `npm run typecheck` in `server`.
The schema test runner includes six SQLite migration fixtures for profiles,
labels, posts, routes, slug collisions, message preservation, aliases and unique names.
CLI validation uses `env -u RUSTC_WRAPPER cargo check -p hiboss` and
`env -u RUSTC_WRAPPER cargo test -p hiboss`,
with `CARGO_DISK_GUARD_MIN_FREE_GB=1`; an isolated writable Cargo target is supported.

Verified on 2026-09-12: **891 Worker/API tests and 16 schema tests passed** on
`grok-bot-twitter`, including all four project backfill fixtures. Schema parity
reported 44 migrations, 38 tables and 109 indexes; server typecheck passed.
Local Cargo check passed and all **8 session/resolver tests passed** (221 unrelated
tests filtered), using `/tmp/hiboss-projects-cargo` because the configured shared
Cargo target was outside the writable sandbox. Disk space was sufficient.
Remote log: `/tmp/hiboss-projects-final-tests.log`; isolated checkout:
`/tmp/hiboss-projects-3a-20260912`. These are host-local artifacts, not public URLs.
Final focused verification after test-file extraction: **108 API tests passed**;
server typecheck passed. Log: `/tmp/hiboss-projects-final-focused.log`.
No production migration, deployment, live delivery smoke test, push, or PR was run.

### FIX round verification (2026-09-12)

The final remote suite passed with **902 API tests and 17 schema tests**, including
six SQLite backfill fixtures and the normalization parity test. The required
`npm test && npm run check:schema && npm run typecheck` completed successfully;
schema parity reported 44 migrations, 38 tables and 109 indexes. Logs remain on
`grok-bot-twitter` at `/tmp/hiboss-fix-3a-{server,schema,typecheck}-final.log`;
the isolated checkout is `/tmp/hiboss-fix-3a-20260912`.

Local Rust validation passed **231 tests** and `cargo check -p hiboss`, with
`RUSTC_WRAPPER` unset. Logs: `/tmp/hiboss-fix-3a-rust-test.log` and
`/tmp/hiboss-fix-3a-rust-check.log`. The wire fixture rejects object-valued legacy
`project` fields and accepts both new progress and session payloads.
HiBoss panel delivery was unavailable because this execution had no resolved session.
