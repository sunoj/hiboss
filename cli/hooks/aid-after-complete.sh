#!/bin/bash
# aid after_complete hook — notifies boss via hiboss when a sub-task completes.
# Receives task JSON on stdin. Extracts task ID, agent, and summary.

if ! command -v hiboss &>/dev/null; then
  exit 0
fi

# Read task JSON from stdin
task_json=$(cat)
if [ -z "$task_json" ]; then
  exit 0
fi

task_id=$(echo "$task_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id','?')[:8])" 2>/dev/null)
agent=$(echo "$task_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent','?'))" 2>/dev/null)
prompt=$(echo "$task_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('prompt','')[:100])" 2>/dev/null)

hiboss send --priority low "[aid] Task ${task_id} completed (${agent}): ${prompt}" 2>/dev/null

exit 0
