#!/bin/zsh
# Restores LaunchAgents and applications previously suspended by PowerSaver.

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
UID_NUM="$(id -u)"
STATE_DIR="${HOME}/Library/Application Support/PowerSaver"
STOPPED_FILE="${STATE_DIR}/stopped_items.txt"

start_agent() {
  local label="$1"
  local plist="${HOME}/Library/LaunchAgents/${label}.plist"
  launchctl enable "gui/${UID_NUM}/${label}" 2>/dev/null || true
  if [[ -f "$plist" ]] && ! launchctl list | awk '{print $3}' | grep -Fxq "$label"; then
    launchctl bootstrap "gui/${UID_NUM}" "$plist" 2>/dev/null || true
  fi
}

open_app_if_found() {
  local app_name="$1"
  for base in "/Applications" "${HOME}/Applications"; do
    if [[ -d "${base}/${app_name}" ]]; then
      open -g -a "${base}/${app_name}" 2>/dev/null || true
      return 0
    fi
  done
}

if [[ -f "$STOPPED_FILE" ]]; then
  while IFS= read -r entry; do
    case "$entry" in
      agent:*)
        start_agent "${entry#agent:}"
        ;;
      apppath:*)
        app_path="${entry#apppath:}"
        [[ -d "$app_path" ]] && open -g -a "$app_path" 2>/dev/null || true
        ;;
      app:*)
        open_app_if_found "${entry#app:}"
        ;;
    esac
  done < "$STOPPED_FILE"
  rm -f "$STOPPED_FILE"
fi

echo "==> Normal mode restored."
