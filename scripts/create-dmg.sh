#!/bin/bash
set -e

APP_NAME="BetterDisplayFree"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-$(cat "$PROJECT_DIR/VERSION" | tr -d '\n')}"
DMG_NAME="${APP_NAME}-${VERSION}"
BUILD_DIR="${PROJECT_DIR}/.build/release"
DIST_DIR="${PROJECT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

echo "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$DIST_DIR"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "${PROJECT_DIR}/VERSION" "${APP_BUNDLE}/Contents/Resources/"
cp "${PROJECT_DIR}/assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"

cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.amitpalomo.BetterDisplayFree</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Amit Palomo. MIT License.</string>
</dict>
</plist>
EOF

echo "Creating DMG..."
DMG_TEMP="${DIST_DIR}/${DMG_NAME}-temp.dmg"
DMG_FINAL="${DIST_DIR}/${DMG_NAME}.dmg"

rm -f "$DMG_TEMP" "$DMG_FINAL"

hdiutil detach "/Volumes/${APP_NAME}" 2>/dev/null || true

hdiutil create -srcfolder "$APP_BUNDLE" -volname "$APP_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW "$DMG_TEMP"

hdiutil attach -readwrite -noverify "$DMG_TEMP" -mountpoint "/Volumes/${APP_NAME}"
MOUNT_DIR="/Volumes/${APP_NAME}"

ln -sf /Applications "${MOUNT_DIR}/Applications"
sync
sleep 1
hdiutil detach "$MOUNT_DIR"

hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
rm -f "$DMG_TEMP"

echo ""
echo "✓ Created: ${DMG_FINAL}"
echo "  Size: $(du -h "$DMG_FINAL" | cut -f1)"
