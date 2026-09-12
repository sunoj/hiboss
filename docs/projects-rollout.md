# Projects rollout — phases 3a and 3b

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
Old session registration derives an alias from the explicit label prefix or cwd basename.
New sessions without a resolvable project return 400; ID-only re-registration retains
an existing project link. Heartbeats cannot update unlinked sessions. An explicitly supplied legacy label is retained in storage; session listing derives
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
Home, feeds and profile lists use project FKs exclusively. Unlinked historical posts
are excluded from these surfaces; inspect and repair null links before rollout.

Messages and progress reject missing or foreign `session_id` values with 400.
Old CLIs with stale local session markers must register a fresh session before
sending again. Sessions are not auto-created by message/progress requests.

## Phase 3b surfaces and migration

Phase 3a is already deployed (reported inventory: 118 projects, 128 aliases, all
session/post/route links backfilled). This change is local implementation only.
Apply `0044_project_surfaces.sql` before deploying the 3b Worker. Back up D1 first.
The guard `missing_team_project` requires every snapshot team's exact alias to
resolve to an existing project before dropping `progress_teams`.

The old `progress_posts.project` constraint forbids omitted text, so 0044 rebuilds
that table with a nullable text field and preserves every post column, like and
index. Both project FK columns remain nullable in SQL; API registration/post writes
require a resolved project. New posts write only `project_id`. Destination route
matching and the unique scope index now use `project_id`, with session-specific
routes preceding project routes and default routes. Runtime route writers are absent;
future route writes must supply IDs, never text. `DESTINATIONS_MODE` is unchanged.

Before applying, verify these queries return no rows:

```sql
SELECT t.project FROM progress_teams t WHERE NOT EXISTS (
  SELECT 1 FROM project_aliases a JOIN projects p ON p.id = a.project_id
  WHERE a.alias = t.project
);
SELECT destination_id, project_id, session_id, COUNT(*) FROM destination_routes
GROUP BY destination_id, COALESCE(project_id, ''), COALESCE(session_id, '')
HAVING COUNT(*) > 1;
```

Resolve duplicate route scopes deliberately before migration: the new unique index
rejects them. Explicit runtime merges keep the target route on conflicting scopes;
otherwise the smallest route ID wins among absorbed routes. All relationship moves,
conflicting-route removal, project deletion and `project.merge` audit share one batch.
The target profile is retained. `progress_posts.project` and
`destination_routes.project` remain as historical text and will be dropped in a
later phase. Do not roll back to a Worker that writes the dropped team snapshot.

`GET /api/boss/projects` returns `{ projects: [...] }`, with `id`, `slug`,
`display_name`, `repo_url`, sorted `aliases`, `session_count`, `last_seen_at` and
`last_post_at`. Counts/timestamps reflect accessible agents. Admins see all projects;
other bosses see projects with accessible activity or an accessible creator.
`PATCH /api/boss/projects/:id` accepts `display_name`, `repo_url` (HTTP(S) or null),
or a separate `{ "merge_into": "target-project-id" }` operation. Viewers cannot
mutate; both merge identities must be visible. Profile edits have boss audit entries.

`GET/PUT /api/progress/teams/:project` resolves slug or alias and reads/writes
`projects`; the old table is never accessed. Profiles remain shared without a project
ACL. `POST /api/projects/:project/aliases` accepts `{ "alias": "old-checkout" }`;
`DELETE /api/projects/:project/aliases/:alias` removes it. Adding another project's
alias returns 409 rather than implicitly merging. Removing the canonical slug alias
returns 400. Existing resolver reconciliation for CLI identity assertions is retained.

Agent progress responses retain `project: "slug"` because installed old CLIs decode
that field as a string. Boss progress responses expose
`project: { "id": "...", "slug": "...", "display_name": "..." }`. Both come from the
same FK join. Request text compatibility is unchanged. Session listings expose
`project_id` and `project_slug`; the boss listing's `include_inactive=true` also
returns historical sessions within the same access scope for native History headers.

The console Projects page lists aliases/activity and supports display-name edits and
confirmed merges in English, Chinese, Japanese and Korean. Agents/Sessions show slugs.
HibossKit decodes project objects and sessions; iOS groups the project filter across
agents by slug, permits null last-post timestamps and keys Home cards by slug.
macOS History reads session inventory for canonical `slug/branch` titles.

Use `hiboss project show`, `hiboss project set --display-name NAME --bio BIO
--avatar PATH`, and `hiboss project aliases add/remove ALIAS [--project SLUG]`.
`hiboss progress team` is a hidden alias with a deprecation notice; its old
`register` and `set-avatar` forms remain accepted. `show` reads the canonical server
profile. `set` preserves unspecified server fields; `.hiboss/team.json` sync still
targets the same project profile and retains its existing hash format.

Agent-qualified local session slots, removal of `api_keys.session_info`, and removal
of stored labels remain deferred. Messages, app installation, production deployment,
remote migrations, pushes and PRs are outside this implementation.

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

### Phase 3b verification (2026-09-12)

The full remote `npm test && npm run check:schema && npm run typecheck` passed:
**908 API tests and 18 schema tests**, including the two SQLite 0044 preservation/
guard fixtures. Schema parity: **45 migrations, 37 tables, 106 indexes**.
Remote console `npm run check && npm test` passed with **132 tests**, zero check
errors/warnings; **4 Playwright browser flows** passed (rename/confirmed merge,
four locales, mobile overflow, and viewer restrictions).

The isolated checkout is `grok-bot-twitter:/tmp/hiboss-projects-3b-20260912`.
Remote logs: `/tmp/hiboss-3b-{server,schema,server-typecheck,web-check,web-test,web-e2e}.log`.
Screenshot: `web/output/playwright/projects-mobile.png` in that remote checkout.
These are host-local artifacts, not hosted links. An initial SSE timeout passed on
rerun. Remote disk exhaustion was recovered using identical existing compiler/runtime
packages and clearing this task's interrupted Vite cache; other jobs were untouched.

Local CLI tests passed **223 tests** (221 library + 2 command-parser tests) with
`RUSTC_WRAPPER` unset and target `/tmp/hiboss-projects-3b-cargo`.
Ten obsolete tests were removed with the unused client-side handle normalizer;
project profile defaults now come from the server.
Log: `/tmp/hiboss-3b-cli.log`. No Cargo formatting command was run.

Local HibossKit passed **134 tests** (133 XCTest + 1 Swift Testing); macOS passed
**128 tests** with `E2E|AttentionLayoutTests` excluded and `swift build` passed.
Project-inventory failures are isolated from existing message-history behavior.
iOS simulator app build and `build-for-testing` both passed; iOS tests were compiled,
not executed. No native app or test runner was installed or launched.
Local logs: `/tmp/hiboss-3b-{kit,macos-tests,macos-build,ios-build,ios-test-build}.log`.
Changed Swift/Rust/TypeScript/UI source files stay within 300 lines; the consolidated
SQL schema retains its existing structure with targeted edits.
HiBoss panel delivery was unavailable because this execution had no resolved session.
No production migration, deployment, live message delivery, push or PR was performed.
