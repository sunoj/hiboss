# Contributing to HiBoss

HiBoss includes a Cloudflare Worker, Rust CLI, web console, shared panel runtime,
and native Apple clients. Start with the module README and keep changes scoped to
the behavior you are fixing.

## Run a local server from zero

```sh
npm ci                                            # server and panel-runtime workspaces
cp server/wrangler.toml.example server/wrangler.toml
printf 'BOOTSTRAP_SECRET=%s\n' "$(openssl rand -hex 24)" > server/.dev.vars
cd server
npx wrangler d1 migrations apply hiboss-db --local
npm run dev                                       # http://localhost:8787
```

Local D1, R2 and Durable Objects need no Cloudflare resources; the placeholder
`database_id` is fine. `server/.dev.vars` holds local secrets and is gitignored. Then
follow the README Quick Start from step 2 with `--server http://localhost:8787` and the
secret from `.dev.vars`. Add other variables from `wrangler.toml.example` to
`.dev.vars` (secrets) or `wrangler.toml` (plain values) as needed.

## Tests

Run the checks for the components you changed:

| Component | Command |
| --- | --- |
| `server/` | `cd server && npm test && npm run typecheck` (`npm ci` at the repository root first) |
| `panel-runtime/` | `npm test --workspace panel-runtime` |
| `cli/` | `cd cli && cargo test --locked` |
| `mcp/` | `cd mcp && bun install && bun test` |
| `web/` | `cd web && npm ci && npm test && npm run check` |
| `HibossKit/` | `cd HibossKit && swift test` |
| `macos/` | `swift build --package-path macos`, then focused `swift test --package-path macos --filter <Class>` |
| `ios/` | see below |

For a server change, the changed modules' test files plus the files that import them
are usually enough; run the full suite when migrations, `wrangler.toml`, shared types or
authentication change. Every bug fix needs a test that fails without the fix.

### macOS tests

Many `HibossIslandTests` classes open real windows on the desktop of the Mac that runs
them. `macos/scripts/verify-tier.sh` maps changed paths to the smallest set of test
classes and prints the exact commands, separating window classes from logic-only ones.
Keep the display awake during window tests (`caffeinate -d -i -u swift test …`).

### iOS tests

```sh
brew install xcodegen
cd ios && xcodegen generate
xcodebuild test -project HiBoss.xcodeproj -scheme HiBoss -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:HiBossTests
```

`HiBossUITests` holds the UI tests; select classes with
`-only-testing:HiBossUITests/<Class>`. UI tests launch the app in demo mode and need no
server. `python3 ios/scripts/i18n-audit.py` and `python3 macos/scripts/i18n-audit.py`
check string catalogs.

Native client setup and signing are described in [ios/README.md](ios/README.md) and
[macos/README.md](macos/README.md). Include the commands you ran and their results in
your pull request. If a check needs an account or device you do not have, say so in the
pull request.

## Pull requests

- Describe the user-visible change, its test coverage, and any migration steps.
- Keep source comments, documentation, and commit messages in English.
- Keep credentials, local configuration, and generated build output out of Git.
  Use `server/wrangler.toml.example` as the configuration starting point and set
  runtime secrets with Wrangler.
- Report security issues privately as described in [SECURITY.md](SECURITY.md).

The project is available under the [MIT license](LICENSE).
