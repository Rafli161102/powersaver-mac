#!/bin/zsh
# Stops unused background agents and helper processes to maximize battery life.
# Usage: power-saver.sh [--extreme]

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
UID_NUM="$(id -u)"
EXTREME=0
[[ "${1:-}" == "--extreme" ]] && EXTREME=1

STATE_DIR="${HOME}/Library/Application Support/PowerSaver"
STOPPED_FILE="${STATE_DIR}/stopped_items.txt"
mkdir -p "$STATE_DIR"
touch "$STOPPED_FILE"

record_stopped() {
  local item="$1"
  grep -Fxq "$item" "$STOPPED_FILE" 2>/dev/null || echo "$item" >> "$STOPPED_FILE"
}

stop_agent() {
  local label="$1"
  if launchctl list | awk '{print $3}' | grep -Fxq "$label"; then
    record_stopped "agent:${label}"
  fi
  launchctl bootout "gui/${UID_NUM}/${label}" 2>/dev/null || true
  launchctl disable "gui/${UID_NUM}/${label}" 2>/dev/null || true
}

stop_proc() {
  local proc="$1"
  local record_app="${2:-}"
  if pgrep -u "$UID_NUM" -x "$proc" >/dev/null 2>&1; then
    [[ -n "$record_app" ]] && record_stopped "app:${record_app}"
    pkill -TERM -u "$UID_NUM" -x "$proc" 2>/dev/null || true
  fi
}

echo "==> Ensuring App Nap is active and disabling Chrome background mode..."
defaults delete NSGlobalDomain NSAppSleepDisabled 2>/dev/null || true
defaults write com.google.Chrome BackgroundModeEnabled -bool false 2>/dev/null || true

echo "==> Suspending unused background updaters and user agents..."
for label in \
  com.google.GoogleUpdater.wake \
  com.google.keystone.agent \
  com.google.keystone.xpcservice \
  com.valvesoftware.steamclean \
  ai.hermes.gateway
do
  stop_agent "$label"
done

for proc in figma_agent FigmaAgent LyricsXHelper ollama Ollama llama-server iwallpaper steam_osx Steam; do
  stop_proc "$proc"
done

# Clean up Adobe background helpers only when no primary Adobe app is running
if ! pgrep -u "$UID_NUM" -f "Adobe (Premiere|After Effects|Photoshop|Illustrator|Lightroom)" >/dev/null 2>&1; then
  for adobe_proc in CCXProcess "Core Sync" AdobeIPCBroker "Adobe Crash Processor" CCLibrary; do
    stop_proc "$adobe_proc"
  done
fi

if (( EXTREME == 1 )); then
  echo "==> Extreme mode: closing menu bar utilities..."
  stop_proc "Atoll" "Atoll.app"
  stop_proc "Macs Fan Control" "Macs Fan Control.app"
  stop_proc "Rectangle" "Rectangle.app"
  stop_proc "Maccy" "Maccy.app"
  pkill -TERM -u "$UID_NUM" -f "Atoll\.app/Contents/Resources/mediaremote-adapter\.pl" 2>/dev/null || true
fi

echo "==> Done. Top user CPU processes:"
ps -u "$UID_NUM" -o pid,%cpu,%mem,comm | sort -k2 -rn | head -n 10
