#!/usr/bin/env bash
# build.sh — Build SwitchMac and package it as SwitchMac.app (includes helper)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="SwitchMac"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "▶ Building $APP_NAME (release)…"
swift build -c release

BINARY="$SCRIPT_DIR/.build/release/$APP_NAME"
HELPER_BIN="$SCRIPT_DIR/.build/release/SwitchMacBTHelper"

if [ ! -f "$BINARY" ]; then
    echo "✗ Build failed — binary not found at $BINARY"
    exit 1
fi

echo "▶ Packaging into $APP_NAME.app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY"                    "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist"     "$APP_BUNDLE/Contents/Info.plist"

# Copy helper if present
if [ -f "$HELPER_BIN" ]; then
    echo "  ✓ Including helper: SwitchMacBTHelper"
    cp "$HELPER_BIN" "$APP_BUNDLE/Contents/MacOS/SwitchMacBTHelper"
    chmod +x "$APP_BUNDLE/Contents/MacOS/SwitchMacBTHelper"
else
    echo "  ⚠ Helper not found at $HELPER_BIN — helper will be omitted"
fi

# Ad-hoc code-sign so macOS will run the app without Gatekeeper quarantine
echo "▶ Ad-hoc signing…"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null && echo "  Signed ✓" || echo "  (signing skipped)"

# Create zipped app for distribution/testing
ZIP_PATH="$SCRIPT_DIR/$APP_NAME.app.zip"
rm -f "$ZIP_PATH"
cd "$SCRIPT_DIR" && zip -r "$ZIP_PATH" "${APP_NAME}.app" >/dev/null

echo ""
echo "✅  Done!  App bundle: $APP_BUNDLE"
echo "✅  Zipped app: $ZIP_PATH"
echo ""
echo "  To run:  open '$APP_BUNDLE'"
echo "  Or move the zip to another machine and unzip it there."
echo ""
echo "NOTE: For production distribution sign and notarize the app." 
