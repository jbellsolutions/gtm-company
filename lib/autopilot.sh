#!/usr/bin/env bash
# chmod +x lib/autopilot.sh
# GTM Company — Auto-Pilot Daemon
#
# Usage: ./lib/autopilot.sh start|stop|status
#
# Makes the GTM Company run 24/7 by scheduling all agents on their defined
# schedules from config/schedules.json. Detects the platform (Linux systemd,
# macOS launchd, or fallback crontab) and sets up appropriate scheduling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PID_FILE="/tmp/gtm-company-autopilot.pid"
LOG_DIR="$PROJECT_ROOT/logs"
SCHEDULES_FILE="$PROJECT_ROOT/config/schedules.json"
PLIST_DIR="$HOME/Library/LaunchAgents"
CRON_TAG="# GTM-COMPANY-AUTOPILOT"

# ─── Detect platform ────────────────────────────────────────────────────────

detect_platform() {
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "launchd"
  elif command -v systemctl &>/dev/null && systemctl --user status &>/dev/null 2>&1; then
    echo "systemd"
  else
    echo "crontab"
  fi
}

PLATFORM=$(detect_platform)

# ─── Ensure directories ─────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"

# ─── Read schedules ─────────────────────────────────────────────────────────

get_agents() {
  jq -r '.agents | keys[]' "$SCHEDULES_FILE" 2>/dev/null
}

get_cron() {
  local agent="$1"
  jq -r ".agents[\"${agent}\"].cron // empty" "$SCHEDULES_FILE" 2>/dev/null
}

get_auto_mode() {
  local agent="$1"
  jq -r ".agents[\"${agent}\"].auto_mode // false" "$SCHEDULES_FILE" 2>/dev/null
}

# ─── Add orchestrator to schedules if not present ────────────────────────────

ensure_orchestrator() {
  local has_orch
  has_orch=$(jq -r '.agents.orchestrator // empty' "$SCHEDULES_FILE" 2>/dev/null)
  if [[ -z "$has_orch" ]]; then
    echo "[autopilot] Adding orchestrator to schedules.json..."
    local tmp
    tmp=$(mktemp)
    jq '.agents.orchestrator = {"cron": "*/30 * * * *", "description": "Every 30 minutes (heartbeat)", "priority": "critical", "auto_mode": true}' "$SCHEDULES_FILE" > "$tmp"
    mv "$tmp" "$SCHEDULES_FILE"
    echo "[autopilot] Orchestrator added."
  fi
}

# ─── launchd (macOS) ────────────────────────────────────────────────────────

cron_to_launchd_interval() {
  # Simple cron-to-launchd mapping for common patterns
  local cron="$1"
  local minute hour dom month dow
  read -r minute hour dom month dow <<< "$cron"

  # */30 * * * * → every 30 minutes
  if [[ "$minute" == "*/30" && "$hour" == "*" ]]; then
    echo "    <key>StartInterval</key>"
    echo "    <integer>1800</integer>"
    return
  fi

  # */N * * * * → every N minutes
  if [[ "$minute" =~ ^\*/([0-9]+)$ && "$hour" == "*" ]]; then
    local interval=$(( ${BASH_REMATCH[1]} * 60 ))
    echo "    <key>StartInterval</key>"
    echo "    <integer>${interval}</integer>"
    return
  fi

  # Specific times — use StartCalendarInterval
  echo "    <key>StartCalendarInterval</key>"
  echo "    <array>"

  # Handle comma-separated hours (e.g., "23 8,12,16 * * *")
  local IFS=','
  local hours=($hour)
  unset IFS

  for h in "${hours[@]}"; do
    echo "      <dict>"
    if [[ "$minute" != "*" ]]; then
      echo "        <key>Minute</key>"
      echo "        <integer>${minute}</integer>"
    fi
    if [[ "$h" != "*" ]]; then
      echo "        <key>Hour</key>"
      echo "        <integer>${h}</integer>"
    fi
    if [[ "$dow" != "*" ]]; then
      echo "        <key>Weekday</key>"
      echo "        <integer>${dow}</integer>"
    fi
    if [[ "$dom" != "*" ]]; then
      echo "        <key>Day</key>"
      echo "        <integer>${dom}</integer>"
    fi
    echo "      </dict>"
  done

  echo "    </array>"
}

