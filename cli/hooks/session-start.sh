#!/bin/bash
# hiboss SessionStart hook — outputs unread boss messages to stdout.
# stdout is injected into agent context as <system-reminder> by Claude Code.
# MUST always exit 0 — hook failures should never block the agent.

if ! command -v hiboss &>/dev/null; then
  exit 0
fi

count=$(hiboss inbox --count 2>/dev/null || echo "")

if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
  echo "You have $count unread boss messages:"
  hiboss inbox 2>/dev/null || echo "[hiboss] Failed to fetch inbox."
  echo "Handle these messages before starting other work. Use 'hiboss reply <id> \"response\"' to reply."
fi

exit 0
