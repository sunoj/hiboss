# Contributing to HiBoss

HiBoss includes a Cloudflare Worker, Rust CLI, web console, shared panel runtime,
and native Apple clients. Start with the module README and keep changes scoped to
the behavior you are fixing.

## Development checks

Install the server and panel runtime dependencies from the repository root with
`npm ci`. The web console has its own lockfile. Run the checks relevant to your
change:

```sh
(cd server && npm test && npm run typecheck)
(cd cli && cargo test --locked)
(cd web && npm ci && npm test && npm run check)
```

Native client setup and build commands are in [ios/README.md](ios/README.md) and
[macos/README.md](macos/README.md). Include the commands you ran and their results
in your pull request. If a check needs an account or device you do not have, state
that limitation in the pull request.

## Pull requests

- Describe the user-visible change, its test coverage, and any migration steps.
- Keep source comments, documentation, and commit messages in English.
- Keep credentials, local configuration, and generated build output out of Git.
  Use `server/wrangler.toml.example` as the configuration starting point and set
  runtime secrets with Wrangler.
- Report security issues privately as described in [SECURITY.md](SECURITY.md).

The project is available under the [MIT license](LICENSE).
