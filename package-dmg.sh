#!/bin/bash
# Build MeetPaw.app and package it into a drag-to-install MeetPaw.dmg.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

STAGE=$(mktemp -d)
cp -R MeetPaw.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

rm -f MeetPaw.dmg
hdiutil create -volname "MeetPaw" -srcfolder "$STAGE" -ov -format UDZO MeetPaw.dmg
rm -rf "$STAGE"
echo "✅ MeetPaw.dmg"
