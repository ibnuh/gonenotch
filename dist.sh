#!/bin/bash
#
# dist.sh - Build, sign, notarize, and package GoneNotch for distribution
#
# Prerequisites:
#   1. Apple Developer ID Application certificate installed in Keychain
#   2. App-specific password stored in Keychain:
#      xcrun notarytool store-credentials "gonenotch-notarize" \
#        --apple-id "YOUR_APPLE_ID" \
#        --team-id "YOUR_TEAM_ID" \
#        --password "YOUR_APP_SPECIFIC_PASSWORD"
#
# Usage:
#   ./dist.sh                          # Build, sign, notarize, create DMG
#   ./dist.sh --skip-notarize          # Build, sign, create DMG (no notarize)
#   ./dist.sh --identity "Dev ID..."   # Override signing identity
#

set -euo pipefail

APP_NAME="GoneNotch"
BUNDLE_ID="com.ibnuhx.gonenotch"
BUILD_DIR="build"
DIST_DIR="dist"
ENTITLEMENTS="Resources/GoneNotch.entitlements"
NOTARIZE_PROFILE="tasky-notarize"
DMG_VOLUME_NAME="GoneNotch"

# Default signing identity (Developer ID Application)
SIGNING_IDENTITY="Developer ID Application"
SKIP_NOTARIZE=false
BUILD_NUMBER_FLAG=""

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --identity)      shift_next=true ;;
        --build-number=*) BUILD_NUMBER_FLAG="$arg" ;;
        *)
            if [ "${shift_next:-}" = true ]; then
                SIGNING_IDENTITY="$arg"
                shift_next=false
            fi
            ;;
    esac
done

APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

# --------------------------------------------------------------------------
# Step 0: Preflight checks
# --------------------------------------------------------------------------

echo "=== Preflight checks ==="

if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    echo "ERROR: No code signing identity matching '$SIGNING_IDENTITY' found."
    echo ""
    echo "Available identities:"
    security find-identity -v -p codesigning
    echo ""
    echo "If you have not enrolled in the Apple Developer Program, do so at:"
    echo "  https://developer.apple.com/programs/"
    echo ""
    echo "Then download your Developer ID Application certificate from:"
    echo "  https://developer.apple.com/account/resources/certificates/list"
    exit 1
fi

# Resolve the full identity string
RESOLVED_IDENTITY=$(security find-identity -v -p codesigning | grep "$SIGNING_IDENTITY" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Signing identity: $RESOLVED_IDENTITY"

if [ "$SKIP_NOTARIZE" = false ]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" >/dev/null 2>&1; then
        echo "ERROR: Notarization credentials not found."
        echo ""
        echo "Store your credentials with:"
        echo "  xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" \\"
        echo "    --apple-id \"your@email.com\" \\"
        echo "    --team-id \"YOUR_TEAM_ID\" \\"
        echo "    --password \"YOUR_APP_SPECIFIC_PASSWORD\""
        echo ""
        echo "Generate an app-specific password at: https://appleid.apple.com/account/manage"
        echo ""
        echo "Or run with --skip-notarize to skip notarization."
        exit 1
    fi
    echo "Notarization credentials: OK"
fi

# --------------------------------------------------------------------------
# Step 1: Build the app (release mode)
# --------------------------------------------------------------------------

echo ""
echo "=== Building $APP_NAME (release) ==="
./build.sh --release $BUILD_NUMBER_FLAG

if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: Build failed, $APP_BUNDLE not found."
    exit 1
fi

# --------------------------------------------------------------------------
# Step 2: Code sign with Developer ID + hardened runtime
# --------------------------------------------------------------------------

echo ""
echo "=== Code signing ==="

codesign --force --deep --options runtime \
    --sign "$RESOLVED_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1
spctl --assess --type execute --verbose=2 "$APP_BUNDLE" 2>&1 || {
    echo "WARNING: spctl assessment failed. This is expected before notarization."
}

echo "Signature: OK"

# --------------------------------------------------------------------------
# Step 3: Create DMG
# --------------------------------------------------------------------------

echo ""
echo "=== Creating DMG ==="

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

DMG_STAGING=$(mktemp -d)
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

codesign --force --sign "$RESOLVED_IDENTITY" --timestamp "$DMG_PATH"

echo "DMG created: $DMG_PATH"

# --------------------------------------------------------------------------
# Step 4: Notarize
# --------------------------------------------------------------------------

if [ "$SKIP_NOTARIZE" = true ]; then
    echo ""
    echo "=== Skipping notarization (--skip-notarize) ==="
    echo ""
    echo "Done! Output:"
    echo "  App: $APP_BUNDLE"
    echo "  DMG: $DMG_PATH"
    exit 0
fi

echo ""
echo "=== Notarizing ==="
echo "Submitting to Apple (this may take a few minutes)..."

xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARIZE_PROFILE" \
    --wait

echo ""
echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "=== Final verification ==="
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" 2>&1 || true
echo ""

DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo "Done! Distribution ready."
echo ""
echo "  DMG: $DMG_PATH ($DMG_SIZE)"
echo ""
echo "This DMG is signed, notarized, and stapled."
echo "Users can download and open it without Gatekeeper warnings."
