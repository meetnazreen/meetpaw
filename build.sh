#!/bin/bash
# Build MeetPaw.app — a proper .app bundle (LSUIElement menu-bar app),
# ad-hoc signed so Keychain/notifications/launch-at-login behave.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=$(swift build -c release --show-bin-path)/MeetPaw

# App icon (regenerate only if missing).
if [ ! -f Resources/AppIcon.icns ]; then
  mkdir -p Resources
  swift Scripts/makeicon.swift /tmp/AppIcon.iconset
  iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf /tmp/AppIcon.iconset
fi

APP="MeetPaw.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MeetPaw"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SPM resource bundle (meet.svg etc.) must sit next to the executable so
# Bundle.module can find it inside the .app.
BINDIR=$(dirname "$BIN")
cp -R "$BINDIR"/*.bundle "$APP/Contents/MacOS/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MeetPaw</string>
  <key>CFBundleDisplayName</key><string>MeetPaw</string>
  <key>CFBundleIdentifier</key><string>com.meetpaw.app</string>
  <key>CFBundleExecutable</key><string>MeetPaw</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✅ Built $APP — run: open $APP"
