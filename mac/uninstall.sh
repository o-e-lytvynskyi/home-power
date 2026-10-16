#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  uninstall.sh  —  Remove HomePower from /Applications
#  Usage:  ./uninstall.sh [--clean]
#            --clean  also drops a .build/ left behind by ./install.sh --dev
# ─────────────────────────────────────────────────────────────
set -euo pipefail

APP_NAME="HomePower"
BUNDLE_ID="dev.local.home-power"
INSTALL_DIR="/Applications"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "→ Stopping $APP_NAME …"
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
    pkill -x "$APP_NAME" 2>/dev/null || true
fi

if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "→ Removing $INSTALL_DIR/$APP_NAME.app …"
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -u "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
else
    echo "   $INSTALL_DIR/$APP_NAME.app not found, skipping"
fi

defaults delete "$BUNDLE_ID" 2>/dev/null || true

if [[ "${1:-}" == "--clean" ]]; then
    rm -rf .build .swiftpm
    echo "   ✓ removed .build/ and .swiftpm/"
fi

echo ""
echo "✅  $APP_NAME uninstalled"
