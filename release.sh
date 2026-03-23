#!/bin/bash
set -e

# Release script: builds GoneNotch, creates a signed DMG, updates appcast.xml,
# and copies the DMG to the web project.
#
# Usage: ./release.sh [--notes "Release notes here"]

APP_BUNDLE="build/GoneNotch.app"
DMG_PATH="build/GoneNotch.dmg"
WEB_PROJECT="../ibnuhx.com/apps/gonenotch"
WEB_APPCAST="$WEB_PROJECT/public/appcast.xml"
WEB_DOWNLOADS="$WEB_PROJECT/public/downloads"

# Parse optional release notes
RELEASE_NOTES="Bug fixes and improvements."
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes) RELEASE_NOTES="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Verify web project exists
if [ ! -d "$WEB_PROJECT" ]; then
    echo "Error: Web project not found at $WEB_PROJECT"
    echo "Expected: ../ibnuhx.com/apps/gonenotch"
    exit 1
fi

# Build release
echo "Building release..."
./build.sh --release

# Read version info from the built plist
PLIST="$APP_BUNDLE/Contents/Info.plist"
SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")

echo "Version: $SHORT_VERSION ($BUILD_NUMBER)"

# Create DMG
echo "Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "GoneNotch" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

# Sign the DMG with Sparkle EdDSA key
echo "Signing update..."
SIGN_OUTPUT=$(./Frameworks/bin/sign_update "$DMG_PATH")
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

echo "Signed: $DMG_PATH"
echo "EdDSA Signature: $ED_SIGNATURE"
echo "Length: $LENGTH bytes"

# Generate appcast.xml
PUB_DATE=$(date -R)

echo "Writing appcast.xml..."
cat > "$WEB_APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>GoneNotch Changelog</title>
        <description>Updates for GoneNotch.</description>
        <language>en</language>
        <item>
            <title>Version $SHORT_VERSION</title>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$SHORT_VERSION</sparkle:shortVersionString>
            <description><![CDATA[
                <h2>GoneNotch $SHORT_VERSION</h2>
                <p>$RELEASE_NOTES</p>
            ]]></description>
            <pubDate>$PUB_DATE</pubDate>
            <enclosure
                url="https://ibnuhx.com/gonenotch/downloads/GoneNotch.dmg"
                type="application/octet-stream"
                sparkle:edSignature="$ED_SIGNATURE"
                length="$LENGTH"
            />
            <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
        </item>
    </channel>
</rss>
EOF

# Copy DMG to web project downloads
echo "Copying DMG to web project..."
mkdir -p "$WEB_DOWNLOADS"
cp "$DMG_PATH" "$WEB_DOWNLOADS/GoneNotch.dmg"

# Also keep a local copy of appcast.xml in sync
cp "$WEB_APPCAST" appcast.xml

echo ""
echo "Done! Version $SHORT_VERSION ($BUILD_NUMBER)"
echo ""
echo "Updated files:"
echo "  $WEB_APPCAST"
echo "  $WEB_DOWNLOADS/GoneNotch.dmg"
echo ""
echo "Next: deploy the web project to publish the update."
