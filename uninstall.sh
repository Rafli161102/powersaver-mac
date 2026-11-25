#!/bin/zsh
set -euo pipefail

UID_NUM="$(id -u)"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.rafli.powersaver.plist"
APP_DIR="${HOME}/Applications/PowerSaver.app"
STATE_DIR="${HOME}/Library/Application Support/PowerSaver"

echo "==> Restoring any suspended items..."
if [[ -x "${APP_DIR}/Contents/Resources/scripts/normal-mode.sh" ]]; then
  "${APP_DIR}/Contents/Resources/scripts/normal-mode.sh" || true
fi

echo "==> Unloading LaunchAgent and removing PowerSaver.app..."
launchctl bootout "gui/${UID_NUM}/com.rafli.powersaver" 2>/dev/null || true
rm -f "${PLIST_DEST}"
rm -rf "${APP_DIR}" "${STATE_DIR}"

echo "==> PowerSaver uninstalled."
