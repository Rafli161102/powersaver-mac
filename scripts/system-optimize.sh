#!/bin/zsh
# Run with administrator privileges: sudo ./scripts/system-optimize.sh
# Applies aggressive battery pmset policies and disables common third-party background updaters.

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Must be run as root: sudo $0"
  exit 1
fi

REAL_USER="${SUDO_USER:-$(stat -f '%Su' /dev/console)}"
REAL_UID="$(id -u "$REAL_USER")"

echo "==> Applying battery power management settings (pmset -b)..."
pmset -b \
  lowpowermode 1 \
  powernap 0 \
  proximitywake 0 \
  womp 0 \
  tcpkeepalive 0 \
  lessbright 1 \
  displaysleep 3 \
  disksleep 5 \
  sleep 1 \
  standby 1 \
  standbydelayhigh 3600 \
  standbydelaylow 900 \
  ttyskeepawake 0

echo "==> Disabling idle third-party system updaters and remote desktop daemons (if present)..."
for sys_label in \
  org.chromium.chromoting.broker \
  com.google.GoogleUpdater.wake.system \
  com.google.keystone.daemon \
  com.microsoft.OneDriveUpdaterDaemon \
  com.microsoft.OneDriveStandaloneUpdaterDaemon \
  com.microsoft.autoupdate.helper \
  com.microsoft.office.licensingV2.helper
do
  launchctl bootout "system/${sys_label}" 2>/dev/null || true
  launchctl disable "system/${sys_label}" 2>/dev/null || true
done

for agent_label in \
  org.chromium.chromoting \
  com.google.keystone.system.agent \
  com.google.keystone.system.xpcservice \
  com.microsoft.OneDriveStandaloneUpdater \
  com.microsoft.SyncReporter \
  com.microsoft.update.agent
do
  launchctl bootout "gui/${REAL_UID}/${agent_label}" 2>/dev/null || true
  launchctl disable "gui/${REAL_UID}/${agent_label}" 2>/dev/null || true
done

echo "==> Done. Current pmset configuration:"
pmset -g custom
