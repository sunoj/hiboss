#!/usr/bin/env bash
# Runs console verification and headless screenshot capture on a remote build box.
# The durable task fetches the screenshot output directory after success.
set -euo pipefail
git rev-parse HEAD
cd web
npm ci
npm run check
npm test
npm run build
browser_dir=$(mktemp -d)
npm install --prefix "$browser_dir" playwright
export PLAYWRIGHT_MODULE="$browser_dir/node_modules/playwright/index.mjs"
export HIBOSS_REMOTE_E2E=1
"$browser_dir/node_modules/.bin/playwright" install chromium
npm run preview -- --host 127.0.0.1 --port 4178 &
preview_pid=$!
trap 'kill "$preview_pid" 2>/dev/null || true' EXIT
node --input-type=module -e '
for (let i = 0; i < 40; i++) {
  try { if ((await fetch("http://127.0.0.1:4178/")).ok) process.exit(0); } catch {}
  await new Promise(resolve => setTimeout(resolve, 250));
}
process.exit(1);
'
node --test tests/projects.e2e.mjs
node tests/console-screenshots.mjs
