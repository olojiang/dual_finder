#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dual Finder 纪"
BUNDLE_ID="com.local.dualfinder"
APP_VERSION="0.1.18"
APP_BUILD="18"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
INSTALL_PATH="/Applications/$APP_NAME.app"
ICONSET="$RELEASE_DIR/DualFinder.iconset"
ICNS="$RESOURCES_DIR/DualFinder.icns"
APPLE_KEYS_DIR="${APPLE_KEYS_DIR:-$ROOT_DIR/signing/apple_keys}"
SIGNING_IDENTITY=""
SIGNING_KEYCHAIN_PATH=""
PREPARED_SIGNING_IDENTITY=""

prepare_apple_signing_identity() {
    local metadata_env="$APPLE_KEYS_DIR/apple_key_metadata.env"
    local secrets_env="$APPLE_KEYS_DIR/apple_key_secrets.env"

    if [[ ! -f "$metadata_env" || ! -f "$secrets_env" ]]; then
        return 1
    fi

    # shellcheck disable=SC1090
    source "$metadata_env"
    # shellcheck disable=SC1090
    source "$secrets_env"

    local local_modern_p12="$APPLE_KEYS_DIR/developer_id_application_pine_field_modern.p12"
    if [[ -f "$local_modern_p12" ]]; then
        MODERN_P12="$local_modern_p12"
    fi
    [[ -n "${APPLE_CERTIFICATE_ID:-}" && -f "${MODERN_P12:-}" && -n "${APPLE_CERTIFICATE_PASSWORD:-}" ]] || return 1

    local keychain_name="${KEYCHAIN_NAME:-apple-build-signing.keychain-db}"
    local keychain_password="${KEYCHAIN_PASSWORD:-$APPLE_CERTIFICATE_PASSWORD}"
    local keychain_path="$HOME/Library/Keychains/$keychain_name"

    if [[ -f "$keychain_path" ]]; then
        echo "Using signing keychain: $keychain_path" >&2
    else
        echo "Creating signing keychain: $keychain_path" >&2
        security create-keychain -p "$keychain_password" "$keychain_path"
    fi

    security unlock-keychain -p "$keychain_password" "$keychain_path"
    security set-keychain-settings -lut 21600 "$keychain_path"

    local existing_keychains=()
    local keychain
    while IFS= read -r keychain; do
        existing_keychains+=("$keychain")
    done < <(security list-keychains -d user | sed 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/\1/')

    if ! printf '%s\n' "${existing_keychains[@]}" | grep -Fx "$keychain_path" >/dev/null; then
        security list-keychains -d user -s "$keychain_path" "${existing_keychains[@]}"
    fi

    if security find-identity -v -p codesigning "$keychain_path" | grep -F "$APPLE_CERTIFICATE_ID" >/dev/null; then
        echo "Signing identity already present: $APPLE_CERTIFICATE_ID" >&2
    else
        echo "Importing signing identity: $APPLE_CERTIFICATE_ID" >&2
        security import "$MODERN_P12" \
            -f pkcs12 \
            -k "$keychain_path" \
            -P "$APPLE_CERTIFICATE_PASSWORD" \
            -T /usr/bin/codesign >/dev/null
    fi

    security set-key-partition-list \
        -S apple-tool:,apple:,codesign: \
        -s \
        -k "$keychain_password" \
        "$keychain_path" >/dev/null

    security find-identity -v -p codesigning "$keychain_path" | grep -F "$APPLE_CERTIFICATE_ID" >/dev/null || return 1
    SIGNING_KEYCHAIN_PATH="$keychain_path"
    PREPARED_SIGNING_IDENTITY="$APPLE_CERTIFICATE_ID"
}

select_codesign_identity() {
    if [[ -n "${DUAL_FINDER_CODESIGN_IDENTITY:-}" ]]; then
        SIGNING_IDENTITY="$DUAL_FINDER_CODESIGN_IDENTITY"
        return
    fi

    if prepare_apple_signing_identity; then
        SIGNING_IDENTITY="$PREPARED_SIGNING_IDENTITY"
        return
    fi

    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

    local identity
    identity="$(
        printf '%s\n' "$identities" |
            sed -nE 's/^ *[0-9]+\) [A-F0-9]+ "([^"]*Apple Development[^"]*)".*/\1/p' |
            head -n 1
    )"
    if [[ -z "$identity" ]]; then
        identity="$(
            printf '%s\n' "$identities" |
                sed -nE 's/^ *[0-9]+\) [A-F0-9]+ "([^"]*Developer ID Application[^"]*)".*/\1/p' |
                head -n 1
        )"
    fi

    SIGNING_IDENTITY="${identity:--}"
}

codesign_app_bundle() {
    local target="$1"
    local args=(--force --timestamp=none --options runtime --sign "$SIGNING_IDENTITY")
    if [[ -n "$SIGNING_KEYCHAIN_PATH" ]]; then
        args+=(--keychain "$SIGNING_KEYCHAIN_PATH")
    fi
    codesign "${args[@]}" "$target"
}

echo "[1/7] Running tests"
swift test --package-path "$ROOT_DIR"

echo "[2/7] Building release binaries"
swift build --package-path "$ROOT_DIR" -c release --product DualFinderApp
swift build --package-path "$ROOT_DIR" -c release --product DualFinderHotkeyHelper

echo "[3/7] Creating app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/DualFinderApp" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

HELPER_APP_NAME="DualFinderHotkeyHelper"
HELPER_APP="$RELEASE_DIR/$HELPER_APP_NAME.app"
HELPER_MACOS="$HELPER_APP/Contents/MacOS"
mkdir -p "$HELPER_MACOS"
cp "$ROOT_DIR/.build/release/DualFinderHotkeyHelper" "$HELPER_MACOS/$HELPER_APP_NAME"
chmod +x "$HELPER_MACOS/$HELPER_APP_NAME"

cat > "$HELPER_APP/Contents/Info.plist" <<HELPER_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DualFinderHotkeyHelper</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.dualfinder.hotkey-helper</string>
    <key>CFBundleName</key>
    <string>DualFinderHotkeyHelper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
HELPER_PLIST

mkdir -p "$CONTENTS/Library/LoginItems"
rm -rf "$CONTENTS/Library/LoginItems/$HELPER_APP_NAME.app"
cp -R "$HELPER_APP" "$CONTENTS/Library/LoginItems/$HELPER_APP_NAME.app"

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
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
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

select_codesign_identity
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "[5/7] Signing app ad-hoc"
    echo "warning: no stable codesigning identity found; macOS privacy permissions may need re-approval after each build."
else
    echo "[5/7] Signing app with: $SIGNING_IDENTITY"
fi

codesign_app_bundle "$CONTENTS/Library/LoginItems/$HELPER_APP_NAME.app"
codesign_app_bundle "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "[6/7] Replacing /Applications build"
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x "Dual Finder" 2>/dev/null || true
pkill -x "DualFinderApp" 2>/dev/null || true
pkill -x "DualFinderHotkeyHelper" 2>/dev/null || true
pkill -f "com.local.dualfinder.hotkey-helper" 2>/dev/null || true
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

echo "[7/7] Launching from /Applications"
open "$INSTALL_PATH"
echo "Installed and launched: $INSTALL_PATH"
