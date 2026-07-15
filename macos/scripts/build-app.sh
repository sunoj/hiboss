#!/bin/sh
# Builds the release executable and wraps it in a runnable macOS app bundle.
# Outputs: dist/HiBoss Island.app, signed with a stable local identity.
# Dependencies: SwiftPM, codesign, Info.plist, and AppIcon.icns.

set -eu

PACKAGE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$PACKAGE_DIR/dist/HiBoss Island.app"
CONTENTS_DIR="$APP_DIR/Contents"
DEFAULT_SIGNING_IDENTITY="Apple Development: Ming Sun (234582ZA6V)"
SIGNING_IDENTITY="${HIBOSS_SIGNING_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"

cd "$PACKAGE_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/HibossIsland" "$CONTENTS_DIR/MacOS/HibossIsland"
cp "$PACKAGE_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PACKAGE_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_DIR"

echo "$APP_DIR"
