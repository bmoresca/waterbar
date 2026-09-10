#!/usr/bin/env bash
# Build WaterBar.app and wrap it in a drag-to-Applications DMG.
#
#   bash WaterBar/package.sh              # build + DMG
#   bash WaterBar/package.sh --notarize   # ...and notarize (needs a Developer ID)
#
# Notarization uses a stored notarytool keychain profile. Create one once with:
#   xcrun notarytool store-credentials waterbar \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
# then export NOTARY_PROFILE=waterbar.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="$HERE/WaterBar.app"
DIST="$ROOT/dist"
VERSION="$(sed -n 's/.*MARKETING_VERSION *= *"\(.*\)".*/\1/p' "$HERE/Sources/WaterBar/Version.swift")"
DMG="$DIST/WaterBar-$VERSION.dmg"
NOTARIZE=false
[ "${1:-}" = "--notarize" ] && NOTARIZE=true

bash "$HERE/build.sh"

mkdir -p "$DIST"
rm -f "$DMG"

# No leading dot: create-dmg copies this into the image's .background
# folder, and Finder refuses to address a dotfile nested in there.
BACKGROUND="$DIST/dmg-background.png"
python3 "$HERE/make_dmg_background.py" "$BACKGROUND" >/dev/null 2>&1 || BACKGROUND=""

# A plain DMG: correct and draggable, just without the styled window. This is
# the fallback whenever create-dmg's Finder scripting is unavailable - it needs
# Automation permission, which CI and fresh machines don't have.
plain_dmg() {
  local stage
  stage="$(mktemp -d)"
  cp -R "$APP" "$stage/"
  ln -s /Applications "$stage/Applications"
  rm -f "$DMG"
  hdiutil create -volname "WaterBar" -srcfolder "$stage" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$stage"
}

echo "==> Building DMG"
if command -v create-dmg >/dev/null; then
  ARGS=(
    --volname "WaterBar"
    --window-pos 200 120 --window-size 600 400
    --icon-size 128
    --icon "WaterBar.app" 150 190
    --app-drop-link 450 190
    --hide-extension "WaterBar.app"
    --no-internet-enable
  )
  [ -f "$BACKGROUND" ] && ARGS+=(--background "$BACKGROUND")
  [ -f "$APP/Contents/Resources/WaterBar.icns" ] && ARGS+=(--volicon "$APP/Contents/Resources/WaterBar.icns")
  if ! create-dmg "${ARGS[@]}" "$DMG" "$APP" || [ ! -f "$DMG" ]; then
    echo "    styled DMG failed (Finder automation unavailable) - plain DMG instead"
    plain_dmg
  fi
else
  echo "    create-dmg not installed (brew install create-dmg) - plain DMG instead"
  plain_dmg
fi
rm -f "$DIST"/rw.*.dmg

# `|| true` matters: with `set -e` and `pipefail`, an empty grep here aborts
# the whole script instead of just meaning "no certificate installed".
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)}"
if [ -n "$IDENTITY" ]; then
  echo "==> Signing DMG"
  codesign --force --sign "$IDENTITY" "$DMG"
fi

if $NOTARIZE; then
  if [ -z "$IDENTITY" ]; then
    echo "==> Cannot notarize: no Developer ID Application certificate in the keychain."
    echo "    Notarization requires a paid Apple Developer Program membership."
    exit 1
  fi
  echo "==> Notarizing (this takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:-waterbar}" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"

echo
echo "==> Gatekeeper verdict"
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/    /' || true

echo
echo "Packaged $DMG"
ls -lh "$DMG" | awk '{print "   ", $5}'
