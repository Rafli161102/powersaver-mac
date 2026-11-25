#!/bin/zsh
# Suspends configured user LaunchAgents, common third-party updaters, and idle background helpers.
# Usage: power-saver.sh [--extreme]

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
UID_NUM="$(id -u)"
EXTREME=0
[[ "${1:-}" == "--extreme" ]] && EXTREME=1

STATE_DIR="${HOME}/Library/Application Support/PowerSaver"
CONFIG_FILE="${STATE_DIR}/config.json"
STOPPED_FILE="${STATE_DIR}/stopped_items.txt"
mkdir -p "$STATE_DIR"
touch "$STOPPED_FILE"

record_stopped() {
  local item="$1"
  grep -Fxq "$item" "$STOPPED_FILE" 2>/dev/null || echo "$item" >> "$STOPPED_FILE"
}

stop_agent() {
  local label="$1"
  [[ -z "$label" ]] && return 0
  if launchctl list | awk '{print $3}' | grep -Fxq "$label"; then
    record_stopped "agent:${label}"
  fi
  launchctl bootout "gui/${UID_NUM}/${label}" 2>/dev/null || true
  launchctl disable "gui/${UID_NUM}/${label}" 2>/dev/null || true
}

stop_proc() {
  local proc="$1"
  [[ -z "$proc" ]] && return 0
  if pgrep -u "$UID_NUM" -x "$proc" >/dev/null 2>&1; then
    pkill -TERM -u "$UID_NUM" -x "$proc" 2>/dev/null || true
  fi
}

read_config_field() {
  local expr="$1"
  [[ -f "$CONFIG_FILE" ]] || return 0
  /usr/bin/osascript -l JavaScript -e "
    ObjC.import('Foundation');
    const data = \$.NSData.dataWithContentsOfFile('${CONFIG_FILE}');
    if (data) {
      const str = \$.NSString.alloc.initWithDataEncoding(data, \$.NSUTF8StringEncoding).js;
      const cfg = JSON.parse(str);
      ${expr}
    }
  " 2>/dev/null || true
}

AUTO_UPDATERS="$(read_config_field 'console.log(cfg.autoSuspendCommonUpdaters !== false ? "1" : "0")')"
AUTO_HELPERS="$(read_config_field 'console.log(cfg.autoCleanCommonHelpers !== false ? "1" : "0")')"
[[ -z "$AUTO_UPDATERS" ]] && AUTO_UPDATERS="1"
[[ -z "$AUTO_HELPERS" ]] && AUTO_HELPERS="1"

echo "==> Ensuring App Nap is active and disabling Chrome background mode..."
defaults delete NSGlobalDomain NSAppSleepDisabled 2>/dev/null || true
defaults write com.google.Chrome BackgroundModeEnabled -bool false 2>/dev/null || true

if [[ "$AUTO_UPDATERS" == "1" ]]; then
  echo "==> Suspending common third-party background updaters..."
  for label in \
    com.google.GoogleUpdater.wake \
    com.google.keystone.agent \
    com.google.keystone.xpcservice \
    com.valvesoftware.steamclean \
    com.adobe.GC.Invoker-1.0 \
    com.adobe.AdobeCreativeCloud \
    com.dropbox.DropboxMacUpdate.agent
  do
    stop_agent "$label"
  done
fi

echo "==> Suspending user-configured LaunchAgents..."
USER_AGENTS="$(read_config_field 'if (Array.isArray(cfg.suspendAgentLabels)) cfg.suspendAgentLabels.forEach(l => console.log(l))')"
if [[ -n "$USER_AGENTS" ]]; then
  while IFS= read -r label; do
    stop_agent "$label"
  done <<< "$USER_AGENTS"
fi

if [[ "$AUTO_HELPERS" == "1" ]]; then
  echo "==> Cleaning idle background helpers..."
  for proc in figma_agent FigmaAgent LyricsXHelper ollama llama-server steam_osx DropboxHelper; do
    stop_proc "$proc"
  done

  if ! pgrep -u "$UID_NUM" -f "Adobe (Premiere|After Effects|Photoshop|Illustrator|Lightroom)" >/dev/null 2>&1; then
    for adobe_proc in CCXProcess "Core Sync" AdobeIPCBroker "Adobe Crash Processor" CCLibrary; do
      stop_proc "$adobe_proc"
    done
  fi
fi

if (( EXTREME == 1 )); then
  echo "==> Extreme mode: terminating user-configured extreme apps (CLI fallback)..."
  EXTREME_APPS="$(read_config_field 'if (Array.isArray(cfg.extremeModeApps)) cfg.extremeModeApps.forEach(a => console.log(a))')"
  if [[ -n "$EXTREME_APPS" ]]; then
    while IFS= read -r app_name; do
      stop_proc "$app_name"
    done <<< "$EXTREME_APPS"
  fi
fi

echo "==> Done. Top user CPU processes:"
ps -u "$UID_NUM" -o pid,%cpu,%mem,comm | sort -k2 -rn | head -n 10
