# HiBoss

**Decisions, progress and shared context between AI agents and the people they work for.**

Website: [hiboss.org](https://hiboss.org/) · [Privacy](https://hiboss.org/privacy/) · [Support](https://hiboss.org/support/)
· [Changelog](CHANGELOG.md) · [Roadmap](docs/roadmap.md)

HiBoss is a self-hosted server, a CLI for agents, and native apps for the human ("the
boss"). An agent that needs a decision, wants to report a result, or has something worth
watching uses the `hiboss` CLI. The boss answers from the iPhone or Mac app, the web
console, Telegram or Discord, and the answer flows back to the agent.

- **Decisions.** `hiboss ask` sends a question with up to five choices and waits for one
  durable answer. A timeout default is recorded as `auto_default`, never as a human choice.
- **Messages.** `hiboss send` delivers progress and results; `hiboss inbox` and
  `hiboss reply` carry the boss's messages back to the right agent session.
- **Progress feed.** `hiboss progress post` adds screenshots and clips to a per-project
  timeline that never notifies.
- **Live panels.** `hiboss panel` publishes a card that keeps updating: a test run, a
  benchmark sweep, a monitor. `hiboss request` adds a typed questionnaire to a panel.
- **Box.** The boss's shared text, links and media, which agents can search and add to,
  with optional expiring public share links.
- **Teams.** Several bosses with `admin`, `manager` and `viewer` roles, per-agent access
  grants, and agents that act as bosses for other agents.

How the pieces fit is described in [business logic](docs/business-logic.md).

## Components

| Path | What it is |
| --- | --- |
| [`server/`](server/) | Cloudflare Worker (Hono, D1, R2, Durable Objects): the API, delivery and live relay |
| [`cli/`](cli/) | `hiboss`, the Rust CLI used by agents, hooks and setup |
| [`mcp/`](mcp/) | MCP server for Claude Code (Bun): HiBoss tools plus pushed messages |
| [`ios/`](ios/) | iPhone app: attention inbox, decisions, progress, panels, Box, Live Activities |
| [`macos/`](macos/) | Mac app "HiBoss Island": dashboard, decisions, history, panels, Box |
| [`HibossKit/`](HibossKit/) | Swift package shared by the iOS and Mac apps |
| [`web/`](web/) | Web console (SvelteKit static build): agents, bosses, notifications, projects |
| [`panel-runtime/`](panel-runtime/) | Shared panel definition schema, validation and fixtures |
| [`site/`](site/) | Static public website |
| [`terminal/`](terminal/) | ESP-IDF configuration defaults for an ESP32 terminal |
| [`docs/`](docs/) | Contracts and references; start with [business logic](docs/business-logic.md) |

## External services

HiBoss runs entirely on your Cloudflare account (Workers, D1, R2, Durable Objects).
Everything else is optional and used only when you configure it:

- **Apple Push Notification service**, for iPhone notifications and Live Activities.
- **Telegram Bot API**, for a Telegram channel.
- **Discord API**, for a Discord channel and interactive buttons.

The server sends no telemetry.

## Quick Start

### Prerequisites

- A [Cloudflare](https://dash.cloudflare.com/) account with Workers, D1 and R2 enabled
- [Node.js](https://nodejs.org/) 20 or later
- [Rust](https://rustup.rs/) 1.85 or later (the CLI uses the 2024 edition)
- The HiBoss iPhone app or the Mac app, to approve machines and answer decisions

### 1. Deploy the server

```bash
cp server/wrangler.toml.example server/wrangler.toml
npm ci                                       # server and panel-runtime workspaces
cd server
npx wrangler d1 create hiboss-db             # copy the returned database_id into wrangler.toml
npx wrangler r2 bucket create hiboss-attachments
npx wrangler secret put BOOTSTRAP_SECRET     # a long random value; keep it private
npm run deploy                               # apply D1 migrations, then deploy the Worker
```

`npm run deploy` stops if a migration fails. `server/wrangler.toml.example` documents
every other variable: `DESTINATIONS_MODE`, the web console origin, and the optional
Telegram, Discord and APNs settings.

### 2. Install the CLI

```bash
cargo install --locked --path cli
```

### 3. Create the boss and enrol the first machine

On the first machine, with the bootstrap secret in the environment so it is not stored
in your shell history:

```bash
export HIBOSS_BOOTSTRAP_SECRET='<the BOOTSTRAP_SECRET value>'
hiboss setup --server https://hiboss-server.<account>.workers.dev --boss-name "<your name>"
```

On a server with no boss yet, setup creates you as the `admin` boss and prints a
`hiboss://pair` link, its QR code and a single-use code that expires after five minutes.
It then sends this machine's join request and waits for approval.

### 4. Pair the app and approve the machine

1. Pair the app with the printed link or code: scan it with the iPhone app, or open
   HiBoss Island on the Mac and choose **Pair with Code…**.
2. Approve the machine's request. On iPhone it is under **Settings → Devices → Device
   Requests**; the Mac app shows it as a request sheet. Approve only if the request shows
   the same six-digit code as the terminal.

Setup then writes the machine's profiles to `~/Library/Application Support/hiboss/config.json`
on macOS or `${XDG_CONFIG_HOME:-~/.config}/hiboss/config.json` on Linux (or `$HIBOSS_CONFIG`).
If setup stops before approval, run the same command again to resume; `hiboss setup --abandon`
discards the request. `hiboss setup --check` verifies every profile.

### 5. Connect your agents

```bash
hiboss setup agents          # global Codex and Claude Code instructions for HiBoss
hiboss setup hooks --global  # Claude Code hooks: unread messages at start, delivery during work
hiboss send "Hello boss!"
```

### 6. Add more machines

On an enrolled machine, `hiboss device invite --copy` copies an **Add a machine**
prompt. Paste it into an agent on the new machine: it installs the CLI if needed, runs
`hiboss setup --invite …`, and waits for your approval in the app.

### Optional: Telegram or Discord

Channel configuration needs an agent profile with administrative capability; profiles
enrolled during the first install have it.

```bash
npx wrangler secret put TELEGRAM_WEBHOOK_SECRET          # in server/
hiboss setup telegram --webhook-secret '<same value>'     # guided bot and chat setup

hiboss setup discord                                      # guided Discord bot setup
```

Discord interactions also need `DISCORD_PUBLIC_KEY` in `server/wrangler.toml`.

### Optional: iPhone push

Push notifications require APNs configuration on the server (`APNS_KEY_ID`,
`APNS_TEAM_ID` and the `APNS_AUTH_KEY` secret); see
[push privacy and isolation](docs/push-privacy-and-isolation.md).

### Optional: web console

See [web/README.md](web/README.md) to build and deploy the console, then set
`CONSOLE_ORIGIN` in `server/wrangler.toml`.

## Using HiBoss from an agent

```bash
hiboss send "Deployment complete"
hiboss send --priority high --file ./failure.png "Build failed"
hiboss ask --option "Ship" --option "Hold" --default "Hold" --timeout 600 "Release 2.3?"
hiboss ask --json --option "A" --option "B" "Pick one"   # inspect "outcome" before acting
hiboss inbox
hiboss reply <message-id> "Done"
hiboss progress post "New onboarding flow" --image ./onboarding.png
hiboss panel guide                                       # how to publish a live panel
hiboss box latest --kind image --by boss
```

`--option` and `--action` are repeatable. An `--action "LABEL=COMMAND"` is shown to the
agent when the boss chooses it; HiBoss never executes it. Peer sessions on the same
project can coordinate with `hiboss send --to <name>` and `hiboss send --broadcast`.

The [CLI reference](docs/reference/cli-reference.md) lists every command, and the
[API reference](docs/reference/api-reference.md) every endpoint.

### Claude Code MCP server

The MCP server in `mcp/` gives Claude Code HiBoss tools (`send`, `ask`, `reply`, `react`,
`inbox`, `search`, `send_file` and others). It needs [Bun](https://bun.sh/) and reads the `claude`
profile from the CLI config (or `HIBOSS_PROFILE`); it never writes credentials.

```bash
cd mcp && bun install
claude mcp add hiboss -- bun "$PWD/server.ts"
```

`HIBOSS_SERVER` and `HIBOSS_KEY`, set together, supply ephemeral credentials instead of
the config file.

## Security

- Agent keys, boss tokens, pairing codes, invites and share links are stored as hashes.
- Agent keys and boss tokens are separate credential types with separate routes.
- Every boss read and write is scoped by role and per-agent grant; viewers are read-only.
- A new machine joins only with an invite (or the bootstrap secret on an empty server)
  and a boss's approval.
- Messages and boss replies can be signed with device-held ES256 keys.

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local development and each component's tests.

## License

MIT
