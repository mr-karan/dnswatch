#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

PLIST_ID="com.dnswatch.bpf-permissions"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SUPPORT_DIR="/Library/Application Support/DNSWatch"
HELPER_DEST="$SUPPORT_DIR/bpf-permissions.sh"
PLIST_DEST="/Library/LaunchDaemons/${PLIST_ID}.plist"

USER_NAME="${1:-}"
if [ -z "$USER_NAME" ]; then
    USER_NAME="$(stat -f '%Su' /dev/console 2>/dev/null || true)"
fi

mkdir -p "$SUPPORT_DIR"

install -m 755 -o root -g wheel "$SCRIPT_DIR/bpf-permissions.sh" "$HELPER_DEST"
install -m 644 -o root -g wheel "$SCRIPT_DIR/${PLIST_ID}.plist" "$PLIST_DEST"

if dseditgroup -o read access_bpf >/dev/null 2>&1; then
    if [ -n "$USER_NAME" ]; then
        dseditgroup -o edit -a "$USER_NAME" -t user access_bpf || true
    fi
fi

launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DEST" 2>/dev/null || launchctl load -w "$PLIST_DEST"
launchctl kickstart -k "system/$PLIST_ID" 2>/dev/null || true

"$HELPER_DEST" || true
