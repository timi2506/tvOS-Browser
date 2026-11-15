#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
    CANDIDATES=(
        "build/DerivedData/Build/Products/Release-appletvos/Browser.app"
        "build/Release-appletvos/Browser.app"
        "Browser.app"
    )
    for c in "${CANDIDATES[@]}"; do
        if [[ -d "$c" ]]; then
            APP_PATH="$c"
            break
        fi
    done
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "Usage: $0 <path-to-app.app>"
    echo "Error: Application bundle not found or not specified."
    exit 1
fi

echo "==> Stripping signature from: $APP_PATH"

find "$APP_PATH" -name "embedded.mobileprovision" -exec rm -f {} + 2>/dev/null || true
find "$APP_PATH" -name "*.xcent" -exec rm -f {} + 2>/dev/null || true

find "$APP_PATH" -type f | while IFS= read -r file; do
    if file -b "$file" | grep -q "Mach-O"; then
        codesign --remove-signature "$file" 2>/dev/null || true
    fi
done

codesign --remove-signature "$APP_PATH" 2>/dev/null || true
find "$APP_PATH" -depth -name "_CodeSignature" -exec rm -rf {} + 2>/dev/null || true

if ! codesign -v "$APP_PATH" 2>/dev/null; then
    echo "==> Successfully stripped signature: $APP_PATH is unsigned."
else
    echo "==> Warning: Bundle may still contain signatures."
fi
