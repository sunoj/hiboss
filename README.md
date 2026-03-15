# hiboss

**AI Agent <-> Boss Communication Tool**

hiboss lets AI agents send messages to their human boss and receive replies through
familiar channels like Discord and Telegram. When an agent needs approval, wants to
report progress, or has a question, it calls `hiboss send` or `hiboss ask` -- the
message lands in your chat app, and your reply flows back to the agent.

The system also supports agent-to-agent communication. One agent sends a message while
another runs in bot mode with a custom handler, enabling autonomous multi-agent
workflows where a human can still step in at any time.

## Architecture

```
                         +---------------------+
  hiboss CLI (Rust)      |  hiboss-server      |     Discord / Telegram
  hiboss MCP Server  <-->|  (Cloudflare Worker) |<--->  Boss (human or AI)
                         |  D1 database         |
                         +---------------------+
```

The server runs on Cloudflare Workers with D1 for persistence. Channels are pluggable
adapters -- configure one or more, and messages route through whichever you choose.

## Quick Start

### Prerequisites

- [Rust](https://rustup.rs/) (for the CLI)
- [Node.js](https://nodejs.org/) >= 18 (for the server and MCP server)
- A [Cloudflare](https://dash.cloudflare.com/) account with Workers and D1 enabled

### 1. Deploy the server

```bash
cd server
npm install
npx wrangler d1 create hiboss-db          # create the D1 database
# Update wrangler.toml with the returned database_id
npx wrangler d1 execute hiboss-db --file=schema.sql   # apply schema
npx wrangler deploy
```

### 2. Build the CLI

```bash
cd cli
cargo build --release
cp target/release/hiboss ~/.cargo/bin/
```

### 3. Initialize

```bash
hiboss init https://hiboss-server.<you>.workers.dev
```

This bootstraps the first API key and saves your config to
`~/.config/hiboss/config.json`.

### 4. Configure a channel

```bash
# Telegram
hiboss channel set telegram --bot-token <BOT_TOKEN> --chat-id <CHAT_ID>

# Discord
hiboss channel set discord --bot-token <BOT_TOKEN> --channel-id <CHANNEL_ID>
```

For Telegram, the CLI automatically registers the webhook with the Telegram API.

### 5. Send your first message

```bash
hiboss send "Hello boss!"
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `hiboss init <server-url>` | Initialize config and bootstrap the first API key |
| `hiboss send <message>` | Send an async message to your boss |
| `hiboss ask <message>` | Send a blocking message and wait for the boss reply |
| `hiboss inbox` | List unread messages from your boss |
| `hiboss read <id>` | Read a specific message with its reply chain |
| `hiboss reply <id> <message>` | Reply to a message from your boss |
| `hiboss status <id>` | Check the delivery status of a sent message |
| `hiboss watch` | Watch for new messages with desktop notifications |
| `hiboss bot --handler <cmd>` | Auto-reply to messages using an external handler |
| `hiboss agent` | Manage agent identities |
| `hiboss channel set <type>` | Configure a messaging channel |
| `hiboss channel list` | List configured channels |
| `hiboss config set <key> <val>` | Manage local configuration |

Common flags: `--priority critical|high|normal|low`, `--channel discord|telegram`,
`--timeout <seconds>`.

## MCP Server

The MCP server lets AI coding tools (Claude Code, Cursor, etc.) communicate with the
boss directly through the Model Context Protocol.

### Setup

```bash
cd mcp-server
npm install
npm run build
```

### Configure in `.mcp.json`

```json
{
  "mcpServers": {
    "hiboss": {
      "command": "node",
      "args": ["/path/to/hiboss/mcp-server/dist/index.js"],
      "env": {
        "HIBOSS_SERVER": "https://hiboss-server.<you>.workers.dev",
        "HIBOSS_KEY": "hb_your_api_key"
      }
    }
  }
}
```

The MCP server can also read credentials from `~/.config/hiboss/config.json` if the
environment variables are not set.

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `send_message` | Send an async update to the boss |
| `ask_boss` | Ask the boss a question and wait for a reply |
| `check_inbox` | List unread or recent boss messages |
| `read_message` | Read a message and its replies |
| `reply_message` | Reply to a boss message |

## Agent-to-Agent Communication

Use bot mode to create agents that automatically respond to messages. The handler
receives the message body on stdin and returns the reply on stdout.

```bash
# Simple acknowledgment bot
hiboss bot --handler 'echo "Acknowledged"'

# Forward to an LLM for autonomous replies
hiboss bot --handler 'llm-cli --prompt "$(cat)"'

# Custom script with logic
hiboss bot --handler './my-handler.sh' --interval 10
```

One agent sends with `hiboss send` or `hiboss ask`, and another agent running
`hiboss bot` picks it up and replies automatically. Chain multiple agents together
for complex workflows.

## Self-Hosted

hiboss is fully self-hosted. The server runs on your own Cloudflare account, data
lives in your own D1 database, and channel credentials stay under your control.
There are no external services, no telemetry, and no third-party dependencies beyond
Cloudflare's infrastructure.

## Project Structure

```
cli/           Rust CLI binary (clap, reqwest, tokio)
server/        Cloudflare Worker (Hono, D1)
mcp-server/    MCP server for AI coding tools (TypeScript)
```

## License

MIT
