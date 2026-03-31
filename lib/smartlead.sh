#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# SmartLead API Integration — GTM Company
# ═══════════════════════════════════════════════════════════════════════════════
# Bridges SmartLead cold email campaigns into the GTM dashboard via Supabase.
# Usage: source this file, then call functions directly.
#
#   source lib/smartlead.sh
#   sl_get_campaigns
#   sl_get_campaign_stats "12345"
#   sl_get_replies "12345"
#   sl_sync_to_supabase
#
# Required env vars:
#   SMARTLEAD_API_KEY    — SmartLead API key
#   SUPABASE_URL         — Supabase project URL
#   SUPABASE_SERVICE_KEY — Supabase service role key (for writes)
#   PROJECT_ID           — GTM project namespace (e.g., ai-integrators-gtm)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SMARTLEAD_BASE="https://server.smartlead.ai/api/v1"

# ─── Validation ──────────────────────────────────────────────────────────────

_sl_check_env() {
  if [[ -z "${SMARTLEAD_API_KEY:-}" ]]; then
    echo "[ERROR] SMARTLEAD_API_KEY not set" >&2
    return 1
  fi
}

_sb_check_env() {
  if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_KEY:-}" ]]; then
    echo "[ERROR] SUPABASE_URL and SUPABASE_SERVICE_KEY must be set" >&2
    return 1
  fi
  if [[ -z "${PROJECT_ID:-}" ]]; then
    echo "[ERROR] PROJECT_ID not set" >&2
    return 1
  fi
}

# ─── SmartLead API Functions ─────────────────────────────────────────────────

# List all campaigns
# Returns: JSON array of campaigns
sl_get_campaigns() {
  _sl_check_env || return 1
  curl -s "${SMARTLEAD_BASE}/campaigns?api_key=${SMARTLEAD_API_KEY}"
}

# Get analytics/stats for a specific campaign
# Args: $1 = campaign_id
# Returns: JSON with sent, opens, replies, bounces, etc.
sl_get_campaign_stats() {
  _sl_check_env || return 1
  local campaign_id="${1:?Usage: sl_get_campaign_stats <campaign_id>}"
  curl -s "${SMARTLEAD_BASE}/campaigns/${campaign_id}/analytics?api_key=${SMARTLEAD_API_KEY}"
}

# Get leads (with reply status) for a campaign
# Args: $1 = campaign_id, $2 = limit (default 100)
# Returns: JSON array of leads with status
sl_get_replies() {
  _sl_check_env || return 1
  local campaign_id="${1:?Usage: sl_get_replies <campaign_id>}"
  local limit="${2:-100}"
  curl -s "${SMARTLEAD_BASE}/campaigns/${campaign_id}/leads?api_key=${SMARTLEAD_API_KEY}&limit=${limit}"
}

# ─── Supabase Sync ───────────────────────────────────────────────────────────

# Upsert a single campaign stat row into Supabase
# Args: JSON string of the row to upsert
_sb_upsert_campaign_stat() {
  local payload="$1"
  curl -s -X POST \
    "${SUPABASE_URL}/rest/v1/campaign_stats" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates" \
    -d "${payload}"
}

# Insert an episode row (for replies)
_sb_insert_episode() {
  local payload="$1"
  curl -s -X POST \
    "${SUPABASE_URL}/rest/v1/episodes" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d "${payload}"
}

# Insert an agent_runs row
_sb_insert_agent_run() {
  local payload="$1"
  curl -s -X POST \
    "${SUPABASE_URL}/rest/v1/agent_runs" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d "${payload}"
}

# ─── Main Sync Function ─────────────────────────────────────────────────────

