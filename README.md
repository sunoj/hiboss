# hiboss

**AI Agent <-> Boss Communication Tool**

hiboss lets AI agents send messages to their human boss and receive replies through
familiar channels like Discord and Telegram. When an agent needs approval, wants to
report progress, or has a question, it calls `hiboss send` or `hiboss ask` -- the
message lands in your chat app, and your reply flows back to the agent.

Agents can also act as bosses for other agents, enabling autonomous multi-agent
workflows where a human can still step in at any time.

## Architecture

```
                         +---------------------+
  hiboss CLI (Rust)      |  hiboss-server      |     Discord / Telegram
  hiboss MCP Server  <-->|  (Cloudflare Worker) |<--->  Boss (human or AI)
                         |  D1 + R2 storage    |
                         +---------------------+
```

The server runs on Cloudflare Workers with D1 for persistence and R2 for file
attachments. Channels are pluggable adapters -- configure one or more, and messages
route through whichever you choose.

## Quick Start

### Prerequisites

- [Rust](https://rustup.rs/) (for the CLI)
- [Node.js](https://nodejs.org/) >= 18 (for the server and MCP server)
- A [Cloudflare](https://dash.cloudflare.com/) account with Workers, D1, and R2 enabled

### 1. Deploy the server

```bash
cd server
npm install
npx wrangler d1 create hiboss-db          # create the D1 database
# Update wrangler.toml with the returned database_id
npx wrangler d1 migrations apply hiboss-db # apply all migrations
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

# Discord (bot mode)
hiboss channel set discord --bot-token <BOT_TOKEN> --channel-id <CHANNEL_ID>

# Discord (webhook mode, no bot required)
hiboss channel set discord --webhook-url <WEBHOOK_URL>
```

### 5. Send your first message

```bash
hiboss send "Hello boss!"
```

## Features

### Messaging

```bash
hiboss send "Deployment complete"                  # async message
hiboss send --priority high "Build failed"         # urgent message
hiboss ask "Option A or B?" --timeout 60           # blocking, wait for reply
hiboss ask --options "A,B,C" "Pick one"            # quick-reply buttons
hiboss ask --actions "Approve:make deploy,Reject" "Deploy to prod?"  # action buttons
hiboss send --file ./screenshot.png "See attached" # file attachment
hiboss send --type task_update "Build deployed"    # typed messages
```

### Action Buttons

`--actions` creates Telegram/Discord buttons that trigger commands when pressed.
The executed command's result (success/failure + output) is automatically sent back
to the boss as a `type=action_result` message.

```bash
hiboss ask --actions "Merge:git merge feature,Reject:echo no" "Merge this PR?"
# Boss taps "Merge" → `git merge feature` runs → result sent back automatically
```

### Channel Routing

Route messages to different channels based on priority:

```bash
hiboss agent config --channel-routing "normal=discord,high=telegram,critical=telegram"
```

Resolution order: `--channel` flag > server `channel_routing` > first configured channel.

### Inbox & Replies

```bash
hiboss inbox                              # unread messages from boss
hiboss inbox --priority critical,high     # urgent only
hiboss read <id>                          # message with reply chain
hiboss reply <id> "Done"                  # reply to boss
hiboss react <id> "✅"                   # emoji reaction (Telegram)
```

### Multi-Boss Teams

```bash
hiboss boss add "Alice" --role admin --telegram-user-id 12345
hiboss boss add "Bob" --role manager --discord-user-id 67890
hiboss boss grant <boss-id> <agent-id>    # grant agent access
hiboss boss list                          # list bosses with roles
```

Roles: `admin` (access all agents), `manager` (explicit grants only), `viewer` (read-only).

### Agent-as-Boss

An agent can act as boss for other agents -- enabling autonomous orchestration:

```bash
# Create a boss linked to an agent
hiboss boss add "Orchestrator" --role admin --agent-id <orchestrator-key-id>

# The orchestrator reads sub-agent messages and replies
hiboss boss inbox
hiboss boss reply <id> "Approved, proceed"
```

### Agent Groups & Routing

```bash
hiboss group create dev-team                       # create group
hiboss group add-member <group-id> <agent-id>      # add member
hiboss group broadcast <group-id> "Stop all work"  # broadcast

hiboss route add --channel telegram --pattern "deploy.*" --target <agent-id>
```

### Session Isolation

Each Claude Code session gets a unique session ID. Messages are scoped per session --
`hiboss inbox` only shows messages from the current session. Boss-initiated messages
(not replies) are visible across all sessions.

### Claude Code Integration

```bash
hiboss setup hooks           # install SessionStart + PostToolUse hooks
hiboss setup hooks --global  # install for all projects
hiboss doctor                # validate config, connectivity, channel routing
```

The hooks inject unread messages at session start and check for urgent messages
every 5 minutes during work.

### Discord Bidirectional

Boss can send messages and click buttons from Discord:

```bash
hiboss channel discord-setup --app-id <id> --bot-token <token>  # register /msg command
```

Boss uses `/msg <message>` in Discord to send messages to agents.

## MCP Server

The MCP server lets AI coding tools (Claude Code, Cursor, etc.) communicate with the
boss directly through the Model Context Protocol.

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

## Self-Hosted

hiboss is fully self-hosted. The server runs on your own Cloudflare account, data
lives in your own D1 database, and channel credentials stay under your control.
No external services, no telemetry, no third-party dependencies beyond Cloudflare.

## Project Structure

```
cli/           Rust CLI binary (clap, reqwest, tokio)
server/        Cloudflare Worker (Hono, D1, R2)
mcp-server/    MCP server for AI coding tools (TypeScript)
```

## License

MIT
