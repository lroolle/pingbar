#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-PingBar}"
PROJECT="${PROJECT:-PingBar.xcodeproj}"
SCHEME="${SCHEME:-PingBar}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHS="${ARCHS:-arm64 x86_64}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/build/release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/$APP_NAME.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_ROOT/export}"
STAGING_DIR="${STAGING_DIR:-$BUILD_ROOT/dmg-staging}"
RELEASE_DIR="${RELEASE_DIR:-$PWD/build/releases}"
VERSION="${VERSION:-}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"

missing=0

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing: $1" >&2
    missing=1
  fi
}

xml_escape() {
  printf '%s' "$1" \
    | sed \
      -e 's/&/\&amp;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g' \
      -e 's/"/\&quot;/g' \
      -e "s/'/\&apos;/g"
}

require_env() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "missing env: $name" >&2
    missing=1
  fi
}

require_command xcodebuild
require_command xcrun
require_command hdiutil
require_command codesign
require_command ditto
require_command grep
require_command shasum
require_command spctl
require_command sed

require_env DEVELOPER_ID_APPLICATION "$DEVELOPER_ID_APPLICATION"
require_env APPLE_TEAM_ID "$APPLE_TEAM_ID"

if [ "$SKIP_NOTARIZATION" != "1" ] && [ -z "$NOTARYTOOL_PROFILE" ]; then
  require_env APPLE_ID "$APPLE_ID"
  require_env APPLE_APP_SPECIFIC_PASSWORD "$APPLE_APP_SPECIFIC_PASSWORD"
fi

if [ "$missing" -ne 0 ]; then
  echo "Release packaging requires Developer ID signing and notarization credentials." >&2
  echo "Set SKIP_NOTARIZATION=1 only for private smoke tests, not public releases." >&2
  exit 1
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$RELEASE_DIR"

echo "Archiving $APP_NAME with Developer ID signing..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  CODE_SIGN_STYLE=Manual \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="$ARCHS" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

export_options="$BUILD_ROOT/exportOptions.plist"
escaped_team_id="$(xml_escape "$APPLE_TEAM_ID")"
escaped_identity="$(xml_escape "$DEVELOPER_ID_APPLICATION")"

cat >"$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingCertificate</key>
  <string>$escaped_identity</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>$escaped_team_id</string>
</dict>
</plist>
EOF

echo "Exporting signed app..."
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$export_options"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Expected exported app at $APP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
if codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.get-task-allow"; then
  echo "Release app contains com.apple.security.get-task-allow; refusing to package." >&2
  exit 1
fi

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [ -z "$VERSION" ]; then
  VERSION="$app_version"
elif [ "$VERSION" != "$app_version" ]; then
  echo "VERSION=$VERSION does not match app CFBundleShortVersionString=$app_version" >&2
  exit 1
fi

safe_version="$(printf '%s' "$VERSION" | tr -c 'A-Za-z0-9._-' '-')"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$safe_version.dmg"

echo "Creating DMG..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"

if [ "$SKIP_NOTARIZATION" = "1" ]; then
  echo "Skipping notarization. Do not publish this DMG."
else
  echo "Submitting DMG for notarization..."
  if [ -n "$NOTARYTOOL_PROFILE" ]; then
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARYTOOL_PROFILE" \
      --wait
  else
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
  fi

  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl -a -vv --type open --context context:primary-signature "$DMG_PATH"
fi

dmg_name="$(basename "$DMG_PATH")"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "$dmg_name" >"$dmg_name.sha256"
)

echo "Release artifact:"
echo "  $DMG_PATH"
echo "  $DMG_PATH.sha256"
