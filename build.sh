#!/usr/bin/env bash
# build.sh — Build SwitchMac and package it as SwitchMac.app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="SwitchMac"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "▶ Building $APP_NAME (release)…"
swift build -c release 2>&1

BINARY="$SCRIPT_DIR/.build/release/$APP_NAME"

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

# Ad-hoc code-sign so macOS will run the app without Gatekeeper quarantine
echo "▶ Ad-hoc signing…"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null && echo "  Signed ✓" || echo "  (signing skipped)"

echo ""
echo "✅  Done!  App bundle: $APP_BUNDLE"
echo ""
echo "  To run:  open '$APP_BUNDLE'"
echo "  Or drag SwitchMac.app to your Applications folder."
echo ""
echo "NOTE: Install SwitchMac on all 3 Macs. On first launch, select your"
echo "      Magic Keyboard from the menu (the keyboard must already be paired"
echo "      with each Mac via Bluetooth Settings beforehand)."
