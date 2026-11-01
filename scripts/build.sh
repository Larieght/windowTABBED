#!/bin/bash
# Builds build/windowTABBED.app and signs it.
#
# Usage: scripts/build.sh [debug|release] [--open]
#
# Signing: macOS remembers the Accessibility permission by the app's signature.
# An ad-hoc signature changes on every build, so you would have to re-allow it each time.
# Create a self-signed "Code Signing" certificate named "windowTABBED Dev" once
# (Keychain Access → Certificate Assistant → Create a Certificate…) and this script
# uses it automatically, so the permission survives rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="debug"
OPEN=0
for arg in "$@"; do
    case "$arg" in
        debug|release) CONFIG="$arg" ;;
        --open) OPEN=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/windowTABBED.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/windowTABBED" "$APP/Contents/MacOS/windowTABBED"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${WT_SIGN_IDENTITY:-windowTABBED Dev}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "Signed with \"$IDENTITY\"."
else
    codesign --force --sign - "$APP"
    echo "Signed ad-hoc. No \"$IDENTITY\" certificate found, so Accessibility must be re-allowed after each build."
fi

echo "Built $APP"

if [ "$OPEN" = 1 ]; then
    pkill -x windowTABBED 2>/dev/null || true
    open "$APP"
fi
