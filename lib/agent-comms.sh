#!/usr/bin/env bash
# chmod +x lib/agent-comms.sh
# GTM Company — Inter-Agent Communication Layer
# Source this file in every agent: source "$(dirname "$0")/../lib/agent-comms.sh"
#
# Agents don't talk to each other directly. They post messages to a shared
# Supabase `agent_messages` table. The orchestrator (and other agents) can
# read messages addressed to them.
#
# Required env vars: SUPABASE_URL, SUPABASE_ANON_KEY, PROJECT_ID

# Note: don't set -euo pipefail here — this file is sourced by other scripts

COMMS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Helpers ────────────────────────────────────────────────────────────────

_comms_url() { echo "${SUPABASE_URL:?SUPABASE_URL not set}/rest/v1/$1"; }

_comms_post() {
  local endpoint="$1"
  local data="$2"
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "apikey: ${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY not set}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "$data" \
    "$(_comms_url "$endpoint")")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "[agent-comms] ERROR POST $endpoint → HTTP $http_code: $body" >&2
    return 1
  fi
  echo "$body"
}

_comms_get() {
  local endpoint="$1"
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    "$(_comms_url "$endpoint")")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "[agent-comms] ERROR GET $endpoint → HTTP $http_code: $body" >&2
    return 1
  fi
  echo "$body"
}

_comms_patch() {
  local endpoint="$1"
  local data="$2"
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -X PATCH \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "$data" \
    "$(_comms_url "$endpoint")")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "[agent-comms] ERROR PATCH $endpoint → HTTP $http_code: $body" >&2
    return 1
  fi
  echo "$body"
}

# ─── Message Types ──────────────────────────────────────────────────────────
# task_complete    — agent finished a run, includes stats
# lead_found       — agent detected a warm lead
# escalation       — agent needs human attention on something
# strategy_update  — new strategy directives or content calendar
# health_alert     — agent health issue detected
# instruction      — task or directive for a specific agent

# ─── Send a message to a specific agent ─────────────────────────────────────
# Usage: send_message "cold-outreach" "orchestrator" "task_complete" '{"emails_drafted":5}'
# Usage: send_message "cold-outreach" "orchestrator" "escalation" '{"contact_id":"x","reason":"hostile reply"}' "urgent"
send_message() {
  local from_agent="$1"
  local to_agent="$2"
  local message_type="$3"
  local payload="$4"
  local priority="${5:-normal}"
  local project_id="${PROJECT_ID:?PROJECT_ID not set}"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local data
  data=$(cat <<EOF
{
  "project_id": "${project_id}",
  "from_agent": "${from_agent}",
  "to_agent": "${to_agent}",
  "message_type": "${message_type}",
  "payload": ${payload},
  "priority": "${priority}",
  "status": "unread",
  "created_at": "${now}"
}
EOF
)

  local result
  result=$(_comms_post "agent_messages" "$data") || {
    echo "[agent-comms] WARNING: Failed to send message from ${from_agent} to ${to_agent}" >&2
    return 1
  }
  echo "[agent-comms] Message sent: ${from_agent} → ${to_agent} (${message_type})"
  echo "$result"
}

# ─── Get messages for an agent ──────────────────────────────────────────────
# Usage: get_messages "orchestrator"           — all unread messages
# Usage: get_messages "orchestrator" "false"   — all messages (read and unread)
get_messages() {
  local agent_id="$1"
  local unread_only="${2:-true}"
  local project_id="${PROJECT_ID:?PROJECT_ID not set}"

  local filter="project_id=eq.${project_id}"

  # Get messages addressed to this agent OR broadcast (to_agent is null)
  if [[ "$unread_only" == "true" ]]; then
    filter="${filter}&status=eq.unread"
  fi

  # Messages directly to this agent
  local direct
  direct=$(_comms_get "agent_messages?${filter}&to_agent=eq.${agent_id}&select=*&order=priority.desc,created_at.asc") || echo "[]"

  # Broadcast messages (to_agent is null)
  # NOTE: Broadcasts should be filtered by created_at > agent's last_run timestamp
  # to avoid re-processing old broadcasts. The caller (run-agent.sh) should pass the
  # agent's last_run time and use it as a filter here, or mark broadcasts as processed
  # per-agent after reading them.
  local broadcasts
  broadcasts=$(_comms_get "agent_messages?${filter}&to_agent=is.null&select=*&order=priority.desc,created_at.asc") || echo "[]"

  # Merge the two arrays using jq
  echo "$direct" "$broadcasts" | jq -s 'add | sort_by(.created_at)' 2>/dev/null || echo "[]"
}

# ─── Mark a message as read ─────────────────────────────────────────────────
# Usage: mark_read "message-uuid"
mark_read() {
  local message_id="$1"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  _comms_patch "agent_messages?id=eq.${message_id}" "{\"status\": \"read\", \"processed_at\": \"${now}\"}"
}

# ─── Mark a message as processed ────────────────────────────────────────────
# Usage: mark_processed "message-uuid" "orchestrator"
mark_processed() {
  local message_id="$1"
  local processed_by="$2"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  _comms_patch "agent_messages?id=eq.${message_id}" "{\"status\": \"processed\", \"processed_at\": \"${now}\", \"processed_by\": \"${processed_by}\"}"
}

