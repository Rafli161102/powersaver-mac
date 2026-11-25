#!/bin/zsh
set -euo pipefail

UID_NUM="$(id -u)"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.rafli.powersaver.plist"
STATE_DIR="${HOME}/Library/Application Support/PowerSaver"

echo "==> Restoring any suspended items..."
for app_path in "${HOME}/Applications/PowerSaver.app" "/Applications/PowerSaver.app"; do
  if [[ -x "${app_path}/Contents/Resources/scripts/normal-mode.sh" ]]; then
    "${app_path}/Contents/Resources/scripts/normal-mode.sh" || true
    break
  fi
done

echo "==> Unloading LaunchAgent and removing PowerSaver.app..."
launchctl bootout "gui/${UID_NUM}/com.rafli.powersaver" 2>/dev/null || true
rm -f "${PLIST_DEST}"
rm -rf "${HOME}/Applications/PowerSaver.app" "${STATE_DIR}"

if [[ -d "/Applications/PowerSaver.app" ]]; then
  rm -rf "/Applications/PowerSaver.app" 2>/dev/null || sudo rm -rf "/Applications/PowerSaver.app"
fi

echo "==> PowerSaver uninstalled."
