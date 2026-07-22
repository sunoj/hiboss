#!/usr/bin/env bash
# Cut and publish a HiBoss Island Sparkle release: build the versioned .app,
# EdDSA-sign the zip, generate a one-item appcast, and PUT both to the hiboss
# Worker (served from R2 under /updates/macos/).
#
# Usage:
#   UPLOAD_SECRET=... HIBOSS_UPDATES_BASE=https://<server>/updates/macos \
#   HIBOSS_SPARKLE_PUBKEY=<edDSA pubkey> \
#   [HIBOSS_SIGNING_IDENTITY="Developer ID Application: … (TEAMID)"] \
#   [NOTARY_PROFILE=hiboss-notary] \
#   ./scripts/release.sh <version> "Release notes."
#
# The private EdDSA key lives in your login Keychain (from Sparkle's
# `generate_keys`); sign_update reads it. UPLOAD_SECRET must equal the Worker's
# RELEASE_UPLOAD_SECRET. HIBOSS_SIGNING_IDENTITY → real Developer-ID signing;
# NOTARY_PROFILE (needs the identity) → notarize + staple for offline Gatekeeper.
# Deps: SwiftPM, ditto, curl, Sparkle bin/sign_update, xcrun notarytool/stapler.

set -euo pipefail

VERSION="${1:?usage: release.sh <version> [notes]}"
NOTES="${2:-Bug fixes and improvements.}"
: "${UPLOAD_SECRET:?set UPLOAD_SECRET (== Worker RELEASE_UPLOAD_SECRET)}"
: "${HIBOSS_UPDATES_BASE:?set HIBOSS_UPDATES_BASE (e.g. https://<server>/updates/macos)}"
: "${HIBOSS_SPARKLE_PUBKEY:?set HIBOSS_SPARKLE_PUBKEY (EdDSA public key from generate_keys)}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BASE="${HIBOSS_UPDATES_BASE%/}"
MIN_OS="14.0"
BUILD="$(date +%Y%m%d%H%M)"          # monotonic-ish CFBundleVersion
OUT_DIR=".build/release-artifacts"
ZIP="hiboss-$VERSION.zip"
APP="$ROOT_DIR/dist/HiBoss Island.app"

# Locate Sparkle's sign_update from the resolved SwiftPM artifacts.
SIGN_UPDATE="$(/usr/bin/find .build/artifacts -name sign_update -type f -not -path '*old_dsa*' 2>/dev/null | head -1 || true)"
: "${SIGN_UPDATE:?sign_update not found — run 'swift build' first to fetch Sparkle}"

# 1. build the versioned, Sparkle-embedded bundle (feed URL + pubkey baked in).
HIBOSS_VERSION="$VERSION" HIBOSS_BUILD="$BUILD" \
  HIBOSS_APPCAST_URL="$BASE/appcast.xml" \
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

# 2. zip the .app (ditto keeps symlinks/signature intact for Sparkle).
/usr/bin/ditto -c -k --keepParent "$APP" "$OUT_DIR/$ZIP"

# 3. EdDSA-sign the zip → sparkle:edSignature="…" length="…".
SIG_LINE="$("$SIGN_UPDATE" "$OUT_DIR/$ZIP")"
LENGTH="$(printf '%s' "$SIG_LINE" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"

# 4. one-item appcast (Sparkle offers it when newer than the running build).
cat > "$OUT_DIR/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>HiBoss Island</title>
    <item>
      <title>Version $VERSION</title>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[ $NOTES ]]></description>
      <enclosure url="$BASE/$ZIP" $SIG_LINE type="application/zip" />
    </item>
  </channel>
</rss>
XML

# 5. publish zip + appcast to the Worker (stored in R2 behind the upload secret).
curl -fsS -X PUT "$BASE/$ZIP" -H "authorization: Bearer $UPLOAD_SECRET" \
  -H "content-type: application/zip" --data-binary "@$OUT_DIR/$ZIP" >/dev/null
curl -fsS -X PUT "$BASE/appcast.xml" -H "authorization: Bearer $UPLOAD_SECRET" \
  -H "content-type: application/xml" --data-binary "@$OUT_DIR/appcast.xml" >/dev/null

printf 'Published HiBoss Island %s (build %s, %s bytes)\n' "$VERSION" "$BUILD" "$LENGTH"
printf '  feed: %s/appcast.xml\n  zip:  %s/%s\n' "$BASE" "$BASE" "$ZIP"
