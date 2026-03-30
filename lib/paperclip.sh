#!/usr/bin/env bash
# GTM Company — Paperclip Integration Library
#
# Provides functions for reporting agent activity to the Paperclip
# operations dashboard (heartbeats, issues, costs).
#
# Usage: source lib/paperclip.sh

PAPERCLIP_URL="${PAPERCLIP_URL:-http://localhost:3100}"
PAPERCLIP_COMPANY_ID="${PAPERCLIP_COMPANY_ID:-886062c6-ef67-403c-8508-ad6c849d5e05}"

# Agent name -> Paperclip UUID mapping
declare -A PAPERCLIP_AGENTS=(
  [orchestrator]="13c96703-7801-49a1-94e0-961c95ac3813"
  [cold-outreach]="2db070e1-41ab-46bd-80c1-935ddaab7264"
  [linkedin-engage]="a6d8fd54-cc12-4af5-b560-45fd0f51ae1b"
  [lead-router]="b4d10298-c3e5-4408-8b0b-1c7ead46521e"
  [content-strategist]="e9c0de4f-5fcb-4a43-97fc-a9417bb1c98d"
  [weekly-strategist]="941d135d-1650-4339-a174-c5a83124027a"
)

# ─── pc_get_agent_id ──────────────────────────────────────────────────────────
# Resolve an agent name to its Paperclip UUID.
# Returns empty string and exits 1 if agent not found.
#
# Usage: pc_get_agent_id "orchestrator"
pc_get_agent_id() {
  local agent_name="${1:?Usage: pc_get_agent_id <agent-name>}"
  local agent_id="${PAPERCLIP_AGENTS[$agent_name]:-}"
  if [[ -z "$agent_id" ]]; then
    echo "[paperclip] WARNING: Unknown agent '${agent_name}' — not registered in Paperclip" >&2
    return 1
  fi
  echo "$agent_id"
}

# ─── pc_heartbeat ─────────────────────────────────────────────────────────────
# Send a heartbeat to Paperclip for the given agent.
#
# Usage: pc_heartbeat "orchestrator" "running" "Starting agent run"
# Status values: running, succeeded, failed, error, idle
pc_heartbeat() {
  local agent_name="${1:?Usage: pc_heartbeat <agent-name> <status> [message]}"
  local status="${2:?Usage: pc_heartbeat <agent-name> <status> [message]}"
  local message="${3:-}"

  local agent_id
  agent_id=$(pc_get_agent_id "$agent_name") || return 0

  local payload
  payload=$(jq -n \
    --arg status "$status" \
    --arg message "$message" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      status: $status,
      session: {
        timestamp: $timestamp,
        message: $message
      },
      stdout: $message
    }')

  curl -s -X POST \
    "${PAPERCLIP_URL}/api/companies/${PAPERCLIP_COMPANY_ID}/agents/${agent_id}/heartbeat" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    --max-time 5 \
    > /dev/null 2>&1 || {
      echo "[paperclip] WARNING: Heartbeat failed for ${agent_name} (${status})" >&2
    }
}

# ─── pc_update_agent_status ───────────────────────────────────────────────────
# Update an agent's status in Paperclip. Thin wrapper around heartbeat.
#
# Usage: pc_update_agent_status "orchestrator" "idle"
pc_update_agent_status() {
  local agent_name="${1:?Usage: pc_update_agent_status <agent-name> <status>}"
  local status="${2:?Usage: pc_update_agent_status <agent-name> <status>}"
  pc_heartbeat "$agent_name" "$status" "Status updated to ${status}"
}

# ─── pc_create_issue ──────────────────────────────────────────────────────────
# Create an issue/task in Paperclip for the given agent.
#
# Usage: pc_create_issue "Fix email template" "The template has a typo" "cold-outreach" "high"
# Priority values: low, medium, high, critical
pc_create_issue() {
  local title="${1:?Usage: pc_create_issue <title> <description> <agent-name> [priority]}"
  local description="${2:-}"
  local agent_name="${3:-}"
  local priority="${4:-medium}"

  local agent_id=""
  if [[ -n "$agent_name" ]]; then
    agent_id=$(pc_get_agent_id "$agent_name") || agent_id=""
  fi

  local payload
  payload=$(jq -n \
    --arg title "$title" \
    --arg description "$description" \
    --arg priority "$priority" \
    --arg agentId "$agent_id" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      title: $title,
      description: $description,
      priority: $priority,
      agentId: (if $agentId != "" then $agentId else null end),
      createdAt: $timestamp
    }')

  local response
  response=$(curl -s -X POST \
    "${PAPERCLIP_URL}/api/companies/${PAPERCLIP_COMPANY_ID}/issues" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    --max-time 10 \
    2>/dev/null) || {
      echo "[paperclip] WARNING: Failed to create issue '${title}'" >&2
      return 1
    }

  echo "$response"
}

# ─── pc_log_cost ──────────────────────────────────────────────────────────────
# Report cost/token usage to Paperclip for the given agent.
#
# Usage: pc_log_cost "orchestrator" 150 25000
#   cost_cents = 150 (i.e. $1.50)
#   tokens = 25000
pc_log_cost() {
  local agent_name="${1:?Usage: pc_log_cost <agent-name> <cost_cents> [tokens]}"
  local cost_cents="${2:?Usage: pc_log_cost <agent-name> <cost_cents> [tokens]}"
  local tokens="${3:-0}"

  local agent_id
  agent_id=$(pc_get_agent_id "$agent_name") || return 0

  local payload
  payload=$(jq -n \
    --argjson costCents "$cost_cents" \
    --argjson tokens "$tokens" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      status: "cost_report",
      session: {
        timestamp: $timestamp,
        costCents: $costCents,
        tokens: $tokens
      },
      stdout: ("Cost: " + ($costCents | tostring) + " cents, Tokens: " + ($tokens | tostring))
    }')

  curl -s -X POST \
    "${PAPERCLIP_URL}/api/companies/${PAPERCLIP_COMPANY_ID}/agents/${agent_id}/heartbeat" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    --max-time 5 \
    > /dev/null 2>&1 || {
      echo "[paperclip] WARNING: Cost log failed for ${agent_name}" >&2
    }
}

echo "[paperclip] Library loaded (${#PAPERCLIP_AGENTS[@]} agents registered)"
