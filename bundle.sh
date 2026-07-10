#!/bin/bash
set -euo pipefail

APP_NAME="TypeLock"
BUNDLE_ID="com.sergey.typelock"
VERSION="0.2.1"
ICON_FILE="Resources/TypeLock.icns"
if [ -z "${BUILD_NUMBER:-}" ]; then
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
        BUILD_NUMBER="$(printf "%03d" "$(git rev-list --count HEAD)")"
    else
        BUILD_NUMBER="001"
    fi
fi
APP_DIR="$APP_NAME.app"

# Build release
swift build -c release

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy app icon
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/TypeLock.icns"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>TypeLock</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "Built $APP_DIR version $VERSION ($BUILD_NUMBER)"
echo ""
echo "To install:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "Then open TypeLock from /Applications."
