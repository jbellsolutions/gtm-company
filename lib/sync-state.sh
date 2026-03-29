#!/usr/bin/env bash
# chmod +x lib/sync-state.sh
# GTM Company — Sync local state files to Supabase after each agent run
#
# Usage: source lib/sync-state.sh && sync_all "cold-outreach"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source memory layer if not already loaded
if ! type mem_init &>/dev/null 2>&1; then
  source "$SCRIPT_DIR/memory.sh"
fi

# Load project config
PROJECT_ID="${PROJECT_ID:-$(jq -r '.project_id' "$PROJECT_ROOT/config/project.json" 2>/dev/null || echo "ai-integrators-gtm")}"

# ─── Sync Run Results ──────────────────────────────────────────────────────

sync_run_results() {
  local agent_id="$1"
  local state_file="$PROJECT_ROOT/state/${agent_id}/last-run.json"

  if [[ ! -f "$state_file" ]]; then
    echo "[sync-state] No last-run.json found for ${agent_id}, skipping run sync."
    return 0
  fi

  local status outputs token_usage cost_cents
  status=$(jq -r '.status // "unknown"' "$state_file")
  outputs=$(jq -c '.' "$state_file")
  token_usage=$(jq -r '.token_usage // 0' "$state_file")
  cost_cents=$(jq -r '.cost_cents // 0' "$state_file")

  echo "[sync-state] Logging run for ${agent_id} (status: ${status})..."
  log_run "$PROJECT_ID" "$agent_id" "$status" "$outputs" "$token_usage" "$cost_cents"
  echo "[sync-state] Run logged for ${agent_id}."
}

# ─── Sync Contacts ─────────────────────────────────────────────────────────

sync_contacts() {
  local agent_id="$1"
  local contacts_file="$PROJECT_ROOT/state/${agent_id}/new-contacts.json"

  if [[ ! -f "$contacts_file" ]]; then
    echo "[sync-state] No new-contacts.json found for ${agent_id}, skipping contacts sync."
    return 0
  fi

  local count
  count=$(jq 'length' "$contacts_file" 2>/dev/null || echo 0)

  if [[ "$count" -eq 0 ]]; then
    echo "[sync-state] No new contacts to sync for ${agent_id}."
    return 0
  fi

  echo "[sync-state] Syncing ${count} contacts from ${agent_id}..."

  local i=0
  while [[ $i -lt $count ]]; do
    local email data_json
    email=$(jq -r ".[$i].email // empty" "$contacts_file")
    data_json=$(jq -c ".[$i]" "$contacts_file")

    if [[ -n "$email" ]]; then
      contact_upsert "$PROJECT_ID" "$email" "$data_json" || {
        echo "[sync-state] WARNING: Failed to upsert contact ${email}" >&2
      }
    fi
    ((i++))
  done

  # Archive synced contacts file
  local archive_dir="$PROJECT_ROOT/state/${agent_id}/archive"
  mkdir -p "$archive_dir"
  mv "$contacts_file" "$archive_dir/contacts-$(date +%Y%m%d-%H%M%S).json"
  echo "[sync-state] Contacts synced and archived for ${agent_id}."
}

# ─── Sync All ──────────────────────────────────────────────────────────────

sync_all() {
  local agent_id="$1"
  echo "[sync-state] Starting full sync for ${agent_id}..."
  sync_run_results "$agent_id"
  sync_contacts "$agent_id"
  echo "[sync-state] Full sync complete for ${agent_id}."
}
