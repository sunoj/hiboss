#!/bin/bash
# hiboss PostToolUse hook — checks for urgent boss messages with TTL cache.
# Only alerts for critical/high priority. Skips check if last check was < 5 min ago.
# Output goes to stdout → injected into agent context as <system-reminder>.
# MUST always exit 0 — hook failures should never block the agent.

set -o pipefail

TTL_FILE="/tmp/hiboss-urgent-check"
TTL_SECONDS=300  # 5 minutes

# Skip if checked recently
if [ -f "$TTL_FILE" ]; then
  last_check=$(cat "$TTL_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  elapsed=$((now - last_check))
  if [ "$elapsed" -lt "$TTL_SECONDS" ]; then
    exit 0
  fi
fi

# Update TTL timestamp early to avoid retry storms
date +%s > "$TTL_FILE" 2>/dev/null

# Skip if hiboss CLI not available
if ! command -v hiboss &>/dev/null; then
  exit 0
fi

# Check for urgent unread messages only
urgent_count=$(hiboss inbox --priority critical,high --count 2>/dev/null || echo "")

# Alert only if urgent messages exist
if [ -n "$urgent_count" ] && [ "$urgent_count" -gt 0 ] 2>/dev/null; then
  echo "URGENT: You have $urgent_count unread critical/high priority boss messages. Run: hiboss inbox --priority critical,high"
fi

exit 0
