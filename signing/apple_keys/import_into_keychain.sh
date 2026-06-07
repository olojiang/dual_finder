#!/usr/bin/env bash
set -euo pipefail

APPLE_KEYS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA_ENV="$APPLE_KEYS_DIR/apple_key_metadata.env"
SECRETS_ENV="$APPLE_KEYS_DIR/apple_key_secrets.env"

if [ ! -f "$METADATA_ENV" ] || [ ! -f "$SECRETS_ENV" ]; then
  echo "ERROR: missing metadata/secrets. Run collect_and_convert.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$METADATA_ENV"
# shellcheck disable=SC1090
source "$SECRETS_ENV"

KEYCHAIN_NAME="${KEYCHAIN_NAME:-apple-build-signing.keychain-db}"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$APPLE_CERTIFICATE_PASSWORD}"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN_NAME"

require_file() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    echo "ERROR: missing $label: $path" >&2
    exit 1
  fi
}

LOCAL_MODERN_P12="$APPLE_KEYS_DIR/developer_id_application_pine_field_modern.p12"
if [ -f "$LOCAL_MODERN_P12" ]; then
  MODERN_P12="$LOCAL_MODERN_P12"
fi

require_file "$MODERN_P12" "modern PKCS#12"

identity_available() {
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -F "$APPLE_CERTIFICATE_ID" >/dev/null
}

if [ -f "$KEYCHAIN_PATH" ]; then
  echo "Using existing keychain: $KEYCHAIN_PATH"
else
  echo "Creating keychain: $KEYCHAIN_PATH"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"

existing_keychains=()
while IFS= read -r keychain; do
  existing_keychains+=("$keychain")
done < <(security list-keychains -d user | sed 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/\1/')

if ! printf '%s\n' "${existing_keychains[@]}" | grep -Fx "$KEYCHAIN_PATH" >/dev/null; then
  security list-keychains -d user -s "$KEYCHAIN_PATH" "${existing_keychains[@]}"
fi

if identity_available; then
  echo "Signing identity already present; skipping duplicate import."
else
  security import "$MODERN_P12" \
    -f pkcs12 \
    -k "$KEYCHAIN_PATH" \
    -P "$APPLE_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign >/dev/null
fi

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" >/dev/null

echo "Signing identity available in: $KEYCHAIN_PATH"
security find-identity -v -p codesigning "$KEYCHAIN_PATH"

if identity_available; then
  echo "Verification passed: $APPLE_CERTIFICATE_ID is available for codesign."
else
  echo "ERROR: expected identity not found: $APPLE_CERTIFICATE_ID" >&2
  exit 1
fi
