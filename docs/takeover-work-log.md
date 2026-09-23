# Takeover work log

## 2026-09-22: Baseline recovery and SAFE-01

Source baseline: `38c8570`. Changes remain in the working tree; no merge,
deployment, installed-client replacement, or production migration was performed.

### Completed in this batch

- Converted the takeover roadmap and its navigation entries to English.
- Recorded the working-language requirement in root AGENTS.md.
- Provisioned isolated Rust 1.90.0, Bun 1.2.22, and Python 3.12.11 under
  `/private/tmp/hiboss-toolchains`; no shell-profile changes or system Python replacement.
- Implemented CLI `ask --json` outcomes and explicit default markers. Automatic
  defaults and unconfirmed local fallbacks do not expose an action command.
- Added MCP structured ask outcomes and default markers in ask, channel, inbox,
  and search output, preserving verification before formatting.
- Corrected misleading documentation and help that claimed ask executes actions.
- Added Rust and Bun regression tests; see [the outcome contract](ask-outcomes.md).

### Validation evidence

| Check | Result |
| --- | --- |
| `cargo test --manifest-path cli/Cargo.toml --locked ask` | 45 passed, 0 failed; filter also matches panel task tests |
| `cargo test --manifest-path cli/Cargo.toml --locked --offline --quiet` | 234 library tests and 2 binary tests passed; 0 failures |
| `bun test mcp` | 10 passed, 0 failed; 25 assertions across 3 files |
| `sh server/scripts/check-schema.sh` with isolated Python on PATH | Matches 46 migration files through 0045; 38 tables, 109 indexes including implicit indexes |
| `git diff --check` | Passed |

The initial full CLI run inside the session sandbox had 9 failures, all from
localhost mock-server binding being denied. The approved unsandboxed rerun passed
all 236 tests. This is an execution-environment restriction, not a product test
failure. The initial Python 3.9 schema error was resolved by running the unchanged
checker with isolated Python 3.12.

Reproduce without changing shell profiles:

```sh
RUSTUP_HOME=/private/tmp/hiboss-toolchains/rustup \
CARGO_HOME=/private/tmp/hiboss-toolchains/cargo \
/private/tmp/hiboss-toolchains/cargo/bin/cargo test --manifest-path cli/Cargo.toml --locked --offline --quiet

/private/tmp/hiboss-toolchains/bun-darwin-aarch64/bun test mcp

PATH=/private/tmp/hiboss-toolchains/python/cpython-3.12.11-macos-aarch64-none/bin:$PATH \
sh server/scripts/check-schema.sh
```

These temporary toolchains are machine-specific and may be removed by normal
system cleanup. Standard installations of the same tools can run the underlying
commands. Localhost network permission is required by some Rust tests.

### Task status and next gates

| Task | Status | Remaining gate |
| --- | --- | --- |
| BASE-01 | Pending operational evidence | Current Worker, D1, mode, installed versions, rollback inventory |
| QA-01 | Partial: CLI, MCP unit tests, schema verified | Server/full E2E in the documented authorized grok checkout; Web, panel-runtime, native baselines; MCP type/build/integration checks |
| SAFE-01 | Local implementation and regression checks complete | Code review before merge; client distribution and actual channel/poll integration verification |
| DEL-01 | Static inventory only | Shadow window, coverage, routing and queue evidence |

No authorized grok host alias or isolated directory was available in the project
context. The operator was asked for the current test environment. Full server/E2E
and live delivery were not run. M0 remains open; a passing schema comparison alone
does not establish production migration state or shadow parity.

### Compatibility notes

Automatic-default text output changes intentionally. Scripts consuming raw labels
must adopt the documented outcome contract. Ordinary reply text remains unchanged.
The `reply` outcome is not a claim of human authorship or authorization.

MCP currently has no default-option input, but returned system defaults are still
classified whenever present. CLI local fallback remains unconfirmed until the
server state is retrieved. No server response shape or expiry rule was changed.


## 2026-09-23: Open PR review and Web baseline

