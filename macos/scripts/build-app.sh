#!/bin/sh
# Builds the release executable and wraps it in a runnable macOS app bundle
# with Sparkle embedded for auto-updates.
# Outputs: dist/HiBoss Island.app, ad-hoc signed by default.
# Dependencies: SwiftPM, codesign, PlistBuddy, Info.plist, and AppIcon.icns.
#
# Optional env:
#   HIBOSS_SIGNING_IDENTITY  codesign identity (default: ad-hoc).
#   HIBOSS_APPCAST_URL       overrides SUFeedURL in the bundled Info.plist.
#   HIBOSS_SPARKLE_PUBKEY    overrides SUPublicEDKey (EdDSA public key, base64).

set -eu

PACKAGE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$PACKAGE_DIR/dist/HiBoss Island.app"
CONTENTS_DIR="$APP_DIR/Contents"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
DEFAULT_SIGNING_IDENTITY="-"
SIGNING_IDENTITY="${HIBOSS_SIGNING_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

# Notarization requires the hardened runtime and a secure (online) timestamp;
# both are pointless overhead for the local development identity, so they turn
# on exactly when a Developer ID identity is used.
case "$SIGNING_IDENTITY" in
    "Developer ID"*) SIGN_FLAGS="--options runtime --timestamp" ;;
    *)               SIGN_FLAGS="--timestamp=none" ;;
esac

cd "$PACKAGE_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$FRAMEWORKS_DIR"
cp "$BIN_DIR/HibossIsland" "$CONTENTS_DIR/MacOS/HibossIsland"
cp "$PACKAGE_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PACKAGE_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"

# SwiftPM resource bundles hold String Catalogs. Copy them next to Resources so
# Bundle.module (and Bundle.main lookup of .lproj) can find translations.
for bundle in "$BIN_DIR"/*_*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "$CONTENTS_DIR/Resources/"
    find "$bundle" -name "*.lproj" -maxdepth 1 -exec cp -R {} "$CONTENTS_DIR/Resources/" \;
done

# Embed Sparkle (SwiftPM drops the framework next to the binary) and let the
# loader find it from the bundle.
cp -R "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$CONTENTS_DIR/MacOS/HibossIsland" 2>/dev/null || true

# Inject deployment-specific Sparkle settings without baking them into the repo.
# Both keys are absent from the tracked Info.plist (an empty SUPublicEDKey is
# invalid to Sparkle and makes the updater refuse to start), so add them here.
# A build missing either one simply ships without an updater.
if [ -n "${HIBOSS_APPCAST_URL:-}" ]; then
    "$PLIST_BUDDY" -c "Add :SUFeedURL string $HIBOSS_APPCAST_URL" "$CONTENTS_DIR/Info.plist"
fi
if [ -n "${HIBOSS_SPARKLE_PUBKEY:-}" ]; then
    "$PLIST_BUDDY" -c "Add :SUPublicEDKey string $HIBOSS_SPARKLE_PUBKEY" "$CONTENTS_DIR/Info.plist"
fi
# release.sh overrides the version/build so Sparkle can compare against a release.
if [ -n "${HIBOSS_VERSION:-}" ]; then
    "$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $HIBOSS_VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [ -n "${HIBOSS_BUILD:-}" ]; then
    "$PLIST_BUDDY" -c "Set :CFBundleVersion $HIBOSS_BUILD" "$CONTENTS_DIR/Info.plist"
fi

# Sign nested Sparkle helpers first, then the framework, then the app
# (deep→shallow — --deep does not re-sign the XPC/Autoupdate helpers correctly).
SP="$FRAMEWORKS_DIR/Sparkle.framework"
find "$SP" \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" \) -print0 2>/dev/null |
    while IFS= read -r -d '' nested; do
        codesign --force $SIGN_FLAGS --sign "$SIGNING_IDENTITY" "$nested"
    done
codesign --force $SIGN_FLAGS --sign "$SIGNING_IDENTITY" "$SP"
codesign --force $SIGN_FLAGS --sign "$SIGNING_IDENTITY" "$CONTENTS_DIR/MacOS/HibossIsland"
codesign --force $SIGN_FLAGS --sign "$SIGNING_IDENTITY" "$APP_DIR"

echo "$APP_DIR"