launchd_install() {
  mkdir -p "$PLIST_DIR"

  for agent in $(get_agents); do
    local cron
    cron=$(get_cron "$agent")
    if [[ -z "$cron" ]]; then continue; fi

    local auto_flag=""
    if [[ "$(get_auto_mode "$agent")" == "true" ]]; then
      auto_flag="--auto"
    fi

    local label="com.gtm-company.${agent}"
    local plist_file="${PLIST_DIR}/${label}.plist"
    local log_file="${LOG_DIR}/${agent}.log"

    cat > "$plist_file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${PROJECT_ROOT}/lib/run-agent.sh</string>
        <string>${agent}</string>
$(if [[ -n "$auto_flag" ]]; then echo "        <string>${auto_flag}</string>"; fi)
    </array>
    <key>WorkingDirectory</key>
    <string>${PROJECT_ROOT}</string>
$(cron_to_launchd_interval "$cron")
    <key>StandardOutPath</key>
    <string>${log_file}</string>
    <key>StandardErrorPath</key>
    <string>${log_file}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:${HOME}/.local/bin</string>
$(if [[ -f "$PROJECT_ROOT/.env" ]]; then
  while IFS='=' read -r k v; do
    # Skip comments and empty lines
    [[ -z "$k" || "$k" == \#* ]] && continue
    # Strip quotes from value
    v="${v%\"}"
    v="${v#\"}"
    v="${v%\'}"
    v="${v#\'}"
    echo "        <key>${k}</key>"
    echo "        <string>${v}</string>"
  done < "$PROJECT_ROOT/.env"
fi)
    </dict>
</dict>
</plist>
PLIST

    launchctl unload "$plist_file" 2>/dev/null || true
    launchctl load "$plist_file"
    echo "[autopilot] Loaded: ${label} (${cron})"

    # Handle cron_followup: create a second schedule entry if defined
    local cron_followup
    cron_followup=$(jq -r ".agents[\"${agent}\"].cron_followup // empty" "$SCHEDULES_FILE" 2>/dev/null)
    if [[ -n "$cron_followup" ]]; then
      local followup_label="com.gtm-company.${agent}-followup"
      local followup_plist="${PLIST_DIR}/${followup_label}.plist"

      cat > "$followup_plist" <<FPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${followup_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${PROJECT_ROOT}/lib/run-agent.sh</string>
        <string>${agent}</string>
$(if [[ -n "$auto_flag" ]]; then echo "        <string>${auto_flag}</string>"; fi)
    </array>
    <key>WorkingDirectory</key>
    <string>${PROJECT_ROOT}</string>
$(cron_to_launchd_interval "$cron_followup")
    <key>StandardOutPath</key>
    <string>${log_file}</string>
    <key>StandardErrorPath</key>
    <string>${log_file}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:${HOME}/.local/bin</string>
$(if [[ -f "$PROJECT_ROOT/.env" ]]; then
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" == \#* ]] && continue
    v="${v%\"}" ; v="${v#\"}" ; v="${v%\'}" ; v="${v#\'}"
    echo "        <key>${k}</key>"
    echo "        <string>${v}</string>"
  done < "$PROJECT_ROOT/.env"
fi)
    </dict>
</dict>
</plist>
FPLIST

      launchctl unload "$followup_plist" 2>/dev/null || true
      launchctl load "$followup_plist"
      echo "[autopilot] Loaded followup: ${followup_label} (${cron_followup})"
    fi
  done
}

launchd_uninstall() {
  for agent in $(get_agents); do
    local label="com.gtm-company.${agent}"
    local plist_file="${PLIST_DIR}/${label}.plist"
    if [[ -f "$plist_file" ]]; then
      launchctl unload "$plist_file" 2>/dev/null || true
      rm -f "$plist_file"
      echo "[autopilot] Unloaded: ${label}"
    fi
    # Also unload followup schedule if present
    local followup_label="com.gtm-company.${agent}-followup"
    local followup_plist="${PLIST_DIR}/${followup_label}.plist"
    if [[ -f "$followup_plist" ]]; then
      launchctl unload "$followup_plist" 2>/dev/null || true
      rm -f "$followup_plist"
      echo "[autopilot] Unloaded followup: ${followup_label}"
    fi
  done
}

# ─── Log rotation ──────────────────────────────────────────────────────────
# Truncate log files over 10MB to prevent disk bloat
# Usage: rotate_logs
rotate_logs() {
  local max_bytes=$((10 * 1024 * 1024))  # 10MB
  for log_file in "$LOG_DIR"/*.log; do
    [[ -f "$log_file" ]] || continue
    local size
    size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
    if [[ "$size" -gt "$max_bytes" ]]; then
      echo "[autopilot] Rotating $(basename "$log_file") (${size} bytes > 10MB)"
      local archive="${log_file}.$(date +%Y%m%d-%H%M%S).bak"
      mv "$log_file" "$archive"
      gzip "$archive" 2>/dev/null || true
      touch "$log_file"
      echo "[autopilot] Rotated: $(basename "$log_file")"
    fi
  done
}

launchd_status() {
  echo ""
  echo "GTM Company Auto-Pilot Status (launchd)"
  echo "========================================="
  echo ""
  for agent in $(get_agents); do
    local label="com.gtm-company.${agent}"
    local plist_file="${PLIST_DIR}/${label}.plist"
    local cron
    cron=$(get_cron "$agent")
    local log_file="${LOG_DIR}/${agent}.log"

    if [[ -f "$plist_file" ]]; then
      local running
      running=$(launchctl list 2>/dev/null | grep "$label" || echo "")
      local last_run="never"
      if [[ -f "$log_file" ]]; then
        last_run=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$log_file" 2>/dev/null || echo "unknown")
      fi

      if [[ -n "$running" ]]; then
        local pid
        pid=$(echo "$running" | awk '{print $1}')
        echo "  [ACTIVE]  ${agent}"
        echo "            Schedule: ${cron}"
        echo "            PID: ${pid}"
        echo "            Last log: ${last_run}"
      else
        echo "  [LOADED]  ${agent}"
        echo "            Schedule: ${cron}"
        echo "            Last log: ${last_run}"
      fi
    else
      echo "  [OFF]     ${agent}"
      echo "            Schedule: ${cron}"
    fi
    echo ""
  done

  # Show log tail for recent activity
  echo "Recent Activity (last 5 log entries):"
  echo "--------------------------------------"
  for agent in $(get_agents); do
    local log_file="${LOG_DIR}/${agent}.log"
    if [[ -f "$log_file" ]]; then
      echo "--- ${agent} ---"
      tail -5 "$log_file" 2>/dev/null || echo "  (empty)"
      echo ""
    fi
  done
}

# ─── crontab (Linux/fallback) ──────────────────────────────────────────────

crontab_install() {
  # Remove existing GTM entries and add new ones
  local existing
  existing=$(crontab -l 2>/dev/null | grep -v "$CRON_TAG" || true)

  local new_entries=""
  for agent in $(get_agents); do
    local cron
    cron=$(get_cron "$agent")
    if [[ -z "$cron" ]]; then continue; fi

    local auto_flag=""
    if [[ "$(get_auto_mode "$agent")" == "true" ]]; then
      auto_flag="--auto"
    fi

    local log_file="${LOG_DIR}/${agent}.log"
    new_entries="${new_entries}${cron} cd ${PROJECT_ROOT} && ${PROJECT_ROOT}/lib/run-agent.sh ${agent} ${auto_flag} >> ${log_file} 2>&1 ${CRON_TAG}
"
  done

  echo "${existing}
${new_entries}" | crontab -
  echo "[autopilot] Crontab entries installed."
}

crontab_uninstall() {
  local existing
  existing=$(crontab -l 2>/dev/null | grep -v "$CRON_TAG" || true)
  echo "$existing" | crontab -
  echo "[autopilot] Crontab entries removed."
}

crontab_status() {
  echo ""
  echo "GTM Company Auto-Pilot Status (crontab)"
  echo "========================================="
  echo ""
  local entries
  entries=$(crontab -l 2>/dev/null | grep "$CRON_TAG" || echo "")
  if [[ -z "$entries" ]]; then
    echo "  No scheduled agents found in crontab."
  else
    echo "Active cron entries:"
    echo "$entries" | while IFS= read -r line; do
      echo "  $line"
    done
  fi
  echo ""

  for agent in $(get_agents); do
    local log_file="${LOG_DIR}/${agent}.log"
    local last_run="never"
    if [[ -f "$log_file" ]]; then
      last_run=$(date -r "$log_file" "+%Y-%m-%d %H:%M" 2>/dev/null || stat -c "%y" "$log_file" 2>/dev/null | cut -d. -f1 || echo "unknown")
    fi
    echo "  ${agent}: last log activity ${last_run}"
  done
  echo ""
}

# ─── Main ───────────────────────────────────────────────────────────────────

ACTION="${1:-}"

case "$ACTION" in
  start)
    echo "========================================="
    echo " GTM Company Auto-Pilot — Starting"
    echo " Platform: ${PLATFORM}"
    echo " $(date)"
    echo "========================================="
    echo ""

    # Ensure schedules file exists
    if [[ ! -f "$SCHEDULES_FILE" ]]; then
      echo "[autopilot] FATAL: ${SCHEDULES_FILE} not found" >&2
      exit 1
    fi

    # Ensure orchestrator is scheduled
    ensure_orchestrator

    # Install schedules
    case "$PLATFORM" in
      launchd)   launchd_install ;;
      systemd)   crontab_install ;; # systemd user timers are complex; use crontab
      crontab)   crontab_install ;;
    esac

    # Write PID file
    echo $$ > "$PID_FILE"

    echo ""
    echo "========================================="
    echo " Auto-Pilot is ACTIVE"
    echo " Agents scheduled: $(get_agents | wc -l | tr -d ' ')"
    echo " Logs: ${LOG_DIR}/"
    echo " Stop: ./lib/autopilot.sh stop"
    echo "========================================="

    # Run the first orchestrator heartbeat immediately
    echo ""
    echo "[autopilot] Running initial orchestrator heartbeat..."
    "${PROJECT_ROOT}/lib/run-agent.sh" orchestrator --auto >> "${LOG_DIR}/orchestrator.log" 2>&1 &
    echo "[autopilot] Orchestrator heartbeat started (PID: $!)"
    ;;

  stop)
    echo "========================================="
    echo " GTM Company Auto-Pilot — Stopping"
    echo " $(date)"
    echo "========================================="
    echo ""

    case "$PLATFORM" in
      launchd)   launchd_uninstall ;;
      systemd)   crontab_uninstall ;;
      crontab)   crontab_uninstall ;;
    esac

    rm -f "$PID_FILE"

    echo ""
    echo "========================================="
    echo " Auto-Pilot is STOPPED"
    echo " All scheduled agents have been unloaded."
    echo "========================================="
    ;;

  status)
    case "$PLATFORM" in
      launchd)   launchd_status ;;
      systemd)   crontab_status ;;
      crontab)   crontab_status ;;
    esac

    # Check PID file
    if [[ -f "$PID_FILE" ]]; then
      echo "Auto-pilot PID file: $(cat "$PID_FILE")"
    else
      echo "Auto-pilot PID file: not found (may not be running)"
    fi
    ;;

  *)
    echo "Usage: ./lib/autopilot.sh start|stop|status"
    echo ""
    echo "  start   — Schedule all agents and start the orchestrator"
    echo "  stop    — Remove all scheduled agents"
    echo "  status  — Show what's running and last activity"
    exit 1
    ;;
esac