# Pull all SmartLead data and write to Supabase campaign_stats table.
# Also logs new replies as episodes and creates an agent_run entry.
sl_sync_to_supabase() {
  _sl_check_env || return 1
  _sb_check_env || return 1

  local run_start
  run_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local total_sent=0
  local total_opens=0
  local total_replies=0
  local total_bounces=0
  local total_unsubscribed=0
  local campaign_count=0
  local sync_errors=0

  echo "[smartlead-sync] Starting SmartLead -> Supabase sync at ${run_start}"

  # 1. Fetch all campaigns
  local campaigns_json
  campaigns_json="$(sl_get_campaigns)" || {
    echo "[ERROR] Failed to fetch campaigns from SmartLead" >&2
    return 1
  }

  local campaign_ids
  campaign_ids="$(echo "${campaigns_json}" | jq -r '.[].id // empty' 2>/dev/null)"

  if [[ -z "${campaign_ids}" ]]; then
    echo "[smartlead-sync] No campaigns found"
    return 0
  fi

  # 2. For each campaign, fetch stats and upsert to Supabase
  while IFS= read -r cid; do
    [[ -z "${cid}" ]] && continue

    local cname
    cname="$(echo "${campaigns_json}" | jq -r --arg id "${cid}" '.[] | select(.id == ($id | tonumber)) | .name // "Unknown"' 2>/dev/null)"
    local cstatus
    cstatus="$(echo "${campaigns_json}" | jq -r --arg id "${cid}" '.[] | select(.id == ($id | tonumber)) | .status // "active"' 2>/dev/null)"

    echo "[smartlead-sync] Processing campaign: ${cname} (${cid})"

    # Fetch analytics
    local stats_json
    stats_json="$(sl_get_campaign_stats "${cid}")" || {
      echo "[WARN] Failed to fetch stats for campaign ${cid}" >&2
      ((sync_errors++)) || true
      continue
    }

    # Extract stats (SmartLead analytics response varies; handle gracefully)
    local sent opens replies bounces unsubscribed leads_total reply_rate
    sent="$(echo "${stats_json}" | jq '.sent_count // .total_emails_sent // 0' 2>/dev/null || echo 0)"
    opens="$(echo "${stats_json}" | jq '.open_count // .total_opens // 0' 2>/dev/null || echo 0)"
    replies="$(echo "${stats_json}" | jq '.reply_count // .total_replies // 0' 2>/dev/null || echo 0)"
    bounces="$(echo "${stats_json}" | jq '.bounce_count // .total_bounces // 0' 2>/dev/null || echo 0)"
    unsubscribed="$(echo "${stats_json}" | jq '.unsubscribe_count // .total_unsubscribes // 0' 2>/dev/null || echo 0)"
    leads_total="$(echo "${stats_json}" | jq '.total_leads // .leads_count // 0' 2>/dev/null || echo 0)"

    # Calculate reply rate
    if [[ "${sent}" -gt 0 ]]; then
      reply_rate="$(echo "scale=4; ${replies} / ${sent}" | bc 2>/dev/null || echo 0)"
    else
      reply_rate="0"
    fi

    # Build sequence_steps JSON if available
    local sequence_steps
    sequence_steps="$(echo "${stats_json}" | jq '.sequence_stats // {}' 2>/dev/null || echo '{}')"

    # Upsert to campaign_stats
    local upsert_payload
    upsert_payload="$(jq -n \
      --arg id "sl-${cid}" \
      --arg pid "${PROJECT_ID}" \
      --arg name "${cname}" \
      --arg status "${cstatus}" \
      --argjson sent "${sent}" \
      --argjson opens "${opens}" \
      --argjson replies "${replies}" \
      --argjson bounces "${bounces}" \
      --argjson unsub "${unsubscribed}" \
      --argjson leads "${leads_total}" \
      --argjson leads_contacted "${sent}" \
      --argjson rate "${reply_rate}" \
      --argjson seq "${sequence_steps}" \
      '{
        id: $id,
        project_id: $pid,
        campaign_name: $name,
        campaign_type: "cold_email",
        status: $status,
        sent: $sent,
        opens: $opens,
        replies: $replies,
        bounces: $bounces,
        unsubscribed: $unsub,
        leads_total: $leads,
        leads_contacted: $leads_contacted,
        reply_rate: $rate,
        sequence_steps: $seq,
        updated_at: now
      }' | sed 's/"now"/now()/g')"

    # Use proper timestamp
    upsert_payload="$(jq -n \
      --arg id "sl-${cid}" \
      --arg pid "${PROJECT_ID}" \
      --arg name "${cname}" \
      --arg status "${cstatus}" \
      --argjson sent "${sent}" \
      --argjson opens "${opens}" \
      --argjson replies "${replies}" \
      --argjson bounces "${bounces}" \
      --argjson unsub "${unsubscribed}" \
      --argjson leads "${leads_total}" \
      --argjson leads_contacted "${sent}" \
      --argjson rate "${reply_rate}" \
      --argjson seq "${sequence_steps}" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{
        id: $id,
        project_id: $pid,
        campaign_name: $name,
        campaign_type: "cold_email",
        status: $status,
        sent: $sent,
        opens: $opens,
        replies: $replies,
        bounces: $bounces,
        unsubscribed: $unsub,
        leads_total: $leads,
        leads_contacted: $leads_contacted,
        reply_rate: $rate,
        sequence_steps: $seq,
        updated_at: $ts
      }')"

    _sb_upsert_campaign_stat "${upsert_payload}" || {
      echo "[WARN] Failed to upsert stats for campaign ${cid}" >&2
      ((sync_errors++)) || true
    }

    # Accumulate totals
    total_sent=$((total_sent + sent))
    total_opens=$((total_opens + opens))
    total_replies=$((total_replies + replies))
    total_bounces=$((total_bounces + bounces))
    total_unsubscribed=$((total_unsubscribed + unsubscribed))
    ((campaign_count++)) || true

    echo "[smartlead-sync]   -> sent=${sent} opens=${opens} replies=${replies} bounces=${bounces}"

  done <<< "${campaign_ids}"

  # 3. Log the sync as an agent_run
  local run_end
  run_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local run_payload
  run_payload="$(jq -n \
    --arg pid "${PROJECT_ID}" \
    --arg start "${run_start}" \
    --arg end "${run_end}" \
    --argjson sent "${total_sent}" \
    --argjson opens "${total_opens}" \
    --argjson replies "${total_replies}" \
    --argjson bounces "${total_bounces}" \
    --argjson campaigns "${campaign_count}" \
    --argjson errors "${sync_errors}" \
    '{
      project_id: $pid,
      agent_id: "cold-outreach",
      started_at: $start,
      ended_at: $end,
      status: (if $errors > 0 then "partial" else "completed" end),
      outputs: {
        source: "smartlead_sync",
        campaigns_synced: $campaigns,
        total_sent: $sent,
        total_opens: $opens,
        total_replies: $replies,
        total_bounces: $bounces,
        sync_errors: $errors
      }
    }')"

  _sb_insert_agent_run "${run_payload}" || {
    echo "[WARN] Failed to log sync run to agent_runs" >&2
  }

  echo "[smartlead-sync] Complete: ${campaign_count} campaigns synced"
  echo "[smartlead-sync] Totals: sent=${total_sent} opens=${total_opens} replies=${total_replies} bounces=${total_bounces}"
  echo "[smartlead-sync] Errors: ${sync_errors}"
}

# ─── Convenience ─────────────────────────────────────────────────────────────

# Print a summary of all campaigns (for terminal use)
sl_summary() {
  _sl_check_env || return 1
  local campaigns
  campaigns="$(sl_get_campaigns)"
  echo "${campaigns}" | jq -r '.[] | "\(.id)\t\(.name)\t\(.status)"' 2>/dev/null
}
