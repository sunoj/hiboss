#!/bin/bash
# hiboss SessionStart hook — outputs unread boss messages to stdout.
# stdout is injected into agent context as <system-reminder> by Claude Code.

if ! command -v hiboss &>/dev/null; then
  exit 0
fi

count=$(hiboss inbox --count 2>/dev/null)

if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
  echo "You have $count unread boss messages:"
  hiboss inbox 2>/dev/null
  echo "Handle these messages before starting other work. Use 'hiboss reply <id> \"response\"' to reply."
fi

exit 0
