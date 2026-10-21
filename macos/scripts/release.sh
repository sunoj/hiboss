#!/usr/bin/env bash
# Build a HiBoss Island release: the versioned .app (optionally notarized and
# stapled), a zip for the GitHub Release `macos-v<version>`, and an EdDSA-signed
# one-item appcast written to site/updates/macos/appcast.xml (served by hiboss.org).
#
# Usage:
#   HIBOSS_SPARKLE_PUBKEY=<edDSA pubkey> \
#   [HIBOSS_SIGNING_IDENTITY="Developer ID Application: … (TEAMID)"] \
#   [NOTARY_PROFILE=hiboss-notary] [HIBOSS_SPARKLE_KEY_FILE=<private key file>] \
#   ./scripts/release.sh <version> "Release notes."
#
# The script uploads nothing. It prints the GitHub Release command; the appcast
# goes live when the site is deployed. sign_update reads the private EdDSA key
# from the login Keychain (Sparkle `generate_keys`) or HIBOSS_SPARKLE_KEY_FILE.
# HIBOSS_SIGNING_IDENTITY → Developer-ID signing; NOTARY_PROFILE (needs the
# identity) → notarize + staple. HIBOSS_RELEASE_REPO (default sunoj/hiboss)
# names the GitHub repository that hosts the zip.
# Deps: SwiftPM, ditto, Sparkle bin/sign_update, xcrun notarytool/stapler,
# security-guard (optional; scans the signed .app before it is zipped).

set -euo pipefail

VERSION="${1:?usage: release.sh <version> [notes]}"
NOTES="${2:-Bug fixes and improvements.}"
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version must look like 1.2.3, got: $VERSION" >&2
  exit 2
fi
: "${HIBOSS_SPARKLE_PUBKEY:?set HIBOSS_SPARKLE_PUBKEY (EdDSA public key from generate_keys)}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

REPO="${HIBOSS_RELEASE_REPO:-sunoj/hiboss}"
TAG="macos-v$VERSION"
MIN_OS="14.0"
BUILD="$(date +%Y%m%d%H%M)"          # monotonic-ish CFBundleVersion
OUT_DIR=".build/release-artifacts"
ZIP="HiBoss-Island-$VERSION.zip"
APP="$ROOT_DIR/dist/HiBoss Island.app"
APPCAST="$(cd "$ROOT_DIR/.." && pwd)/site/updates/macos/appcast.xml"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$ZIP"

# Locate Sparkle's sign_update from the resolved SwiftPM artifacts.
SIGN_UPDATE="$(/usr/bin/find .build/artifacts -name sign_update -type f -not -path '*old_dsa*' 2>/dev/null | head -1 || true)"
: "${SIGN_UPDATE:?sign_update not found — run 'swift build' first to fetch Sparkle}"
SIGN_ARGS=()
if [ -n "${HIBOSS_SPARKLE_KEY_FILE:-}" ]; then
  SIGN_ARGS=(--ed-key-file "$HIBOSS_SPARKLE_KEY_FILE")
fi

# 1. build the versioned, Sparkle-embedded bundle (default hiboss.org feed + pubkey).
HIBOSS_VERSION="$VERSION" HIBOSS_BUILD="$BUILD" \
  HIBOSS_SPARKLE_PUBKEY="$HIBOSS_SPARKLE_PUBKEY" \
  ./scripts/build-app.sh >/dev/null
mkdir -p "$OUT_DIR"

# 1b. notarize + staple when Developer-ID signed and a notary profile is set.
if [ -n "${NOTARY_PROFILE:-}" ] && [ -n "${HIBOSS_SIGNING_IDENTITY:-}" ]; then
  /usr/bin/ditto -c -k --keepParent "$APP" "$OUT_DIR/notarize-$VERSION.zip"
  echo "submitting to Apple notary (profile: $NOTARY_PROFILE)…"
  xcrun notarytool submit "$OUT_DIR/notarize-$VERSION.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  echo "notarized + stapled ✓"
elif [ -n "${HIBOSS_SIGNING_IDENTITY:-}" ]; then
  echo "NOTE: Developer-ID signed but NOT notarized — set NOTARY_PROFILE to notarize."
else
  echo "NOTE: ad-hoc/local signed — Gatekeeper will warn on first launch."
fi

# 1c. scan the final signed bundle for credentials before it is archived; an
# archive's own bytes cannot be scanned, so the .app tree is the checked artifact.
if command -v security-guard >/dev/null 2>&1; then
  security-guard artifact "$APP" --repo "$(cd "$ROOT_DIR/.." && pwd)"
else
  echo "NOTE: security-guard not installed — the bundle was not scanned for credentials."
fi

# 2. zip the .app (ditto keeps symlinks/signature intact for Sparkle).
rm -f "$OUT_DIR/$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$OUT_DIR/$ZIP"

# 3. EdDSA-sign the zip → sparkle:edSignature="…" length="…".
SIG_LINE="$("$SIGN_UPDATE" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$OUT_DIR/$ZIP")"
LENGTH="$(printf '%s' "$SIG_LINE" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

# 4. one-item appcast (Sparkle offers it when newer than the running build).
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>HiBoss Island</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[ $NOTES ]]></description>
      <enclosure url="$DOWNLOAD_URL" $SIG_LINE type="application/zip" />
    </item>
  </channel>
</rss>
XML

printf 'Built HiBoss Island %s (build %s, %s bytes). Nothing was uploaded.\n' \
  "$VERSION" "$BUILD" "$LENGTH"
printf '  zip:     %s\n  appcast: %s\n' "$OUT_DIR/$ZIP" "$APPCAST"
printf 'Publish the zip first, then commit the appcast and deploy the site:\n'
printf '  gh release create %q %q --repo %q --title %q --notes %q\n' \
  "$TAG" "$ROOT_DIR/$OUT_DIR/$ZIP" "$REPO" "HiBoss Island $VERSION" "$NOTES"
