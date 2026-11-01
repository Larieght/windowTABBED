#!/bin/bash
# Builds build/windowTABBED.app and signs it.
#
# Usage: scripts/build.sh [debug|release] [--open] [--install]
#   --open     relaunch the app after building
#   --install  copy it to /Applications and run that copy (implies --open)
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
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        debug|release) CONFIG="$arg" ;;
        --open) OPEN=1 ;;
        --install) INSTALL=1; OPEN=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# SwiftPM records the deployment target (macOS 14) as the SDK the app was built with. macOS keeps
# the pre-26 look (old title bar and traffic lights) for apps built with an older SDK, so record
# the SDK we actually build with.
SDK_VERSION="$(xcrun --show-sdk-version)"
LINK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")
swift build -c "$CONFIG" "${LINK_FLAGS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${LINK_FLAGS[@]}" --show-bin-path)"

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
    if [ "$INSTALL" = 1 ]; then
        rm -rf "/Applications/windowTABBED.app"
        cp -R "$APP" "/Applications/windowTABBED.app"
        APP="/Applications/windowTABBED.app"
        echo "Installed $APP"
    fi
    open "$APP"
fi
