#!/usr/bin/env bash
# Builds Tarjem.app (menu-bar app) into ./build.
#
#   ./scripts/build-app.sh            # native architecture
#   UNIVERSAL=1 ./scripts/build-app.sh  # Apple Silicon + Intel (needs Xcode)
#   ./scripts/build-app.sh --install  # also copy to /Applications and launch
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Tarjem"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

ARGS=(-c release --product "$APP_NAME")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARGS+=(--arch arm64 --arch x86_64)
fi

echo "▸ Building $APP_NAME (${ARGS[*]})"
swift build "${ARGS[@]}"
BIN_DIR="$(swift build "${ARGS[@]}" --show-bin-path)"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

# Ad-hoc signature so macOS can track the Screen Recording permission.
# Set SIGN_IDENTITY="Developer ID Application: …" to sign with a real certificate
# (hardened runtime, ready for notarization).
echo "▸ Signing"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi

echo "▸ Packaging $BUILD_DIR/$APP_NAME.zip"
rm -f "$BUILD_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/$APP_NAME.zip"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Installing to /Applications"
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$APP_NAME.app"
fi

echo "✓ Done: $APP"
