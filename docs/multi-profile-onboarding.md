# Multi-device, multi-profile onboarding — contract

KB consulted: `an-agents-isolated-home-carries-a-different-git-identity`,
`passthrough-symlink-sandbox-records-ephemeral-paths`. Lesson applied: a rule that lives in
`$HOME` does not reach a sandboxed agent, and a symlinked sandbox makes tools record ephemeral
paths. Identity therefore travels through env vars or is derived from the repository. It never
comes from a path recorded under `$HOME`.

## Problem (measured on `main@a8c18e9`)

| # | Observation | Evidence |
|---|---|---|
| 1 | Every runtime and project on a machine uses one agent key. Nothing tells Claude, Codex, a dispatched agent or a second machine apart. | `cli/src/config.rs:31`; `server/schema.sql:255` |
| 2 | The CLI has no env override. A clean `$HOME` finds no config. A symlinked `$HOME` (aid) finds the operator's config and silently acts as the operator. | `config.rs:38-42` |
| 3 | The session file is `/tmp/hiboss-session-<hash(project_dir)>`, shared by every runtime and concurrent session in a checkout. SessionStart deletes every marker in it. | `session.rs:117`; `hook_start.rs:30` |
| 4 | A dispatched headless agent inherits Claude Stop hooks that block on `hiboss ask`. | ai-dispatch `src/agent/grok.rs:39` works around this |
| 5 | `init` names the agent `$USER`. A second machine collides and gets a 409, but only at approval time, after a 5-minute poll. It never sends the bootstrap secret. | `init.rs:167`; `boss-join.ts:31` |
| 6 | `setup hooks --global` writes `$HOME/.claude/settings.json` and ignores `CLAUDE_CONFIG_DIR`. | `setup_hooks.rs:32` |
| 7 | The CLI writes `{server,key}` under `dirs::config_dir()`. The MCP configure skill writes `{server_url,api_key}` to `~/.config`. On macOS the CLI does not read that file. | `mcp/server.ts:221`; `mcp/skills/configure/SKILL.md` |
| 8 | The removed boss-creation command sent an agent key to a boss-only route and failed. | `cli/src/client/bosses.rs` |
| 9 | A Mac boss client cannot redeem a pairing code. Only an admin can issue one. The documented token route revokes every other device. | `pairing.ts:45`; `bosses.ts:212` |
| 10 | Project aliases include the cwd basename, so worktree directories alias unrelated repos and cross-agent merges fail with 409. The hook hides the failure. | `project.rs:28`; `projects/index.ts:51` |

## Decisions

- **One agent per runtime profile.** Name format: `<user>-<profile>@<host>`, for example
  `alice-claude@macbook`, `alice-codex@macbook`, `alice-aid@macbook`.
- **Device grouping.** All profiles created in one join request share a `device_id`. The boss
  approves the device once and every profile in it is approved together.
- **Dispatched agents attach to their parent session and never block.** They may `send`,
  `progress` and update panels. `ask` and blocking Stop behaviour are refused with an
  actionable message.

## Config v2 (CLI and MCP read the same file)

Path: `$HIBOSS_CONFIG` if set, else `dirs::config_dir()/hiboss/config.json` (macOS:
`~/Library/Application Support/hiboss/config.json`). Mode 0600.

```json
{
  "version": 2,
  "server": "https://hiboss.example",
  "device_id": "d_…",
  "default_profile": "claude",
  "channel": null,
  "profiles": {
    "claude": { "key": "hb_…", "agent_id": "…", "name": "alice-claude@macbook" },
    "codex":  { "key": "hb_…", "agent_id": "…", "name": "alice-codex@macbook" },
    "aid":    { "key": "hb_…", "agent_id": "…", "name": "alice-aid@macbook", "server": "optional override" }
  }
}
```

The loader rewrites a v1 file (`{server,key,channel}`) once into
`profiles.default` + `default_profile: "default"` and saves it. The reader then knows only v2.
There is no v1 code path after the rewrite and no `server_url`/`api_key` aliases.

### Credential resolution (first match wins)

1. `HIBOSS_SERVER` + `HIBOSS_KEY`: ephemeral, no file touched. One without the other is an
   error naming the missing variable.
2. `HIBOSS_PROFILE=<name>`: that profile. If it is missing the CLI exits 3 with
   `profile '<name>' is not set up; run: hiboss setup --profile <name>`.
3. **Detected runtime** (table below): the profile with that name, if present.
4. `default_profile`.

`hiboss whoami` (and `--json`) prints the resolved profile, the source rule (1–4), agent
name, server, config path and runtime. Every friendly error names the rule that was used.

### Runtime detection (env only, first match wins)

