#!/bin/bash
# Build MeetPaw.app and package it into a styled, drag-to-install MeetPaw.dmg
# (centered title with glow, grid background, app + Applications) using create-dmg.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

# 1x background + @2x for retina (create-dmg auto-picks the @2x next to it).
swift Scripts/makedmgbg.swift Resources/dmg-bg.png 1
swift Scripts/makedmgbg.swift Resources/dmg-bg@2x.png 2

rm -f MeetPaw.dmg
create-dmg \
  --volname "MeetPaw" \
  --background "Resources/dmg-bg.png" \
  --window-pos 200 120 \
  --window-size 620 420 \
  --icon-size 128 \
  --icon "MeetPaw.app" 215 235 \
  --app-drop-link 405 235 \
  --no-internet-enable \
  "MeetPaw.dmg" \
  "MeetPaw.app"

echo "✅ MeetPaw.dmg"
