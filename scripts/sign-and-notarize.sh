#!/bin/bash
# Sign and notarize the .app bundle.
# Requires these environment variables (set as GitHub Actions secrets):
#   CERTIFICATE_BASE64     — Developer ID cert exported as .p12, base64 encoded
#   CERTIFICATE_PASSWORD   — Password for the .p12
#   NOTARYTOOL_APPLE_ID    — Your Apple ID email
#   NOTARYTOOL_PASSWORD    — App-specific password from appleid.apple.com
#   NOTARYTOOL_TEAM_ID     — Your 10-character Team ID
set -e

APP="dist/ClaudeQuota.app"

echo "Installing certificate..."
echo "$CERTIFICATE_BASE64" | base64 --decode -o /tmp/cert.p12
security create-keychain -p "" build.keychain
security import /tmp/cert.p12 -k build.keychain -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security list-keychains -s build.keychain
security default-keychain -s build.keychain
security unlock-keychain -p "" build.keychain
security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain

IDENTITY=$(security find-identity -v -p codesigning build.keychain | grep "Developer ID Application" | head -1 | awk '{print $2}')
echo "Signing with identity: $IDENTITY"

codesign --force --deep --sign "$IDENTITY" \
  --entitlements scripts/entitlements.plist \
  --options runtime \
  "$APP"

echo "Notarizing..."
cd dist
zip -r ClaudeQuota-notarize.zip ClaudeQuota.app
xcrun notarytool submit ClaudeQuota-notarize.zip \
  --apple-id "$NOTARYTOOL_APPLE_ID" \
  --password "$NOTARYTOOL_PASSWORD" \
  --team-id "$NOTARYTOOL_TEAM_ID" \
  --wait
xcrun stapler staple ClaudeQuota.app
rm ClaudeQuota-notarize.zip
cd ..

echo "Signed and notarized successfully."
