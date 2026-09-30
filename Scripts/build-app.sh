#!/bin/bash
# Builds MacDirStat.app into ./build (release, ad-hoc signed).
# Optional env: VERSION, BUILD_NUMBER, BUNDLE_ID, UNIVERSAL=1 (arm64 + x86_64).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MacDirStat.app"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-io.github.a-barwick.macdirstat}"
# UNIVERSAL=1 builds for Apple silicon + Intel: one build per architecture, merged with lipo.
if [ "${UNIVERSAL:-0}" = 1 ]; then
  BIN="build/MacDirStat-universal"
  mkdir -p build
  SLICES=()
  for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx14.0"
    SLICES+=("$(swift build -c release --triple "$ARCH-apple-macosx14.0" --show-bin-path)/MacDirStat")
  done
  lipo -create "${SLICES[@]}" -output "$BIN"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/MacDirStat"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacDirStat"

ICONSET="build/AppIcon.iconset"
if [ ! -f build/AppIcon.icns ] || [ Scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  rm -rf "$ICONSET"
  swift Scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacDirStat</string>
  <key>CFBundleDisplayName</key><string>MacDirStat</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>MacDirStat</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with WinDirStat.</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Folder</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string><string>public.volume</string></array>
  </dict></array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
