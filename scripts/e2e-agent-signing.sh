#!/bin/sh
# End-to-end agent message signing: the real CLI binary against a local Worker and D1.
# Run from the repository root of a disposable checkout on a build box after `npm ci`; it resets
# server/.wrangler/state, builds the CLI and uses only localhost.
# Proves enroll, signed send, refused edit, prefix-resolved signed reply, verification on read, no downgrade.
set -eu

ROOT=$(pwd)
WORK=$(mktemp -d)
PORT=${E2E_PORT:-$((20000 + $$ % 20000))}
DEV=""
cleanup() {
  # wrangler starts workerd children; kill the whole process group, never just npx.
  if [ -n "$DEV" ]; then kill -TERM "-$DEV" 2>/dev/null || kill "$DEV" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
# dash skips the EXIT trap on a signal; exit explicitly so cleanup always runs.
trap 'exit 130' INT
trap 'exit 143' TERM HUP
fail() {
  echo "FAIL: $*" >&2
  if [ -n "${KEY:-}" ]; then
    echo "--- GET /api/agents/me:" >&2
    curl -s -H "Authorization: Bearer $KEY" "http://127.0.0.1:$PORT/api/agents/me" >&2 || true
  fi
  if [ -f "$WORK/dev.log" ]; then echo "--- worker log:" >&2; tail -120 "$WORK/dev.log" >&2; fi
  exit 1
}

(cd cli && cargo build --quiet)
# Build boxes may set CARGO_TARGET_DIR; ask cargo where the binary went.
TARGET=$(cd cli && cargo metadata --format-version 1 --no-deps | sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')
HIBOSS="$TARGET/debug/hiboss"
[ -x "$HIBOSS" ] || fail "hiboss binary not found at $HIBOSS"
cd server
[ -f wrangler.toml ] || cp wrangler.toml.example wrangler.toml
export CI=1 WRANGLER_SEND_METRICS=false
rm -rf .wrangler/state
npx wrangler d1 migrations apply hiboss-db --local 2>&1 | tail -5
sql() { npx wrangler d1 execute hiboss-db --local --json --command "$1"; }

KEY="hb_e2e_signing_$$"
HASH=$(printf %s "$KEY" | sha256sum | cut -d' ' -f1)
SYSTEM='{"source":"system","provenance":{"version":1,"source":"system","actor":{"kind":"system"},"authentication":{"kind":"system"},"signature":{"status":"not_applicable"}}}'
sql "INSERT INTO api_keys (id, name, key_hash) VALUES ('e2e-agent', 'e2e-agent', '$HASH');
  INSERT INTO agent_keys (id, agent_id, key_hash, label) VALUES ('e2e-cred', 'e2e-agent', '$HASH', 'e2e');
  INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata)
  VALUES ('e2eparent0000000000000000000001', 'e2e-agent', 'boss_to_agent', 'async', 'api', 'Status?', 'sent', 'normal', '$SYSTEM');" >/dev/null

if curl -s "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then fail "port $PORT is already serving; refusing to test a stale worker"; fi
setsid npx wrangler dev --local --port "$PORT" >"$WORK/dev.log" 2>&1 &
DEV=$!
tries=0
# Ready when our launcher's log reports this port and the port answers; the launcher must be
# alive on every probe, including the successful one, and again after the run.
until kill -0 "$DEV" 2>/dev/null && grep -q "Ready on http://localhost:$PORT" "$WORK/dev.log" \
  && curl -sf "http://127.0.0.1:$PORT/" >/dev/null 2>&1; do
  kill -0 "$DEV" 2>/dev/null || fail "worker launcher exited"
  tries=$((tries + 1)); [ "$tries" -lt 90 ] || fail "worker did not start"; sleep 1
done
kill -0 "$DEV" 2>/dev/null || fail "worker launcher exited"

export HOME="$WORK/home" HIBOSS_CONFIG="$WORK/config.json"
mkdir -p "$HOME"
printf '{"server":"http://127.0.0.1:%s","key":"%s"}' "$PORT" "$KEY" >"$HIBOSS_CONFIG"

"$HIBOSS" key enroll || fail "enroll"
ls "$WORK"/signing/*.json >/dev/null 2>&1 || fail "no key file beside the config"
SENT=$("$HIBOSS" send "signed e2e hello" | tail -1) || fail "signed send"
sql "SELECT metadata FROM messages WHERE id = '$SENT'" | grep -q 'agent_signature' || fail "send not stored as signed"
"$HIBOSS" status "$SENT" --json >/dev/null || fail "CLI rejected its own signed message on read"
if "$HIBOSS" edit "$SENT" "signed e2e edited" >/dev/null 2>&1; then fail "a signing agent's edit was accepted"; fi
"$HIBOSS" status "$SENT" --json >/dev/null || fail "CLI rejected its signed message after the refused edit"
"$HIBOSS" reply e2eparent "done" >/dev/null || fail "signed reply by id prefix"
sql "SELECT metadata FROM messages WHERE reply_to = 'e2eparent0000000000000000000001'" | grep -q 'agent_signature' \
  || fail "reply not stored as signed"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"body":"unsigned"}' "http://127.0.0.1:$PORT/api/messages")
[ "$CODE" = 401 ] || fail "unsigned write after enrollment returned $CODE, expected 401"
kill -0 "$DEV" 2>/dev/null || fail "worker launcher exited during the run"
echo "PASS: agent signing e2e (enroll, signed send, refused edit, signed reply by prefix, verify on read, no downgrade)"
