#!/bin/zsh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
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
trap 'rm -rf "$MODULE_CACHE"' EXIT

swiftc -module-cache-path "$MODULE_CACHE" -swift-version 5 -O \
  -framework Cocoa -framework IOKit \
  "${REPO_DIR}/src/PowerSaverApp.swift" \
  -o "${EXECUTABLE}"

codesign --force --sign - "${APP_DIR}"

echo "==> Installing LaunchAgent..."
sed "s|__APP_EXECUTABLE__|${EXECUTABLE}|g" \
  "${REPO_DIR}/resources/com.rafli.powersaver.plist.template" > "${PLIST_DEST}"

launchctl bootout "gui/${UID_NUM}/com.rafli.powersaver" 2>/dev/null || true
sleep 0.2
launchctl bootstrap "gui/${UID_NUM}" "${PLIST_DEST}"

echo "==> PowerSaver installed and running! Check the leaf/bolt icon in your Menu Bar."
