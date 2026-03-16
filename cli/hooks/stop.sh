#!/bin/bash
# hiboss Stop hook — checks for ALL unread boss messages before session ends.
# If unread messages exist, outputs a reminder so the agent handles them before stopping.
# MUST always exit 0 — hook failures should never block the agent.

if ! command -v hiboss &>/dev/null; then
  exit 0
fi

count=$(hiboss inbox --count 2>/dev/null || echo "")

if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
  echo "You have $count unread boss messages. Run 'hiboss inbox' and handle them before finishing."
else
  echo "[hiboss] No unread boss messages."
fi

exit 0
