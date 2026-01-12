#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree is dirty. Commit or stash changes first."
    exit 1
fi

if [ ! -f "$ROOT/version.env" ]; then
    echo "version.env not found. Create it before releasing."
    exit 1
fi

source "$ROOT/version.env"

if ! grep -q "^## ${MARKETING_VERSION} — Unreleased" "$ROOT/CHANGELOG.md"; then
    echo "CHANGELOG.md must contain '## ${MARKETING_VERSION} — Unreleased'."
    exit 1
fi

if ! command -v swiftformat >/dev/null; then
    echo "swiftformat not found. Install with: brew install swiftformat"
    exit 1
fi

if ! command -v swiftlint >/dev/null; then
    echo "swiftlint not found. Install with: brew install swiftlint"
    exit 1
fi

swiftformat DNSWatch/Sources --lint
swiftlint --strict

"$ROOT/Scripts/package_app.sh" "$@"
