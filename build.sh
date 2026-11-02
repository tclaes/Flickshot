#!/bin/bash
# Builds LightShot.app for Apple Silicon.
#   ./build.sh           build into ./build/LightShot.app
#   ./build.sh install   also copy to /Applications and launch it
set -euo pipefail
cd "$(dirname "$0")"

APP="build/LightShot.app"
VERSION="1.0.0"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/LightShot"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LightShot"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tomclaes.lightshot</string>
    <key>CFBundleName</key><string>LightShot</string>
    <key>CFBundleDisplayName</key><string>LightShot</string>
    <key>CFBundleExecutable</key><string>LightShot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSScreenCaptureUsageDescription</key><string>LightShot captures your screen so you can select and annotate an area.</string>
</dict>
</plist>
PLIST

# A stable signing identity keeps the Screen Recording permission across rebuilds.
# Override with SIGN_IDENTITY="..."; falls back to ad-hoc when no certificate is installed.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [[ -z "$IDENTITY" ]]; then
    echo "No signing certificate found; using ad-hoc signature (permissions reset on every rebuild)"
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --identifier com.tomclaes.lightshot "$APP"
echo "Built $APP (signed with: $IDENTITY)"

if [[ "${1:-}" == "install" ]]; then
    pkill -x LightShot 2>/dev/null || true
    rm -rf /Applications/LightShot.app
    cp -R "$APP" /Applications/
    open /Applications/LightShot.app
    echo "Installed to /Applications/LightShot.app"
fi
