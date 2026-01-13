#!/bin/bash
set -euo pipefail

# DNSWatch Packaging Script
# Creates distributable DMG and ZIP files
#
# Usage:
#   ./Scripts/package_app.sh                    # Build only
#   ./Scripts/package_app.sh --sign             # Build + ad-hoc sign
#   ./Scripts/package_app.sh --notarize         # Build + sign + notarize (requires credentials)
#
# Environment variables:
#   VERSION          - Version string (default: from git tag or "1.0.0")
#   SIGNING_IDENTITY - Code signing identity (default: "-" for ad-hoc)

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="DNSWatch"
BUNDLE_ID="com.dnswatch.app"
BUILD_DIR="$ROOT/.build"
DIST_DIR="$ROOT/dist"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT/DNSWatch/Resources/DNSWatch.entitlements"

if [ -f "$ROOT/version.env" ]; then
    source "$ROOT/version.env"
fi

if [ -n "${MARKETING_VERSION:-}" ]; then
    VERSION="${VERSION:-$MARKETING_VERSION}"
else
    VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")}"
fi
VERSION="${VERSION#v}"

if [ -n "${BUILD_NUMBER:-}" ]; then
    BUILD_NUMBER="${BUILD_NUMBER}"
else
    BUILD_NUMBER="$VERSION"
fi

DSYM_DIR="$BUILD_DIR/$APP_NAME.dSYM"
DSYM_ZIP="$DIST_DIR/$APP_NAME-v$VERSION-mac.dSYM.zip"

SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGN_APP=false
NOTARIZE_APP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)
            SIGN_APP=true
            shift
            ;;
        --notarize)
            SIGN_APP=true
            NOTARIZE_APP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "📦 Packaging $APP_NAME v$VERSION"
echo "================================"

# Clean previous builds
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Build release binary
echo "→ Compiling (release mode)..."
ARCHES_VALUE="${ARCHES:-$(uname -m)}"
ARCH_LIST=( ${ARCHES_VALUE} )
BINARIES=()

for ARCH in "${ARCH_LIST[@]}"; do
    ARCH_BUILD_DIR="$BUILD_DIR/$ARCH"
    mkdir -p "$ARCH_BUILD_DIR"
    swiftc \
        -O \
        -whole-module-optimization \
        -sdk "$(xcrun --show-sdk-path)" \
        -target "${ARCH}-apple-macos14.0" \
        -lpcap \
        -o "$ARCH_BUILD_DIR/$APP_NAME" \
        $(find "$ROOT/DNSWatch/Sources" -name "*.swift")
    BINARIES+=("$ARCH_BUILD_DIR/$APP_NAME")
done

if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
else
    lipo -create -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "${BINARIES[@]}"
fi

# Copy and process Info.plist
cp "$ROOT/DNSWatch/Resources/Info.plist" "$APP_BUNDLE/Contents/"
sed -i '' "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" "$APP_BUNDLE/Contents/Info.plist"
sed -i '' "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" "$APP_BUNDLE/Contents/Info.plist"
sed -i '' "s/\$(PRODUCT_NAME)/$APP_NAME/g" "$APP_BUNDLE/Contents/Info.plist"
sed -i '' "s/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/g" "$APP_BUNDLE/Contents/Info.plist"

# Update version in Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

# Copy app icon
cp "$ROOT/DNSWatch/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
mkdir -p "$APP_BUNDLE/Contents/Resources/BPFHelper"
cp "$ROOT/DNSWatch/Resources/BPFHelper/"* "$APP_BUNDLE/Contents/Resources/BPFHelper/"
chmod +x "$APP_BUNDLE/Contents/Resources/BPFHelper/"*.sh

echo "✅ Build complete"

xattr -cr "$APP_BUNDLE"

if command -v dsymutil >/dev/null; then
    dsymutil "$APP_BUNDLE/Contents/MacOS/$APP_NAME" -o "$DSYM_DIR"
    (cd "$BUILD_DIR" && zip -r -q "$DSYM_ZIP" "$APP_NAME.dSYM")
fi

# Sign the app (always ad-hoc sign to prevent "damaged" error on macOS)
echo "→ Signing app..."
if [ "$SIGN_APP" = true ] && [ "$SIGNING_IDENTITY" != "-" ]; then
    # Developer ID signing with entitlements
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
else
    # Ad-hoc signing (required for macOS to not show "damaged" error)
    codesign --force --deep --sign - "$APP_BUNDLE"
fi
echo "✅ Signed"

# Notarize (if requested and credentials available)
if [ "$NOTARIZE_APP" = true ]; then
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
        echo "⚠️  Skipping notarization (APPLE_ID and APPLE_TEAM_ID not set)"
    else
        echo "→ Notarizing..."
        # Create ZIP for notarization
        ditto -c -k --keepParent "$APP_BUNDLE" "$BUILD_DIR/notarize.zip"

        xcrun notarytool submit "$BUILD_DIR/notarize.zip" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --wait

        xcrun stapler staple "$APP_BUNDLE"
        echo "✅ Notarized"
    fi
fi

# Create DMG
echo "→ Creating DMG..."
DMG_NAME="$APP_NAME-v$VERSION-mac.dmg"
DMG_TEMP="$BUILD_DIR/dmg_temp"

mkdir -p "$DMG_TEMP"
cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG with compression
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "$DIST_DIR/$DMG_NAME"

rm -rf "$DMG_TEMP"

# Create ZIP
echo "→ Creating ZIP..."
ZIP_NAME="$APP_NAME-v$VERSION-mac.zip"
(cd "$BUILD_DIR" && zip -r -q -9 "$DIST_DIR/$ZIP_NAME" "$APP_NAME.app")

# Generate checksums
echo "→ Generating checksums..."
(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
(cd "$DIST_DIR" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
if [ -f "$DSYM_ZIP" ]; then
    (cd "$DIST_DIR" && shasum -a 256 "$(basename "$DSYM_ZIP")" > "$(basename "$DSYM_ZIP").sha256")
fi

# Print summary
echo ""
echo "✅ Packaging complete!"
echo ""
echo "Artifacts in $DIST_DIR/:"
ls -lh "$DIST_DIR/"
echo ""
echo "SHA256 checksums:"
cat "$DIST_DIR"/*.sha256
echo ""
echo "To install:"
echo "  1. Open $DIST_DIR/$DMG_NAME"
echo "  2. Drag $APP_NAME to Applications"
echo "  3. Run: sudo /Applications/$APP_NAME.app/Contents/Resources/BPFHelper/install_bpf_helper.sh"
echo "     (Temporary: sudo chmod o+rw /dev/bpf*)"
echo "  4. Launch from Applications"
