#!/bin/bash
set -e

BINARY=".build/release/ClaudeQuota"
APP_NAME="ClaudeQuota"
BUNDLE_ID="com.clausequota.app"
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.0.0")
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo "1")

APP_DIR="dist/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "Packaging ${APP_NAME} v${VERSION} (build ${BUILD})..."

rm -rf dist
mkdir -p "${MACOS}" "${RESOURCES}"

# Copy binary and strip ad-hoc signature so Gatekeeper doesn't block unsigned internet downloads
cp "${BINARY}" "${MACOS}/${APP_NAME}"
codesign --remove-signature "${MACOS}/${APP_NAME}" 2>/dev/null || true

# Write Info.plist
cat > "${CONTENTS}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
EOF

# Copy icon if it exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES}/AppIcon.icns"
fi

echo "Created ${APP_DIR}"
