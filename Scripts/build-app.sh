#!/bin/bash
# Builds MacDirStat.app into ./build (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MacDirStat.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MacDirStat"

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
  <key>CFBundleIdentifier</key><string>com.macdirstat.app</string>
  <key>CFBundleExecutable</key><string>MacDirStat</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
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

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
