#!/bin/bash
# hiboss SessionStart hook — injects unread boss messages into Claude Code session.
# Writes HIBOSS_UNREAD env var via CLAUDE_ENV_FILE so the agent sees pending messages.

if [ -z "$CLAUDE_ENV_FILE" ]; then
  exit 0
fi

# Check if hiboss CLI is available
if ! command -v hiboss &>/dev/null; then
  exit 0
fi

# Fetch unread messages (returns empty if no config or no messages)
unread=$(hiboss inbox 2>/dev/null)
if [ -z "$unread" ]; then
  exit 0
fi

# Count non-header lines (messages)
msg_count=$(echo "$unread" | tail -n +2 | grep -c .)
if [ "$msg_count" -eq 0 ]; then
  exit 0
fi

# Inject as environment variable for the session
cat >> "$CLAUDE_ENV_FILE" <<ENVEOF
export HIBOSS_UNREAD_COUNT="$msg_count"
export HIBOSS_UNREAD="$(echo "$unread" | sed 's/"/\\"/g')"
ENVEOF

exit 0
