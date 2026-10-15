#!/bin/bash
# Build MeetPaw.app and package it into a styled, drag-to-install MeetPaw.dmg
# (white window with a grid background, app on the left, Applications on the right).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VOL="MeetPaw"
APP="MeetPaw.app"
DMG="MeetPaw.dmg"
RW="$(mktemp -u).dmg"

swift Scripts/makedmgbg.swift Resources/dmg-bg.png

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp Resources/dmg-bg.png "$STAGE/.background/bg.png"

rm -f "$RW" "$DMG"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
rm -rf "$STAGE"

# Mount read-write and capture the device node for a clean detach later.
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | egrep '^/dev/' | head -1 | awk '{print $1}')
sleep 2

# Finder styling. If Finder scripting is unavailable we still ship a working DMG.
osascript <<EOF || echo "⚠️  Finder styling skipped (automation unavailable); DMG still built."
tell application "Finder"
  tell disk "$VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 820, 540}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background picture of theViewOptions to POSIX file "/Volumes/$VOL/.background/bg.png"
    set position of item "$APP" of container window to {165, 215}
    set position of item "Applications" of container window to {455, 215}
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

sync; sleep 1
# Detach (retry a few times in case the volume is briefly busy).
for _ in 1 2 3 4 5; do hdiutil detach "$DEV" >/dev/null 2>&1 && break || sleep 2; done

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"
echo "✅ $DMG"