| Runtime | Signal | Per-session id |
|---|---|---|
| `aid` (dispatched) | `AID_TASK_ID` non-empty | `AID_TASK_ID` |
| `claude` | `CLAUDECODE=1` | `CLAUDE_CODE_SESSION_ID` (measured: exported to child processes) |
| `codex` | unverified; not detected | unverified |
| `gemini` | unverified; not detected | unverified |
| none | — | — |

The `aid` check runs first: a dispatched Claude agent is a dispatched agent before it is a
Claude agent. Unverified signals are reported as unverified. Nobody guesses them.

## Session identity

- State directory: `<cache_dir>/hiboss/sessions/<project_key>/<leaf>/`, where `<cache_dir>` is
  the user's cache directory (`~/Library/Caches` on macOS, `$XDG_CACHE_HOME` or `~/.cache` on
  Linux). `project_key` is the FNV-1a hash of the canonical **git common dir** (the project
  directory outside a repository), so the main checkout and all its worktrees share it.
  `<leaf>` is `<hex(profile)>-<hex(session_key)>`: the lowercase hex of each part's UTF-8
  bytes, untruncated. Hex contains no `-`, so the separator is unambiguous and two distinct
  pairs never share a directory. `profile` is the resolved credential profile (`environment`
  under rule 1, `unconfigured` when none resolves), so two profiles in one checkout never share
  a session file. `session_key` is the per-session id from the table, falling back to
  `default` when the runtime exposes none. A leaf longer than 200 bytes is refused. Missing
  directories are created 0700; existing ones are used as they are. The leaf must be a real
  directory (not a symlink) owned by the caller. If it cannot be created or fails that check,
  the CLI prints one warning and runs without session state: `send` and `progress` go out
  unscoped, and hooks neither register nor start a daemon. Every state file is opened without
  following symlinks and used only if it is a regular file owned by the caller; anything else
  is refused with one warning naming the path, and is never truncated. Writes go to a fresh
  0600 file renamed into place. The session id, markers, read queue, daemon pid/spool/log and
  panel epochs all live there. The daemon's pid file is written before the listener is
  spawned, and a listener whose pid cannot be recorded is killed. SessionStart clears only its
  own directory's session markers. `$TMPDIR` and the old `/tmp/hiboss-*` files are not read.
- `POST /api/sessions` gains optional fields: `host` (short hostname), `runtime`,
  `parent_session_id`, `dispatch_ref` (e.g. the aid task id). The CLI sends `host`, `runtime`
  and, for `aid`, `dispatch_ref` and `parent_session_id` when a parent is found.
- **Foreign session self-heal:** when `send`, `ask`, a broadcast or `progress post` gets an HTTP
  400 whose body is exactly `session does not belong to calling agent`, the CLI registers a
  fresh session for the current profile in the current state directory, restarts the session's
  daemon if one is running (so its SSE subscription uses the new id), prints one line saying
  so, and retries the call once.
- **Parent lookup for a dispatched agent:** in the same `project_key`, take the most recently
  touched non-dispatched session directory. If there is none, register without a parent.
  Each registration writes a `runtime` file next to `session`; a directory counts only when
  that file names a runtime other than `aid`, and "touched" is the `session` file's mtime. A
  `parent_rejected: true` response prints one warning on stderr; registration still succeeds.
- **Server rule for `parent_session_id`:** accepted only if the parent session's agent has the
  same `device_id` as the caller. Otherwise the field is dropped and the response carries
  `parent_rejected: true`, so a foreign agent cannot claim a parent.
- **Project identity:** derived from the repository: the remote URL's repo name, else the
  repository name: for a checkout whose common dir is `.git`, the basename of its parent; for a
  bare repository (`core.bare` true, or a common dir not named `.git`), the common dir's own
  basename minus `.git`. It is never the worktree directory basename, and the
  worktree basename is not sent as an alias either.
  The registration error is printed on stderr from hooks instead of being swallowed.
- **Display label:** `<project>/<branch> · <host> · <runtime>` in clients. A dispatched
  session nests under its parent where the client lists sessions.

## Dispatched mode (`runtime == aid`)

- The Stop hook exits 0 without requiring a report or `ask`. It does not park the session as
  waiting; it only stops the session's SSE daemon.
- `hiboss ask` exits 4 with:
  `dispatched agents cannot ask the boss; return the question to your dispatcher`.
- `send`, `progress`, `panel *` work, attributed via `dispatch_ref` + parent.

## Join with device grouping (server, security-sensitive)

`POST /api/join`
```json
{ "device": { "label": "macbook", "host": "macbook.local" },
  "profiles": [ { "profile": "claude", "name": "alice-claude@macbook" },
                { "profile": "codex",  "name": "alice-codex@macbook" } ] }
```
- Rejects up front with 409 and the conflicting names when any requested name already belongs
  to an agent. A name held only by another pending request is caught at approval: 409, and
  nothing is created. The CLI prints the 409 immediately. Without a live invite (when one is
  required) the 403 comes before the name check, so names cannot be probed.
