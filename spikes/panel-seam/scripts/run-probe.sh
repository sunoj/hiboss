#!/bin/sh
# Launches the seam app, captures both appearances, and kills one WebContent process.
# Outputs: stdout observations and evidence/light.png plus evidence/dark.png.
# Dependencies: the built app, defaults, pgrep, kill, and the screenshot helper.

set -eu

SPIKE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$SPIKE_DIR/dist/Panel Seam Spike.app/Contents/MacOS/PanelSeamSpike"
LOG="$(mktemp /tmp/panel-seam-probe.XXXXXX)"
EVIDENCE_DIR="$SPIKE_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"

before_pids="$(pgrep -x com.apple.WebKit.WebContent || true)"
HIBOSS_SEAM_AUTO=1 "$APP" >"$LOG" 2>&1 &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true; rm -f "$LOG"' EXIT

ready=0
for _ in $(seq 1 60); do
    if rg -q '^probe_ready=1$' "$LOG"; then ready=1; break; fi
    sleep 1
done

if [ "$ready" -ne 1 ]; then
    echo "probe_status=not ready"
    sed -n '1,240p' "$LOG"
    exit 1
fi

python3 /Users/example/.codex/skills/screenshot/scripts/take_screenshot.py --active-window --path "$EVIDENCE_DIR/light.png"
echo "appearance_state=light screenshot=$EVIDENCE_DIR/light.png"
defaults write -g AppleInterfaceStyle Dark
sleep 1
python3 /Users/example/.codex/skills/screenshot/scripts/take_screenshot.py --active-window --path "$EVIDENCE_DIR/dark.png"
echo "appearance_state=dark screenshot=$EVIDENCE_DIR/dark.png"
defaults delete -g AppleInterfaceStyle
sleep 1
echo "appearance_state=light_restored"

web_pid=""
for pid in $(pgrep -x com.apple.WebKit.WebContent || true); do
    case " $before_pids " in
        *" $pid "*) ;;
        *) web_pid="$pid"; break ;;
    esac
done
if [ -n "$web_pid" ]; then
    echo "renderer_kill_pid=$web_pid"
    kill -KILL "$web_pid"
else
    echo "renderer_kill=not observed (new WebContent PID unavailable)"
fi
sleep 2
sed -n '1,240p' "$LOG"
