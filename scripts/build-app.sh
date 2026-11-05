#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEAM_ID="${TEAM_ID:-7492ZAHAJV}"
BUNDLE_ID="${BUNDLE_ID:-org.robertcrandall.Tasks}"
APP_NAME="Tasks"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
echo "==> Building ${APP_NAME} and tasks-mcp (release)..."
swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/TasksApp" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$BUILD_DIR/tasks-mcp" "$APP_BUNDLE/Contents/MacOS/tasks-mcp"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF

SIGN_IDENTITY=""
while IFS= read -r candidate; do
  [[ -z "$candidate" ]] && continue
  if security find-certificate -c "$candidate" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -q "OU=${TEAM_ID}"; then
    SIGN_IDENTITY="$candidate"
    break
  fi
done < <(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2}')

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "Error: No Apple Development codesigning identity found for Team ${TEAM_ID}." >&2
  exit 1
fi

echo "==> Signing ${APP_BUNDLE} with '${SIGN_IDENTITY}' (Team ${TEAM_ID})..."
codesign --force --sign "$SIGN_IDENTITY" \
  --timestamp=none \
  "$APP_BUNDLE/Contents/MacOS/tasks-mcp"

# If a macOS CloudKit provisioning profile is supplied, embed it and sign with full CloudKit entitlements;
# otherwise sign with Team-prefixed App Group entitlements so amfid allows local execution without a profile.
if [[ -n "${PROVISIONING_PROFILE:-}" && -f "${PROVISIONING_PROFILE}" ]]; then
  cp "${PROVISIONING_PROFILE}" "$APP_BUNDLE/Contents/embedded.provisionprofile"
  codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT_DIR/Tasks.entitlements" \
    --timestamp=none \
    "$APP_BUNDLE"
else
  TEMP_ENTITLEMENTS="$(mktemp -t tasks-entitlements.XXXXXX.plist)"
  trap 'rm -f "$TEMP_ENTITLEMENTS"' EXIT

  cat > "$TEMP_ENTITLEMENTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>${TEAM_ID}.group.org.robertcrandall.Tasks</string>
	</array>
	<key>com.apple.security.get-task-allow</key>
	<true/>
</dict>
</plist>
EOF

  codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements "$TEMP_ENTITLEMENTS" \
    --timestamp=none \
    "$APP_BUNDLE"
fi

codesign --verify --verbose=2 "$APP_BUNDLE"
echo "==> Built and signed: $APP_BUNDLE"
echo "==> Bundled MCP server: $APP_BUNDLE/Contents/MacOS/tasks-mcp"
