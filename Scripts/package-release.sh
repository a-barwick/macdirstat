#!/bin/bash
# Builds release artifacts: build/MacDirStat-<version>.dmg and .zip
#
# Unsigned (ad-hoc) by default. If these are set, it signs with a Developer ID and notarizes instead:
#   DEVELOPER_ID_IDENTITY   e.g. "Developer ID Application: Jane Doe (TEAMID1234)" (must be in the keychain)
#   NOTARY_KEY_PATH         path to an App Store Connect API key (.p8)
#   NOTARY_KEY_ID, NOTARY_ISSUER_ID
#
# Usage: VERSION=1.2.0 ./Scripts/package-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
export VERSION
APP="build/MacDirStat.app"
DMG="build/MacDirStat-${VERSION}.dmg"
ZIP="build/MacDirStat-${VERSION}.zip"

./Scripts/build-app.sh

SIGNED=0
if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
  echo "Signing with: $DEVELOPER_ID_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$APP/Contents/MacOS/MacDirStat"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  SIGNED=1
else
  echo "No DEVELOPER_ID_IDENTITY set: shipping an ad-hoc signed (unsigned) build."
fi

# Zip (for people who prefer it, and for Homebrew-style installs)
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# DMG with the usual drag-to-Applications layout
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "MacDirStat" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [ "$SIGNED" = 1 ]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$DMG"
  if [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    echo "Notarizing…"
    xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" --wait
    xcrun stapler staple "$DMG"
    # Staple the app inside the zip too, so it opens cleanly offline.
    xcrun notarytool submit "$ZIP" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
  else
    echo "Signed but not notarized (no NOTARY_* settings); Gatekeeper will still warn." >&2
  fi
fi

echo "Packaged $DMG and $ZIP"
