#!/usr/bin/env bash
# Build WaterBar.app as a universal (arm64 + x86_64) bundle.
#
# Signing is automatic: if a "Developer ID Application" certificate is in your
# keychain it signs properly with the hardened runtime, otherwise it falls back
# to an ad-hoc signature, which runs fine locally but makes Gatekeeper complain
# on someone else's Mac. See docs/DISTRIBUTION.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HERE/WaterBar.app"
VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION *= *"\(.*\)".*/\1/p' "$HERE/Sources/WaterBar/Version.swift")}"

echo "==> Compiling universal binary (arm64 + x86_64)"
swift build -c release --package-path "$HERE" --arch arm64 --arch x86_64
BIN="$(swift build -c release --package-path "$HERE" --arch arm64 --arch x86_64 --show-bin-path)/WaterBar"
lipo -archs "$BIN"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WaterBar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>WaterBar</string>
  <key>CFBundleIconFile</key><string>WaterBar</string>
  <key>CFBundleIdentifier</key><string>com.betomoresca.waterbar</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>WaterBar</string>
  <key>CFBundleDisplayName</key><string>WaterBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Estimates only. Nothing here is measured.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Icon"
if python3 -c "import PIL" 2>/dev/null && command -v iconutil >/dev/null; then
  python3 "$HERE/make_icon.py" "$APP/Contents/Resources/WaterBar.icns" >/dev/null
  rm -rf "$APP/Contents/Resources/WaterBar.iconset"
  echo "    drawn"
else
  echo "    skipped (needs Pillow and iconutil)"
fi

# Tells plugin/hooks/water-hook.sh that this bundle understands CLI
# subcommands. Older bundles without it are skipped rather than hung on.
echo "1" > "$APP/Contents/Resources/cli-engine"

echo "==> Signing"
# `|| true` matters: with `set -e` and `pipefail`, an empty grep here aborts
# the whole script instead of just meaning "no certificate installed".
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)}"

if [ -n "$IDENTITY" ]; then
  echo "    Developer ID: $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
else
  echo "    no Developer ID certificate found - signing ad-hoc"
  echo "    (runs locally; other Macs will need the quarantine workaround)"
  codesign --force --deep --sign - "$APP" 2>/dev/null || echo "    codesign unavailable"
fi

echo
echo "Built $APP  (v$VERSION)"
