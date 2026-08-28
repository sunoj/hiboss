# hiboss CLI Reference

## Setup
```bash
hiboss init https://hiboss-server.<user>.workers.dev  # bootstrap first key
hiboss config set server https://hiboss-server.<user>.workers.dev
hiboss config set key <api-key>
hiboss config set channel discord   # default channel
hiboss setup hooks                  # configure Claude Code hooks (project)
hiboss setup hooks --global         # configure for all Claude Code sessions
hiboss setup hooks --remove         # remove hiboss hooks
hiboss setup telegram               # guided Telegram bot setup
hiboss setup discord                # guided Discord bot setup
```

## Send (async)
```bash
hiboss send "Deployment complete."
hiboss send --priority high "Build failed, need help."
hiboss send --channel telegram "Quick update via TG."
hiboss send --file-url "https://example.com/screenshot.png" "See attached"
hiboss send --type task_update "Build v2.1 deployed"
hiboss send --file ./screenshot.png "See attached"
hiboss send --to worker-1 "Implement OAuth2 login"                    # agent-to-agent
hiboss send --to worker-1 --task "Implement OAuth2" --files src/auth/ # with context
hiboss send --to smart-router "..."        # project name: resolves to its one live session
hiboss send --to smart-router/main "..."   # exact label: wins outright even if several share it
hiboss send --to aefb4ffd "..."            # session id prefix
hiboss send --to smart-router --wait-ack "..."  # block until it leaves 'sent', then report
hiboss send --content "sim reverted @block 21M" "Retry at 2x gas?"    # --content = notification subtitle
hiboss send --summary "build status" "Full private-safe body here"    # --summary shown in private-mode pushes
```

## Ask (blocking, waits for reply)
```bash
hiboss ask "Option A or B for the migration?"
hiboss ask --timeout 60 "Quick question: proceed with deploy?"
hiboss ask --option "A" --option "B" --option "C" "Pick one:\n1. A\n2. B\n3. C"
hiboss ask --option "Ship" --option "Wait" --default "Ship" "Deploy now?"  # Ship auto-runs on timeout
hiboss ask --action "Approve=aid merge t-123" --action "Reject=echo rejected" "Deploy?"
hiboss ask --to reviewer "Review feat/oauth branch"
hiboss ask --content "payments · retry policy" --option "Approve" --option "Reject" "Retry?"  # subtitle context
```

`--content <TEXT>` adds a context line rendered as the boss notification subtitle
(under the project/title). `--summary <TEXT>` is a short non-sensitive summary shown
in private-mode pushes (where the body is withheld from Apple's servers).

`--option` and `--action` are singular repeatable flags. The removed plural flags
must not be used, and choices must not be joined with commas.

`--default <LABEL>` marks one option/action label as the default. It is flagged in
the boss UI, and if the ask times out with no reply the server auto-selects it and
returns it to the asker, so the agent can proceed instead of stalling.

## Inbox
```bash
hiboss inbox                              # unread messages (boss + agent)
hiboss inbox --all                        # all messages
hiboss inbox --limit 5                    # last 5
hiboss inbox --priority critical,high     # urgent only
hiboss inbox --priority critical --count  # count of urgent unread
hiboss inbox --from lead-agent            # from specific agent
hiboss inbox --search "keyword"           # full-text search
```

## Read / Reply / React
```bash
hiboss read <msg-id>
hiboss read <id> --reactions
hiboss reply <msg-id> "Done, deployed to staging."
hiboss reply <msg-id> --status accepted "Starting now"
hiboss reply <msg-id> --status completed "Done. PR ready."
hiboss reply <msg-id> --status blocked "Need DB schema decision"
hiboss react <msg-id> "👀"
hiboss status <msg-id>
```

## Agent Config
```bash
hiboss agent config                          # view config
hiboss agent config --default-priority high
hiboss agent config --rate-limit 10          # msg/min
hiboss agent config --rate-limit 0           # disable
hiboss agent config --role orchestrator
hiboss agent config --channel-routing "normal=discord,high=telegram"
```

## Routing Rules
```bash
hiboss route list
hiboss route add --channel telegram --pattern "deploy.*" --target <agent-id>
hiboss route add --channel discord --pattern "urgent" --target <agent-id> --priority 10
hiboss route remove <rule-id>
```

## Agent Groups
```bash
hiboss group list
hiboss group create dev-team --description "Development agents"
hiboss group show dev-team
hiboss group add-member <group-id> <agent-id>
hiboss group remove-member <group-id> <agent-id>
hiboss group broadcast <group-id> "Stop all work" --priority high
hiboss group delete <group-id>
```

## Discord Setup
```bash
hiboss channel discord-setup --app-id <id> --bot-token <token>
hiboss channel set discord --webhook-url <url> --bot-token <token> --channel-id <id>
```

## Boss Management
```bash
hiboss boss list
hiboss boss add "Ming" --role admin --telegram-user-id 123
hiboss boss show <boss-id>
hiboss boss update <boss-id> --discord-user-id 456
hiboss boss grant <boss-id> <agent-id>
hiboss boss revoke <boss-id> <agent-id>
hiboss boss remove <boss-id>
```

## Agent-as-Boss
```bash
hiboss boss add "Manager" --agent-id <agent-id>
hiboss boss inbox
hiboss boss inbox --priority critical,high
hiboss boss inbox --count
hiboss boss reply <msg-id> "Your reply here"
```

## Session Status Board
```bash
hiboss ss                                    # kanban board
hiboss ss set working "implementing feature"
hiboss ss set waiting "need boss approval"
hiboss ss set blocked "external dependency"
hiboss ss set completed
```

## Background SSE Daemon
```bash
hiboss daemon start
hiboss daemon stop
hiboss daemon status
```

## Diagnostics
```bash
hiboss doctor    # validate config, connectivity, channel setup, routing
```

## CLI Config
Stored in `~/.config/hiboss/config.json`:
```json
{
  "server": "https://hiboss-server.xxx.workers.dev",
  "key": "hb_xxxxxxxxxxxx",
  "channel": "discord"
}
```
