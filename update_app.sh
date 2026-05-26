#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dual Finder"
BUNDLE_ID="com.local.dualfinder"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
INSTALL_PATH="/Applications/$APP_NAME.app"
ICONSET="$RELEASE_DIR/DualFinder.iconset"
ICNS="$RESOURCES_DIR/DualFinder.icns"

echo "[1/7] Running tests"
swift test --package-path "$ROOT_DIR"

echo "[2/7] Building release binary"
swift build --package-path "$ROOT_DIR" -c release

echo "[3/7] Creating app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/DualFinderApp" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>DualFinder</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Local development build</string>
</dict>
</plist>
PLIST

echo "[4/7] Generating transparent rounded icon"
swift "$ROOT_DIR/tools/generate_icon.swift" "$ICONSET"
iconutil --convert icns "$ICONSET" --output "$ICNS"

echo "[5/7] Signing app ad-hoc"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "[6/7] Replacing /Applications build"
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x "DualFinderApp" 2>/dev/null || true
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

echo "[7/7] Launching from /Applications"
open "$INSTALL_PATH"
echo "Installed and launched: $INSTALL_PATH"
