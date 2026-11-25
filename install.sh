#!/bin/zsh
set -euo pipefail

REPO_URL="https://github.com/Rafli161102/powersaver-mac.git"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"
TMP_CLONE=""

cleanup() {
  if [[ -n "$TMP_CLONE" && -d "$TMP_CLONE" ]]; then
    rm -rf "$TMP_CLONE"
  fi
}
trap cleanup EXIT

if [[ -f "${SCRIPT_DIR}/src/PowerSaverApp.swift" ]]; then
  REPO_DIR="${SCRIPT_DIR}"
else
  echo "==> Downloading PowerSaver source..."
  TMP_CLONE="$(mktemp -d)"
  git clone --depth 1 "${REPO_URL}" "${TMP_CLONE}/powersaver-mac"
  REPO_DIR="${TMP_CLONE}/powersaver-mac"
fi

APP_DIR="${HOME}/Applications/PowerSaver.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/PowerSaver"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
SCRIPTS_DEST="${RESOURCES_DIR}/scripts"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.rafli.powersaver.plist"
UID_NUM="$(id -u)"

echo "==> Building PowerSaver.app..."
mkdir -p "${APP_DIR}/Contents/MacOS" "${SCRIPTS_DEST}" "${HOME}/Library/LaunchAgents"
cp "${REPO_DIR}/resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${REPO_DIR}/scripts/"*.sh "${SCRIPTS_DEST}/"
chmod +x "${SCRIPTS_DEST}/"*.sh

MODULE_CACHE="$(mktemp -d)"
BUILD_TMP="$(mktemp -d)"
cleanup_all() {
  rm -rf "$MODULE_CACHE" "$BUILD_TMP"
  cleanup
}
trap cleanup_all EXIT

if swiftc -module-cache-path "$MODULE_CACHE" -target arm64-apple-macosx13.0 -swift-version 5 -O \
    -framework Cocoa -framework IOKit "${REPO_DIR}/src/PowerSaverApp.swift" -o "${BUILD_TMP}/ps_arm64" 2>/dev/null && \
   swiftc -module-cache-path "$MODULE_CACHE" -target x86_64-apple-macosx13.0 -swift-version 5 -O \
    -framework Cocoa -framework IOKit "${REPO_DIR}/src/PowerSaverApp.swift" -o "${BUILD_TMP}/ps_x86_64" 2>/dev/null; then
  lipo -create "${BUILD_TMP}/ps_arm64" "${BUILD_TMP}/ps_x86_64" -output "${EXECUTABLE}"
else
  swiftc -module-cache-path "$MODULE_CACHE" -swift-version 5 -O \
    -framework Cocoa -framework IOKit "${REPO_DIR}/src/PowerSaverApp.swift" -o "${EXECUTABLE}"
fi

codesign --force --sign - "${APP_DIR}"

echo "==> Installing LaunchAgent..."
sed "s|__APP_EXECUTABLE__|${EXECUTABLE}|g" \
  "${REPO_DIR}/resources/com.rafli.powersaver.plist.template" > "${PLIST_DEST}"

launchctl bootout "gui/${UID_NUM}/com.rafli.powersaver" 2>/dev/null || true
sleep 0.2
launchctl bootstrap "gui/${UID_NUM}" "${PLIST_DEST}"

echo "==> PowerSaver installed and running! Check the leaf/bolt icon in your Menu Bar."