Reviewed all six open PRs returned by the GitHub API for `sunoj/hiboss`.
Remote `main` and local `main` both point to `38c8570a47a4c4d1b11c87e46a502d3bef5fd6cc`.
The existing uncommitted SAFE-01 and planning changes were preserved.

### PR disposition

Each PR contains one commit not reachable from `main`, but its complete target
module tree exactly matches an implementation commit already on `main`:

| PR | Module | PR head | Identical module on main | Disposition |
| --- | --- | --- | --- | --- |
| [#9](https://github.com/sunoj/hiboss/pull/9) | Messages | `0f58a16` | `3ab8a6d` | Closed as superseded; already implemented |
| [#10](https://github.com/sunoj/hiboss/pull/10) | Audit | `3994711` | `f0e0144` | Closed as superseded; already implemented |
| [#11](https://github.com/sunoj/hiboss/pull/11) | Routing table | `a710eb6` | `f0e0144` | Closed as superseded; already implemented |
| [#12](https://github.com/sunoj/hiboss/pull/12) | Routing writes | `d3e9006` | `b92a03d` | Closed as superseded; already implemented |
| [#13](https://github.com/sunoj/hiboss/pull/13) | System / Doctor | `34431cb` | `b92a03d` | Closed as superseded; already implemented |
| [#14](https://github.com/sunoj/hiboss/pull/14) | Groups writes | `724288d` | `b92a03d` | Closed as superseded; already implemented |

For each row, `git diff origin/pr/<number> <implementation-commit> --
web/src/routes/<module>` is empty. `git show --name-only` confirms that each
PR's unique commit modifies only that module. Later main commits add localization
(`0b5f177`) and message option media support/fixes (`75f1f6b`, `b65fe08`).
Preserve these later changes.

`git merge-tree --write-tree --name-only main origin/pr/<number>` reports
conflicts for all six heads. The GitHub API reports mergeability as unknown,
zero check runs, zero commit statuses, and zero reviews for every PR. An empty
status list is not a passing CI result.

No PR was merged or closed, and no remote branch was changed. There is no new
feature to recover from these heads. GitHub CLI authentication and an HTTPS
credential were unavailable; public API reads and SSH Git fetches succeeded.
Authentication was subsequently restored; see the follow-up below.

### QA-01 progress

Provisioned isolated Node.js 22.23.2 / npm 10.9.8 under
`/private/tmp/hiboss-toolchains/node-v22.23.2-darwin-arm64`, verifying the archive
against the vendor's SHA-256 list. Installed Web dependencies with `npm ci`;
no tracked dependency manifest or lockfile changed.

| Check | Result |
| --- | --- |
| `cd web && npm test` | 18 test files, 135 tests passed |
| `cd web && npm run check` | 0 errors, 0 warnings |
| `cd web && npm run build` | Passed; static site written to `web/build` |

Build output includes the existing adapter notice that the fallback overwrites
`build/index.html`. Browser, authenticated API, and device behavior were not tested.
Temporary raw logs: `/tmp/hiboss-web-test.log`, `/tmp/hiboss-web-check.log`, and
`/tmp/hiboss-web-build.log`.

Reproduce with the isolated Node bin directory on PATH, then run the commands
above from `web/`. QA-01 remains partial: panel-runtime, MCP type/build/integration,
Swift/native baselines, and authorized remote server/E2E checks remain open.
BASE-01 and DEL-01 still require operational evidence; M0 is not complete.


### Authenticated PR cleanup follow-up

After the user completed `gh auth login`, re-read every PR with `gh pr view`.
All six heads and remote main were unchanged. GitHub now reports all six heads
as `CONFLICTING` / `DIRTY`; the exact module comparisons above still pass.
Closed #9–#14 as superseded, without merging or deleting branches. A transient
GraphQL failure while closing #11 was recovered using the REST API through `gh`.
The final `gh pr list --state open --limit 100 --json number,title` returns `[]`.
The repository has no remaining open PRs. No production deployment or source
branch change was performed.
