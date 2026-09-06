#!/bin/bash
# Builds Bbox and packages it into a double-clickable Bbox.app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Bbox"
BUNDLE_ID="com.bbox.app"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
VERSION="${1:-1.0.14}"

echo "▶ Building ${APP_NAME} (release)…"
swift build -c release

echo "▶ Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"
chmod +x "${CONTENTS}/MacOS/${APP_NAME}"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

# Clear extended attributes so codesign does not choke on "detritus".
xattr -cr "${APP_DIR}" 2>/dev/null || true

# Prefer a stable local self-signed identity so the app keeps the same
# designated requirement across rebuilds. This lets a granted Accessibility
# permission survive reinstalls. Falls back to ad-hoc (e.g. on CI) when the
# local signing keychain is absent.
SIGN_KC="${HOME}/Library/Keychains/bbox-signing.keychain-db"
SIGN_ID="Bbox Signing"
if [ -f "${SIGN_KC}" ] && security find-identity -p codesigning "${SIGN_KC}" 2>/dev/null | grep -q "${SIGN_ID}"; then
  echo "▶ Signing with stable identity '${SIGN_ID}'…"
  security unlock-keychain -p "bbox-local-signing" "${SIGN_KC}" 2>/dev/null || true
  # codesign resolves the identity via the keychain search list; make sure our
  # signing keychain is on it (keeping the existing ones too).
  security list-keychains -d user -s "${SIGN_KC}" $(security list-keychains -d user | sed 's/"//g') 2>/dev/null || true
  codesign --force --deep --sign "${SIGN_ID}" --keychain "${SIGN_KC}" "${APP_DIR}" \
    && echo "  signed (stable)" || echo "  (stable signing failed)"
else
  echo "▶ Ad-hoc signing…"
  codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || echo "  (codesign skipped)"
fi

echo "✅ Done: ${APP_DIR}"
echo "   Run with: open \"${APP_DIR}\""
