#!/bin/bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

PLIST_ID="com.dnswatch.bpf-permissions"

SUPPORT_DIR="/Library/Application Support/DNSWatch"
HELPER_DEST="$SUPPORT_DIR/bpf-permissions.sh"
PLIST_DEST="/Library/LaunchDaemons/${PLIST_ID}.plist"

launchctl bootout system "$PLIST_DEST" 2>/dev/null || launchctl unload -w "$PLIST_DEST" 2>/dev/null || true

rm -f "$PLIST_DEST" "$HELPER_DEST"
rmdir "$SUPPORT_DIR" 2>/dev/null || true
