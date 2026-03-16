#!/bin/bash
# aid on_fail hook — notifies boss via hiboss when a sub-task fails.
# Receives task JSON on stdin. Sends high priority alert.

if ! command -v hiboss &>/dev/null; then
  exit 0
fi

task_json=$(cat)
if [ -z "$task_json" ]; then
  exit 0
fi

task_id=$(echo "$task_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id','?')[:8])" 2>/dev/null)
agent=$(echo "$task_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent','?'))" 2>/dev/null)
prompt=$(echo "$task_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('prompt','')[:100])" 2>/dev/null)

hiboss send --priority high "[aid] Task ${task_id} FAILED (${agent}): ${prompt}" 2>/dev/null

exit 0
