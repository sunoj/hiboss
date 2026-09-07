#!/bin/sh
# Builds the bundled chart leaf, copies the shared fixture, and wraps the app.
# Outputs: spikes/panel-seam/dist/Panel Seam Spike.app.
# Dependencies: npm, SwiftPM, the panel-runtime fixture, and macOS codesign.

set -eu

SPIKE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REPO_DIR="$(CDPATH= cd -- "$SPIKE_DIR/../.." && pwd)"
RESOURCE_DIR="$SPIKE_DIR/Resources"
NPM_CACHE="/tmp/hiboss-panel-seam-npm-cache"

NPM_CONFIG_CACHE="$NPM_CACHE" npm install --no-package-lock --prefix "$SPIKE_DIR/web"
NPM_CONFIG_CACHE="$NPM_CACHE" npm run build --prefix "$SPIKE_DIR/web"
rm -rf "$RESOURCE_DIR/Web" "$RESOURCE_DIR/Fixtures"
mkdir -p "$RESOURCE_DIR/Web" "$RESOURCE_DIR/Fixtures"
cp -R "$SPIKE_DIR/web/dist/." "$RESOURCE_DIR/Web/"
cp "$REPO_DIR/panel-runtime/fixtures/mixed-panel.json" "$RESOURCE_DIR/Fixtures/mixed-panel.json"

APP_DIR="$SPIKE_DIR/dist/Panel Seam Spike.app"
mkdir -p "$SPIKE_DIR/dist"
rm -rf "$APP_DIR"
swift build --package-path "$SPIKE_DIR" -c release
BIN_DIR="$(swift build --package-path "$SPIKE_DIR" -c release --show-bin-path)"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/PanelSeamSpike" "$APP_DIR/Contents/MacOS/PanelSeamSpike"
cp "$RESOURCE_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
for bundle in "$BIN_DIR"/*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
codesign --force --sign - "$APP_DIR"
echo "$APP_DIR"
