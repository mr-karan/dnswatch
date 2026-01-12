#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="DNSWatch"
BUILD_DIR="$ROOT/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
LOCK_KEY=$(printf '%s' "$ROOT" | shasum -a 256 | cut -c1-8)
LOCK_DIR="${TMPDIR:-/tmp}/dnswatch-compile-and-run-${LOCK_KEY}"
LOCK_PID_FILE="$LOCK_DIR/pid"

MARKETING_VERSION="0.0.0"
BUILD_NUMBER="0"
if [ -f "$ROOT/version.env" ]; then
    source "$ROOT/version.env"
fi

acquire_lock() {
    local attempts=0
    while true; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo "$$" > "$LOCK_PID_FILE"
            return 0
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 20 ]; then
            echo "Another build is already running. Remove $LOCK_DIR if stale."
            return 1
        fi
        sleep 0.2
    done
}

release_lock() {
    rm -rf "$LOCK_DIR"
}

kill_instances() {
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    pkill -f "$APP_NAME" 2>/dev/null || true
    for _ in {1..10}; do
        if ! pgrep -f "$APP_NAME" >/dev/null; then
            return 0
        fi
        sleep 0.2
    done
    pkill -9 -f "$APP_NAME" 2>/dev/null || true
}

build_app() {
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    swiftc \
        -g \
        -sdk "$(xcrun --show-sdk-path)" \
        -target arm64-apple-macos14.0 \
        -lpcap \
        -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
        $(find "$ROOT/DNSWatch/Sources" -name "*.swift")
}

update_plist() {
    cp "$ROOT/DNSWatch/Resources/Info.plist" "$APP_BUNDLE/Contents/"
    sed -i '' "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" "$APP_BUNDLE/Contents/Info.plist"
    sed -i '' "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.dnswatch.app/g" "$APP_BUNDLE/Contents/Info.plist"
    sed -i '' "s/\$(PRODUCT_NAME)/$APP_NAME/g" "$APP_BUNDLE/Contents/Info.plist"
    sed -i '' "s/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/g" "$APP_BUNDLE/Contents/Info.plist"

    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" \
        "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $MARKETING_VERSION" \
        "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
        "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" \
        "$APP_BUNDLE/Contents/Info.plist"
}

echo "DNSWatch Development Loop"
echo "=========================="

acquire_lock
trap release_lock EXIT

echo "→ Stopping existing instances..."
kill_instances

echo "→ Building..."
rm -rf "$BUILD_DIR"
build_app
update_plist

if [ ! -r /dev/bpf0 ]; then
    echo ""
    echo "BPF permissions required. Run:"
    echo "  sudo chmod o+r /dev/bpf*"
    echo ""
fi

echo "→ Launching $APP_NAME..."
echo "(Debug output below, Ctrl+C to stop)"
echo ""

"$APP_BUNDLE/Contents/MacOS/$APP_NAME"
