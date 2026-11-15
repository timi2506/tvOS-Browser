#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${1:-}"
OUTPUT_IPA="${2:-Browser.ipa}"

if [[ -z "$APP_PATH" ]]; then
    echo "==> No .app path provided. Building Browser for generic/platform=tvOS..."
    BUILD_DIR="$SCRIPT_DIR/build"
    DERIVED_DATA="$BUILD_DIR/DerivedData"
    
    xcodebuild -scheme Browser \
        -destination "generic/platform=tvOS" \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        build
        
    APP_PATH="$DERIVED_DATA/Build/Products/Release-appletvos/Browser.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: Application bundle not found at: $APP_PATH"
    exit 1
fi

chmod +x "$SCRIPT_DIR/stripSignature.sh"

echo "==> Stripping signature..."
"$SCRIPT_DIR/stripSignature.sh" "$APP_PATH"

echo "==> Packaging into $OUTPUT_IPA for sideloading..."
TEMP_DIR="$(mktemp -d)"
PAYLOAD_DIR="$TEMP_DIR/Payload"
mkdir -p "$PAYLOAD_DIR"

cp -RH "$APP_PATH" "$PAYLOAD_DIR/"
find "$PAYLOAD_DIR" -name ".DS_Store" -delete 2>/dev/null || true

if [[ "$OUTPUT_IPA" != /* ]]; then
    OUTPUT_IPA="$SCRIPT_DIR/$OUTPUT_IPA"
fi
rm -f "$OUTPUT_IPA"

(cd "$TEMP_DIR" && zip -qry -9 "$OUTPUT_IPA" Payload -x "*.DS_Store" -x "__MACOSX*")
rm -rf "$TEMP_DIR"

echo "==> Successfully created IPA: $OUTPUT_IPA"
echo "==> Ready for sideloading (AltStore, Sideloadly, TrollStore) and GitHub Releases!"
