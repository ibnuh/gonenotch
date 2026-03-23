#!/bin/bash
set -e

APP_NAME="GoneNotch"
BUILD_DIR="build"

# Parse flags
SWIFT_FLAGS=""
BUILD_MODE="debug"
CUSTOM_BUILD_NUMBER=""
for arg in "$@"; do
    case "$arg" in
        --release) BUILD_MODE="release" ;;
        --build-number=*) CUSTOM_BUILD_NUMBER="${arg#*=}" ;;
    esac
done

if [ "$BUILD_MODE" = "debug" ]; then
    SWIFT_FLAGS="-DDEBUG"
else
    SWIFT_FLAGS="-O -warnings-as-errors"
fi

# Auto-download Sparkle framework if missing
SPARKLE_VERSION="2.9.0"
if [ ! -d "Frameworks/Sparkle.framework" ]; then
    echo "Downloading Sparkle $SPARKLE_VERSION..."
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" -o /tmp/sparkle.tar.xz
    mkdir -p Frameworks
    tar -xf /tmp/sparkle.tar.xz -C Frameworks
    rm /tmp/sparkle.tar.xz
    echo "Sparkle $SPARKLE_VERSION downloaded."
fi

APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Clean
rm -rf "$APP_BUNDLE"

# Create app bundle structure
mkdir -p "$MACOS" "$RESOURCES"

# Source files
SOURCES=(
  Sources/main.swift
  Sources/AppDelegate.swift
  Sources/DisplayManager.swift
  Sources/LoginItemManager.swift
  Sources/SettingsWindow.swift
)

FRAMEWORKS="-framework Cocoa -framework Carbon -framework CoreGraphics -framework SwiftUI -framework ServiceManagement -framework Sparkle"
SPARKLE_DIR="Frameworks"
SDK="$(xcrun --show-sdk-path)"

# Build universal binary (arm64 + x86_64)
swiftc \
  -target arm64-apple-macosx12.0 \
  -sdk "$SDK" \
  -F "$SPARKLE_DIR" \
  $FRAMEWORKS \
  $SWIFT_FLAGS \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$BUILD_DIR/GoneNotch-arm64" \
  "${SOURCES[@]}"

swiftc \
  -target x86_64-apple-macosx12.0 \
  -sdk "$SDK" \
  -F "$SPARKLE_DIR" \
  $FRAMEWORKS \
  $SWIFT_FLAGS \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$BUILD_DIR/GoneNotch-x86_64" \
  "${SOURCES[@]}"

lipo -create "$BUILD_DIR/GoneNotch-arm64" "$BUILD_DIR/GoneNotch-x86_64" -output "$MACOS/$APP_NAME"
rm -f "$BUILD_DIR/GoneNotch-arm64" "$BUILD_DIR/GoneNotch-x86_64"

# Embed Sparkle.framework
FRAMEWORKS_DEST="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS_DEST"
cp -R "$SPARKLE_DIR/Sparkle.framework" "$FRAMEWORKS_DEST/"

# Derive build number from git commit count, or use custom override
if [ -n "$CUSTOM_BUILD_NUMBER" ]; then
    BUILD_NUMBER="$CUSTOM_BUILD_NUMBER"
else
    BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
fi

# Generate resolved Info.plist (replace template variables with actual values)
sed -e "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.ibnuhx.gonenotch/g" \
    -e "s/\$(PRODUCT_NAME)/$APP_NAME/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/12.0/g" \
    Resources/Info.plist > "$CONTENTS/Info.plist"

# Replace CFBundleVersion with auto-incremented build number from git
sed -i '' "/<key>CFBundleVersion<\/key>/{n;s/<string>[0-9]*<\/string>/<string>$BUILD_NUMBER<\/string>/;}" "$CONTENTS/Info.plist"

# Write PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Copy app icon
if [ -f "Resources/GoneNotch.icns" ]; then
  cp "Resources/GoneNotch.icns" "$RESOURCES/"
fi

# Copy menu bar template images
for f in Resources/menubar*.png; do
  [ -f "$f" ] && cp "$f" "$RESOURCES/"
done

# Pick signing identity: prefer Developer ID Application, fall back to GoneNotchDev self-signed.
SIGNING_IDENTITY=""
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    SIGNING_IDENTITY="Developer ID Application"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "GoneNotchDev"; then
    SIGNING_IDENTITY="GoneNotchDev"
fi

# If no persistent certificate exists, create a self-signed one.
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="GoneNotchDev"
    echo "Creating self-signed code signing certificate '$SIGNING_IDENTITY'..."
    echo "This is a one-time setup to maintain trust across rebuilds."
    echo ""

    CERT_CONFIG=$(mktemp).cfg
    CERT_PEM=$(mktemp).pem
    KEY_PEM=$(mktemp).pem
    CERT_P12=$(mktemp).p12

    cat > "$CERT_CONFIG" <<CERTEOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = codesign

[ dn ]
CN = $SIGNING_IDENTITY

[ codesign ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CERTEOF

    openssl req -x509 -newkey rsa:2048 \
        -keyout "$KEY_PEM" -out "$CERT_PEM" \
        -days 3650 -nodes \
        -config "$CERT_CONFIG" 2>/dev/null

    openssl pkcs12 -export \
        -out "$CERT_P12" \
        -inkey "$KEY_PEM" -in "$CERT_PEM" \
        -passout pass:gonenotch-build \
        -legacy 2>/dev/null

    security import "$CERT_P12" \
        -k ~/Library/Keychains/login.keychain-db \
        -P "gonenotch-build" -T /usr/bin/codesign

    security find-certificate -c "$SIGNING_IDENTITY" -p \
        ~/Library/Keychains/login.keychain-db > "$CERT_PEM"
    security add-trusted-cert -d -r trustRoot -p codeSign \
        -k ~/Library/Keychains/login.keychain-db "$CERT_PEM" 2>/dev/null || {
        echo ""
        echo "Could not auto-trust certificate. Please open Keychain Access,"
        echo "find '$SIGNING_IDENTITY', double-click -> Trust -> Code Signing -> 'Always Trust'."
    }

    rm -f "$CERT_CONFIG" "$CERT_PEM" "$KEY_PEM" "$CERT_P12"

    echo ""
    echo "Certificate '$SIGNING_IDENTITY' created and trusted for code signing."
    echo ""
fi

# Sign Sparkle.framework components inside-out
SPARKLE_FW="$CONTENTS/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --preserve-metadata=entitlements,identifier,flags "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" 2>/dev/null || true
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --preserve-metadata=entitlements,identifier,flags "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null || true
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --preserve-metadata=entitlements,identifier "$SPARKLE_FW/Versions/B/Autoupdate" 2>/dev/null || true
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --preserve-metadata=entitlements,identifier "$SPARKLE_FW/Versions/B/Updater.app" 2>/dev/null || true
codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$SPARKLE_FW" 2>/dev/null || true

# Sign with the chosen identity; fall back to ad-hoc if signing fails
if codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$APP_BUNDLE" 2>/dev/null; then
    echo "Build complete: $APP_BUNDLE ($BUILD_MODE, signed with '$SIGNING_IDENTITY')"
else
    echo "Warning: Could not sign with '$SIGNING_IDENTITY', falling back to ad-hoc."
    codesign --force --sign - "$APP_BUNDLE"
    echo ""
    echo "Build complete: $APP_BUNDLE ($BUILD_MODE, ad-hoc signed)"
fi

echo ""
echo "To run:  open $APP_BUNDLE"
