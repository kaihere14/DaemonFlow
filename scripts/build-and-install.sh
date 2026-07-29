#!/bin/bash
# Builds DaemonFlow in Release configuration and installs it to /Applications.
#
# Usage: ./scripts/build-and-install.sh
#
# Notes:
# - Requires Vendor/whisper-libs to already exist (run build-whisper.sh first
#   on a fresh checkout).
# - This app is ad-hoc signed (no paid Apple Developer account configured).
#   Every new build produces a distinct code signature, which means macOS
#   TCC treats it as a different app: Accessibility, Input Monitoring, and
#   Microphone permissions must be re-granted after each install. The app's
#   own onboarding walks you through that on first launch.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DaemonFlow.app"
INSTALL_PATH="/Applications/$APP_NAME"

if [[ -d /Applications/Xcode-beta.app && ! -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

echo "--- Building Release configuration ---"
xcodebuild -project "$PROJECT_DIR/DaemonFlow.xcodeproj" \
    -scheme DaemonFlow \
    -configuration Release \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    build

BUILT_APP=$(xcodebuild -project "$PROJECT_DIR/DaemonFlow.xcodeproj" \
    -scheme DaemonFlow \
    -configuration Release \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/$APP_NAME

if [[ ! -d "$BUILT_APP" ]]; then
    echo "error: built app not found at $BUILT_APP" >&2
    exit 1
fi

echo "--- Installing to $INSTALL_PATH ---"
osascript -e 'tell application "DaemonFlow" to quit' 2>/dev/null || true
pkill -f "$INSTALL_PATH/Contents/MacOS/DaemonFlow" 2>/dev/null || true

rm -rf "$INSTALL_PATH"
ditto "$BUILT_APP" "$INSTALL_PATH"

echo "--- Done ---"
echo "Installed: $INSTALL_PATH"
echo "Launch it from /Applications or Spotlight. First launch will walk"
echo "through granting Accessibility, Input Monitoring, and Microphone."
