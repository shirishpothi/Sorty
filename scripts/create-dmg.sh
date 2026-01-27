#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"
APP_PATH="$RELEASE_DIR/Sorty.app"
DMG_NAME="Sorty.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
VOLUME_NAME="Sorty"
BACKGROUND_IMG="$PROJECT_ROOT/Resources/dmg-background.png"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Sorty.app not found at $APP_PATH"
    echo "   Run 'make build' first."
    exit 1
fi

echo "📦 Creating DMG..."

rm -f "$DMG_PATH"

TEMP_DMG="$PROJECT_ROOT/releases/temp_sorty.dmg"
MOUNT_POINT="/Volumes/$VOLUME_NAME"

hdiutil create -srcfolder "$APP_PATH" -volname "$VOLUME_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size 200m "$TEMP_DMG"

hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_POINT" -noautoopen

if [ -f "$BACKGROUND_IMG" ]; then
    mkdir -p "$MOUNT_POINT/.background"
    cp "$BACKGROUND_IMG" "$MOUNT_POINT/.background/background.png"
fi

ln -s /Applications "$MOUNT_POINT/Applications"

echo '
   tell application "Finder"
     tell disk "'$VOLUME_NAME'"
       open
       set current view of container window to icon view
       set toolbar visible of container window to false
       set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1100, 600}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:background.png"
        set position of item "Sorty.app" of container window to {175, 250}
        set position of item "Applications" of container window to {525, 250}
       close
       open
       update without registering applications
       delay 2
     end tell
   end tell
' | osascript

sync

hdiutil detach "$MOUNT_POINT"

hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

rm -f "$TEMP_DMG"

echo "✅ DMG created: $DMG_PATH"
