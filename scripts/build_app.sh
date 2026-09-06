#!/bin/bash
# Builds Bbox and packages it into a double-clickable Bbox.app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Bbox"
BUNDLE_ID="com.bbox.app"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
VERSION="${1:-1.0.5}"

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

# Ad-hoc code signature so macOS lets it run locally without Gatekeeper nagging.
echo "▶ Ad-hoc signing…"
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || echo "  (codesign skipped)"

echo "✅ Done: ${APP_DIR}"
echo "   Run with: open \"${APP_DIR}\""
