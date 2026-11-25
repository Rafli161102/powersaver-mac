#!/bin/zsh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${REPO_DIR}/resources/Info.plist")"
DIST_DIR="${REPO_DIR}/dist"
STAGE_DIR="$(mktemp -d)"
APP_BUNDLE="${DIST_DIR}/PowerSaver.app"
EXECUTABLE="${APP_BUNDLE}/Contents/MacOS/PowerSaver"
SCRIPTS_DEST="${APP_BUNDLE}/Contents/Resources/scripts"

trap 'rm -rf "$STAGE_DIR"' EXIT

echo "==> Cleaning and preparing dist/..."
rm -rf "${DIST_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${SCRIPTS_DEST}"

cp "${REPO_DIR}/resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "${REPO_DIR}/scripts/"*.sh "${SCRIPTS_DEST}/"
chmod +x "${SCRIPTS_DEST}/"*.sh

echo "==> Compiling Universal Binary (arm64 + x86_64)..."
MODULE_CACHE="${STAGE_DIR}/module-cache"
mkdir -p "${MODULE_CACHE}"

swiftc -module-cache-path "${MODULE_CACHE}" -target arm64-apple-macosx13.0 -swift-version 5 -O \
  -framework Cocoa -framework IOKit "${REPO_DIR}/src/PowerSaverApp.swift" -o "${STAGE_DIR}/ps_arm64"

swiftc -module-cache-path "${MODULE_CACHE}" -target x86_64-apple-macosx13.0 -swift-version 5 -O \
  -framework Cocoa -framework IOKit "${REPO_DIR}/src/PowerSaverApp.swift" -o "${STAGE_DIR}/ps_x86_64"

lipo -create "${STAGE_DIR}/ps_arm64" "${STAGE_DIR}/ps_x86_64" -output "${EXECUTABLE}"
codesign --force --sign - "${APP_BUNDLE}"

echo "==> Creating ZIP archive..."
ZIP_PATH="${DIST_DIR}/PowerSaver-${VERSION}-universal.zip"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "==> Creating macOS Installer (.pkg)..."
PKG_ROOT="${STAGE_DIR}/pkg-root"
PKG_SCRIPTS="${STAGE_DIR}/pkg-scripts"
mkdir -p "${PKG_ROOT}/Applications" "${PKG_SCRIPTS}"
ditto "${APP_BUNDLE}" "${PKG_ROOT}/Applications/PowerSaver.app"
cp "${REPO_DIR}/resources/pkg-scripts/postinstall" "${PKG_SCRIPTS}/postinstall"
chmod +x "${PKG_SCRIPTS}/postinstall"

COMPONENT_PKG="${STAGE_DIR}/PowerSaver-component.pkg"
PKG_PATH="${DIST_DIR}/PowerSaver-${VERSION}.pkg"

pkgbuild \
  --root "${PKG_ROOT}" \
  --scripts "${PKG_SCRIPTS}" \
  --identifier "com.rafli.PowerSaver" \
  --version "${VERSION}" \
  --install-location "/" \
  "${COMPONENT_PKG}"

productbuild \
  --package "${COMPONENT_PKG}" \
  "${PKG_PATH}"

echo "==> Creating DMG image (.dmg)..."
DMG_SRC="${STAGE_DIR}/dmg-src"
DMG_PATH="${DIST_DIR}/PowerSaver-${VERSION}.dmg"
mkdir -p "${DMG_SRC}"
ditto "${APP_BUNDLE}" "${DMG_SRC}/PowerSaver.app"
ln -s /Applications "${DMG_SRC}/Applications"
cp "${REPO_DIR}/README.md" "${DMG_SRC}/README.md"

hdiutil create \
  -volname "PowerSaver ${VERSION}" \
  -srcfolder "${DMG_SRC}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

echo "==> Generating SHA-256 checksums..."
(cd "${DIST_DIR}" && shasum -a 256 "PowerSaver-${VERSION}-universal.zip" "PowerSaver-${VERSION}.pkg" "PowerSaver-${VERSION}.dmg" > checksums.txt)

echo "==> Built packages in ${DIST_DIR}:"
ls -lh "${DIST_DIR}"
cat "${DIST_DIR}/checksums.txt"
