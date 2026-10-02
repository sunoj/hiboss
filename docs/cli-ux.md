# CLI first-use and recovery behavior

This page describes how the `hiboss` CLI presents itself to a new user and how it
reports configuration problems. The implementation lives in `cli/src/help.rs`,
`cli/src/config.rs` and the dispatch in `cli/src/main.rs`; the executable-level
tests are in `cli/tests/cli_ux.rs`.

## Root help

`hiboss --help` lists the root commands grouped by intent, followed by the global
options and a short set of runnable examples:

| Group | Commands |
| --- | --- |
| Get started | `init`, `doctor`, `config`, `setup` |
| Talk to your boss | `send`, `ask`, `reply`, `inbox`, `read`, `react`, `edit`, `forward`, `status` |
| Show work | `panel`, `request`, `progress`, `project` |
| Coordinate sessions | `ss`, `agent`, `group` |
| Run in the background | `watch`, `bot`, `daemon`, `hook` |
| Administer the server | `key`, `boss`, `channel`, `route` |

The group table is `COMMAND_GROUPS` in `cli/src/help.rs`. Descriptions are read
from each subcommand's own `about`, so they cannot drift. A unit test fails when a
visible subcommand is missing from the table, appears twice, or when the table
names a command that does not exist. Subcommand help (`hiboss send --help`) keeps
Clap's default layout.

Running `hiboss` with no arguments prints the same grouped help on stderr and exits
with status 2, the usage-error status it had before.

## Commands that bypass required configuration

These commands run before the top-level dispatcher loads configuration, so they
work on a fresh machine and with a file that does not parse. Integration helpers
may independently attempt best-effort configuration reads:

- `hiboss --help`, `hiboss --version`, `hiboss <command> --help`
- `hiboss panel guide`, `hiboss panel validate <file>`
- `hiboss hook <event>` (hook network calls stay best-effort and are skipped when
  the CLI is not configured)
- `hiboss setup hooks`, `hiboss setup agents`

`config`, `init`, `doctor` and `daemon` need a readable config file, but not a
configured server. A missing or empty file counts as an empty configuration.

## Configuration errors

Configuration load/required-value errors name the config file and one next step
on stderr. Stdout stays empty, so a `--json` consumer never receives a partial
document. Missing required values exit with status 3; unreadable or malformed
configuration retains status 1.

| State | Message ends with |
| --- | --- |
| No file, empty file, or `{}` | `server is not configured in <path>; run hiboss init <server-url> to join a server` |
| Key set, server missing or blank | `run hiboss config set server <url>` |
| Server set, key missing or blank | `API key is missing in <path>; run hiboss init <server-url> with your configured server to request one` |
| File does not parse | `config file <path> is not valid hiboss configuration (line L, column C); move the file aside as a backup, then run hiboss init <server-url>` |
| File cannot be read | `cannot read config file <path> (<os error>); check the file's read permissions` |

A parse error reports only the position. It does not include the parser message,
because that message can quote stored values such as the API key. `config set` and
`init` refuse to run against an unparseable file rather than overwriting it, which
keeps whatever the user still has in it.

The CLI checks for a missing or blank value before it builds an HTTP client, so
none of these states sends a request.

## Exit codes

| Status | Meaning |
| --- | --- |
| 0 | Success |
| 1 | Command failed, including unreadable or unparseable configuration |
| 2 | Usage error from argument parsing, or a network failure (`request failed`, `connect`, `timeout`) |
| 3 | Missing or blank required configuration |

Configuration-load errors have an explicit type, so clearer diagnostics cannot
change their status through the general message-based error classifier.

## Verifying

`cli/scripts/check-ux.sh` runs the full CLI test suite and then prints the root
help and the recovery messages from a throwaway `HOME`. Run it on a build host:

```sh
rbox exec <box> <checkout> --untracked -- sh cli/scripts/check-ux.sh
```
