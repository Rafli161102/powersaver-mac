#!/bin/zsh
# Run with administrator privileges:
#   sudo ./scripts/system-optimize.sh            (apply battery optimizations)
#   sudo ./scripts/system-optimize.sh --restore  (restore standard macOS defaults)

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Must be run as root: sudo $0"
  exit 1
fi

REAL_USER="${SUDO_USER:-$(stat -f '%Su' /dev/console)}"
REAL_UID="$(id -u "$REAL_USER")"

apply_pmset() {
  local key="$1"
  local val="$2"
  pmset -b "$key" "$val" 2>/dev/null || true
}

if [[ "${1:-}" == "--restore" ]]; then
  echo "==> Restoring standard macOS battery pmset settings..."
  apply_pmset displaysleep 10
  apply_pmset disksleep 10
  apply_pmset tcpkeepalive 1
  apply_pmset standbydelayhigh 86400
  apply_pmset standbydelaylow 10800
  apply_pmset ttyskeepawake 1
  echo "==> Restored. Current pmset configuration:"
  pmset -g custom
  exit 0
fi

echo "==> Applying universal battery power management settings (pmset -b)..."
# Applied individually so Apple Silicon and Intel Macs skip unsupported keys gracefully.
apply_pmset lowpowermode 1
apply_pmset powernap 0
apply_pmset proximitywake 0
apply_pmset womp 0
apply_pmset tcpkeepalive 0
apply_pmset lessbright 1
apply_pmset displaysleep 3
apply_pmset disksleep 5
apply_pmset sleep 1
apply_pmset standby 1
apply_pmset standbydelayhigh 3600
apply_pmset standbydelaylow 900
apply_pmset ttyskeepawake 0

echo "==> Disabling idle third-party system updaters (only if installed)..."
for sys_label in \
  org.chromium.chromoting.broker \
  com.google.GoogleUpdater.wake.system \
  com.google.keystone.daemon \
  com.microsoft.OneDriveUpdaterDaemon \
  com.microsoft.OneDriveStandaloneUpdaterDaemon \
  com.microsoft.autoupdate.helper \
  com.microsoft.office.licensingV2.helper \
  com.adobe.ARMDC.Communicator \
  com.adobe.ARMDC.SMJobBlessHelper
do
  if [[ -f "/Library/LaunchDaemons/${sys_label}.plist" ]]; then
    launchctl bootout "system/${sys_label}" 2>/dev/null || true
    launchctl disable "system/${sys_label}" 2>/dev/null || true
  fi
done

for agent_label in \
  org.chromium.chromoting \
  com.google.keystone.system.agent \
  com.google.keystone.system.xpcservice \
  com.microsoft.OneDriveStandaloneUpdater \
  com.microsoft.SyncReporter \
  com.microsoft.update.agent
do
  if [[ -f "/Library/LaunchAgents/${agent_label}.plist" ]]; then
    launchctl bootout "gui/${REAL_UID}/${agent_label}" 2>/dev/null || true
    launchctl disable "gui/${REAL_UID}/${agent_label}" 2>/dev/null || true
  fi
done

echo "==> Done. Current pmset configuration:"
pmset -g custom