# ─── Broadcast to all agents ────────────────────────────────────────────────
# Usage: broadcast "weekly-strategist" "strategy_update" '{"directives":[...]}'
broadcast() {
  local from_agent="$1"
  local message_type="$2"
  local payload="$3"
  local priority="${4:-normal}"
  local project_id="${PROJECT_ID:?PROJECT_ID not set}"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local data
  data=$(cat <<EOF
{
  "project_id": "${project_id}",
  "from_agent": "${from_agent}",
  "to_agent": null,
  "message_type": "${message_type}",
  "payload": ${payload},
  "priority": "${priority}",
  "status": "unread",
  "created_at": "${now}"
}
EOF
)

  local result
  result=$(_comms_post "agent_messages" "$data") || {
    echo "[agent-comms] WARNING: Failed to broadcast from ${from_agent}" >&2
    return 1
  }
  echo "[agent-comms] Broadcast sent: ${from_agent} → ALL (${message_type})"
  echo "$result"
}

# ─── Get unprocessed escalations ────────────────────────────────────────────
# Usage: get_unprocessed_escalations
# Usage: get_unprocessed_escalations "ai-integrators-gtm"
get_unprocessed_escalations() {
  local project_id="${1:-${PROJECT_ID:?PROJECT_ID not set}}"

  _comms_get "agent_messages?project_id=eq.${project_id}&message_type=eq.escalation&status=in.(unread,read)&select=*&order=priority.desc,created_at.asc"
}

# ─── Queue a local outbound message (for batch sending after agent run) ─────
# Writes messages to a temp file that run-agent.sh processes after Claude exits
# Usage: queue_message "lead-router" "task_complete" '{"contacts_processed":15}'
# Persist outbound queue to state dir for crash recovery (falls back to /tmp if STATE_DIR unset)
if [[ -n "${STATE_DIR:-}" ]]; then
  mkdir -p "$STATE_DIR"
  OUTBOUND_QUEUE="${STATE_DIR}/outbound-queue.jsonl"
else
  OUTBOUND_QUEUE="${TMPDIR:-/tmp}/gtm-agent-outbound-$$"
fi

queue_message() {
  local to_agent="$1"
  local message_type="$2"
  local payload="$3"
  local priority="${4:-normal}"

  # Append to queue file as one JSON object per line (use jq for safe JSON construction)
  jq -n \
    --arg to "$to_agent" \
    --arg mt "$message_type" \
    --argjson pl "$payload" \
    --arg pr "$priority" \
    '{to_agent: $to, message_type: $mt, payload: $pl, priority: $pr}' >> "$OUTBOUND_QUEUE"
  echo "[agent-comms] Queued outbound: → ${to_agent} (${message_type})"
}

# ─── Queue a broadcast (for batch sending after agent run) ──────────────────
queue_broadcast() {
  local message_type="$1"
  local payload="$2"
  local priority="${3:-normal}"

  echo "{\"to_agent\":null,\"message_type\":\"${message_type}\",\"payload\":${payload},\"priority\":\"${priority}\"}" >> "$OUTBOUND_QUEUE"
  echo "[agent-comms] Queued broadcast: → ALL (${message_type})"
}

# ─── Flush the outbound queue (called by run-agent.sh after Claude exits) ───
# Usage: flush_outbound_queue "cold-outreach"
flush_outbound_queue() {
  local from_agent="$1"

  if [[ ! -f "$OUTBOUND_QUEUE" ]]; then
    echo "[agent-comms] No outbound messages to send."
    return 0
  fi

  local count=0
  while IFS= read -r line; do
    local to_agent message_type payload priority
    to_agent=$(echo "$line" | jq -r '.to_agent // empty')
    message_type=$(echo "$line" | jq -r '.message_type')
    payload=$(echo "$line" | jq -c '.payload')
    priority=$(echo "$line" | jq -r '.priority // "normal"')

    if [[ -z "$to_agent" || "$to_agent" == "null" ]]; then
      broadcast "$from_agent" "$message_type" "$payload" "$priority" >/dev/null 2>&1 || true
    else
      send_message "$from_agent" "$to_agent" "$message_type" "$payload" "$priority" >/dev/null 2>&1 || true
    fi
    count=$((count + 1))
  done < "$OUTBOUND_QUEUE"

  rm -f "$OUTBOUND_QUEUE"
  echo "[agent-comms] Flushed ${count} outbound messages for ${from_agent}."
}

# ─── Get inbound instructions (messages from orchestrator to this agent) ────
# Usage: get_inbound_instructions "cold-outreach"
get_inbound_instructions() {
  local agent_id="$1"
  local project_id="${PROJECT_ID:?PROJECT_ID not set}"

  _comms_get "agent_messages?project_id=eq.${project_id}&to_agent=eq.${agent_id}&message_type=eq.instruction&status=eq.unread&select=*&order=created_at.asc"
}

# ─── Cleanup old messages ──────────────────────────────────────────────────
# Archives messages older than 30 days to keep the table lean
# Usage: cleanup_old_messages
cleanup_old_messages() {
  local project_id="${PROJECT_ID:?PROJECT_ID not set}"
  local cutoff
  cutoff=$(date -u -v-30d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "30 days ago" +"%Y-%m-%dT%H:%M:%SZ")

  echo "[agent-comms] Archiving messages older than 30 days (before ${cutoff})..."
  _comms_patch "agent_messages?project_id=eq.${project_id}&created_at=lt.${cutoff}&status=neq.archived" \
    "{\"status\": \"archived\"}" || {
    echo "[agent-comms] WARNING: Failed to archive old messages" >&2
    return 1
  }
  echo "[agent-comms] Old messages archived."
}

echo "[agent-comms] Inter-agent communication layer loaded."