- Nothing skips approval. On an empty server (no agents yet), a configured `BOOTSTRAP_SECRET`
  and a matching `X-Bootstrap-Secret` stand in for an invite; without a configured secret the
  join gets a 403. The request is still pending until a boss approves it, so the first boss
  comes from `POST /api/bootstrap/boss` and pairing. The CLI sends the secret from
  `--bootstrap-secret` or `HIBOSS_BOOTSTRAP_SECRET`.
- Approval creates every profile's agent atomically under one new `device_id`. The join
  response itself is always `pending`.
- `GET /api/join/status` returns
  `{status, device_id, profiles: [{profile, name, agent_id, key}]}`. The keys are delivered once.
- Adding a profile to an existing device: `POST /api/join` with an `X-Device-Proof` header
  (an existing key of that device). The new profiles join that `device_id`, still after
  approval.

## Invites and verification codes

- `POST /api/devices/invites` (agent key) returns a single-use `hb_inv_…` invite. It lasts
  30 minutes, and an agent can hold at most 5 active invites. Only the invite's hash is
  stored, together with the inviter's device label (or agent name).
- After the first agent exists, `POST /api/join` needs either a live invite or an
  `X-Device-Proof`; without one it returns 403. Taken names are checked first, so a 409 does
  not spend the invite.
- Every join request gets a 6-digit `verification_code`. The joining machine
  prints it. Telegram, Discord, the APNs push (category `HIBOSS_JOIN_REQUEST`, key
  `join_request_id`) and `GET /api/boss/join-requests` all show it next to the inviter label.
  An invite never skips approval.
- `hiboss device invite [--copy]` prints a self-contained prompt for the new machine: install
  the CLI if missing, run `hiboss setup --server … --invite …`, report the code, and wait.

## Agent onboarding: `hiboss setup`

```
hiboss setup [--server <url>] [--invite <invite>] [--profile <p>]... [--label <label>] [--bootstrap-secret <s>] [--wait <seconds>] [--abandon] [--check] [--yes]
```
1. Resolve the server from a flag or config; otherwise require `--server <url>`.
2. Detect installed runtimes on PATH (`claude`, `codex`, `gemini`, `aid`). Propose one profile
   for each. `--profile` overrides.
3. Pass the invite with `--invite`, send one grouped join, show
   a single approval prompt, and poll. A 409 lists conflicting names and suggests
   a distinct `--label`. `hiboss device invite` uses the active profile to mint an invite.
   The poll token waits in an owner-only `pending-enrollment.json` beside `config.json`, so a
   wait timeout (`--wait`, 30 minutes by default) or Ctrl-C leaves the request resumable: the next
   `hiboss setup` keeps polling without a new join or invite, and `--abandon` discards the file.
4. Per profile:
   - claude: install hooks into `${CLAUDE_CONFIG_DIR:-~/.claude}` with `HIBOSS_PROFILE=claude`
     on every hook command.
   - codex: write AGENTS.md guidance into `${CODEX_HOME:-~/.codex}`.
   - gemini: write `~/.gemini/GEMINI.md` guidance.
   - aid: no hooks; dispatched mode applies.
5. `--check`: verify each configured profile with `GET /api/agents/me`. Print a
   PASS/FAIL table. Exit non-zero on any FAIL.

`setup` replaces the removed `init` command. Boss management operates on existing
bosses; `boss add` is removed.

## Boss device onboarding

- **Pairing issuer:** `admin` and `manager` may create pairing codes. The redeemed device
  receives the issuer's role or a lower one, never higher.
- **macOS:** the first-run screen offers *Pair with code* first: paste a `hiboss://pair?…`
  link or server + code. The app registers the `hiboss://` URL scheme so a clicked link opens
  the redeem sheet. *Use a Boss Token* stays as the secondary path.
- **iOS:** Settings gains *Pair another device*, which issues a code and shows the QR,
  observing redemption like the Mac sheet.
- **Docs:** the token-minting route is documented only as "rotate: revokes every token of
  this boss".

## Known properties

- A device proof is checked when the request is created. Revoking the proving key afterwards
  does not withdraw a pending request; the approver still has to approve it.
- Approved keys wait in plaintext in `join_requests.delivery` until the first poll, which clears
  them. A request that is approved but never polled keeps them.
- The active-invite cap is a count-then-insert, so concurrent mints can briefly exceed it.

## Not covered by this contract

Binary distribution (installer, Homebrew), Telegram/Discord approval card layout beyond listing
profile names, and camera QR scanning on macOS.
