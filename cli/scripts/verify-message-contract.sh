#!/bin/bash
# Runs message-contract checks on the synced rbox checkout.
# Records source identity and keeps failed regression results visible.
set -u
printf 'REMOTE_HEAD=%s\n' "$(git rev-parse HEAD)"
git diff --stat
result=0
case "${1:-focused}" in
  before)
    python3 - <<'PY'
from pathlib import Path
import subprocess
paths = subprocess.check_output(['git', 'ls-files', 'cli/src'], text=True).splitlines()
paths += ['server/src/routes/message-send-input.ts', 'server/src/routes/messages.ts']
for name in paths:
    result = subprocess.run(['git', 'show', 'HEAD:' + name], capture_output=True)
    if result.returncode == 0:
        Path(name).write_bytes(result.stdout)
PY
    (cd cli && cargo test --test codex_runtime) || result=1
    (cd cli && cargo test --test message_contract) || result=1
    (npm ci && cd server && npx vitest run src/routes/message-title.test.ts) || result=1
    ;;
  focused)
    (cd cli && cargo test --test codex_runtime) || result=1
    (cd cli && cargo test --test message_contract) || result=1
    (npm ci && cd server && npx vitest run src/routes/message-title.test.ts) || result=1
    ;;
  final)
    (cd cli && cargo test && python3 scripts/test-agent-guidance.py) || result=1
    (npm ci && cd server && npm run typecheck && npm test) || result=1
    ;;
esac
exit "$result"
