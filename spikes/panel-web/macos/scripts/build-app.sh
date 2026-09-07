#!/bin/sh
# Builds the web bundle, copies it into SwiftPM resources, and wraps the app.
# Outputs: spikes/panel-web/macos/dist/Panel Web Spike.app.
# Dependencies: npm, SwiftPM, the untouched fixtures, and macOS codesign.

set -eu

SPIKE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
REPO_DIR="$(CDPATH= cd -- "$SPIKE_DIR/../.." && pwd)"
RESOURCE_DIR="$SPIKE_DIR/macos/Resources"
NPM_CACHE="/tmp/hiboss-panel-web-npm-cache"

NPM_CONFIG_CACHE="$NPM_CACHE" npm ci --prefix "$SPIKE_DIR/web"
NPM_CONFIG_CACHE="$NPM_CACHE" npm run build --prefix "$SPIKE_DIR/web"
rm -rf "$RESOURCE_DIR/Web" "$RESOURCE_DIR/Fixtures"
mkdir -p "$RESOURCE_DIR/Web" "$RESOURCE_DIR/Fixtures"
cp -R "$SPIKE_DIR/web/dist/." "$RESOURCE_DIR/Web/"
cp "$REPO_DIR/panel-runtime/fixtures/metric-panel.json" "$RESOURCE_DIR/Fixtures/metric-panel.json"
cp "$REPO_DIR/panel-runtime/fixtures/rollout-decision.json" "$RESOURCE_DIR/Fixtures/rollout-decision.json"

APP_DIR="$SPIKE_DIR/macos/dist/Panel Web Spike.app"
mkdir -p "$SPIKE_DIR/macos/dist"
rm -rf "$APP_DIR"
swift build --package-path "$SPIKE_DIR/macos" -c release
BIN_DIR="$(swift build --package-path "$SPIKE_DIR/macos" -c release --show-bin-path)"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/PanelWebSpike" "$APP_DIR/Contents/MacOS/PanelWebSpike"
cp "$SPIKE_DIR/macos/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
for bundle in "$BIN_DIR"/*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
codesign --force --sign - "$APP_DIR"
echo "$APP_DIR"
