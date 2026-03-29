#!/usr/bin/env bash
# chmod +x lib/memory.sh
# GTM Company — Supabase Memory Layer
# Source this file in every agent: source "$(dirname "$0")/../lib/memory.sh"
#
# Required env vars: SUPABASE_URL, SUPABASE_ANON_KEY

set -euo pipefail

# ─── Helpers ────────────────────────────────────────────────────────────────

_sb_url() { echo "${SUPABASE_URL:?SUPABASE_URL not set}/rest/v1/$1"; }

_sb_headers() {
  echo -H "apikey: ${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY not set}"
  echo -H "Authorization: Bearer ${SUPABASE_ANON_KEY}"
  echo -H "Content-Type: application/json"
  echo -H "Prefer: return=representation"
}

_sb_get() {
  local endpoint="$1"
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    "$(_sb_url "$endpoint")")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "[memory.sh] ERROR GET $endpoint → HTTP $http_code: $body" >&2
    return 1
  fi
  echo "$body"
}

_sb_post() {
  local endpoint="$1"
  local data="$2"
  local prefer="${3:-return=representation}"
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: $prefer" \
    -d "$data" \
    "$(_sb_url "$endpoint")")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "[memory.sh] ERROR POST $endpoint → HTTP $http_code: $body" >&2
    return 1
  fi
  echo "$body"
}

_sb_patch() {
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
    "$(_sb_url "$endpoint")")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "[memory.sh] ERROR PATCH $endpoint → HTTP $http_code: $body" >&2
    return 1
  fi
  echo "$body"
}

# ─── Init / Connectivity ───────────────────────────────────────────────────

mem_init() {
  echo "[memory.sh] Verifying Supabase connectivity..."
  local response http_code
  response=$(curl -s -w "\n%{http_code}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    "${SUPABASE_URL}/rest/v1/" 2>/dev/null)
  http_code=$(echo "$response" | tail -1)
  if [[ "$http_code" -ge 400 ]]; then
    echo "[memory.sh] FATAL: Cannot connect to Supabase (HTTP $http_code)" >&2
    return 1
  fi
  echo "[memory.sh] Connected to Supabase at ${SUPABASE_URL}"
}

# ─── Memory CRUD ────────────────────────────────────────────────────────────

mem_get() {
  local project_id="$1" namespace="$2" key="$3"
  _sb_get "memories?project_id=eq.${project_id}&namespace=eq.${namespace}&key=eq.${key}&select=value,confidence,updated_at&limit=1"
}

mem_set() {
  local project_id="$1" namespace="$2" key="$3" value="$4"
  local confidence="${5:-0.8}" source="${6:-agent}"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local payload
  payload=$(cat <<EOF
{
  "project_id": "${project_id}",
  "namespace": "${namespace}",
  "key": "${key}",
  "value": $(echo "$value" | jq -R .),
  "confidence": ${confidence},
  "source": "${source}",
  "updated_at": "${now}"
}
EOF
)
  # Upsert using on_conflict
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=representation" \
    -d "$payload" \
    "$(_sb_url "memories")")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "[memory.sh] ERROR mem_set → HTTP $http_code: $body" >&2
    return 1
  fi
  echo "$body"
}

mem_search() {
  local project_id="$1" namespace="$2" query_fragment="$3"
  _sb_get "memories?project_id=eq.${project_id}&namespace=eq.${namespace}&key=ilike.*${query_fragment}*&select=key,value,confidence,updated_at&order=updated_at.desc&limit=20"
}

mem_list() {
  local project_id="$1" namespace="$2"
  _sb_get "memories?project_id=eq.${project_id}&namespace=eq.${namespace}&select=key,value,confidence,updated_at&order=updated_at.desc"
}

# ─── Contacts ───────────────────────────────────────────────────────────────

contact_check() {
  local project_id="$1" email="$2"
  _sb_get "contacts?project_id=eq.${project_id}&email=eq.${email}&select=id,email,status,data,updated_at&limit=1"
}

contact_upsert() {
  local project_id="$1" email="$2" data_json="$3"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local payload
  payload=$(cat <<EOF
{
  "project_id": "${project_id}",
  "email": "${email}",
  "data": ${data_json},
  "updated_at": "${now}"
}
EOF
)
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=representation" \
    -d "$payload" \
    "$(_sb_url "contacts")")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "[memory.sh] ERROR contact_upsert → HTTP $http_code: $body" >&2
    return 1
  fi
  echo "$body"
}

contact_list() {
  local project_id="$1" status="${2:-}"
  if [[ -n "$status" ]]; then
    _sb_get "contacts?project_id=eq.${project_id}&status=eq.${status}&select=id,email,status,data,updated_at&order=updated_at.desc"
  else
    _sb_get "contacts?project_id=eq.${project_id}&select=id,email,status,data,updated_at&order=updated_at.desc"
  fi
}

# ─── Agent Runs ─────────────────────────────────────────────────────────────

log_run() {
  local project_id="$1" agent_id="$2" status="$3" outputs_json="$4"
  local token_usage="${5:-0}" cost_cents="${6:-0}"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local payload
  payload=$(cat <<EOF
{
  "project_id": "${project_id}",
  "agent_id": "${agent_id}",
  "status": "${status}",
  "outputs": ${outputs_json},
  "token_usage": ${token_usage},
  "cost_cents": ${cost_cents},
  "created_at": "${now}"
}
EOF
)
  _sb_post "agent_runs" "$payload"
}

log_episode() {
  local project_id="$1" agent_id="$2" event_type="$3" description="$4"
  local outcome="${5:-}" learnings_json="${6:-null}"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local payload
  payload=$(cat <<EOF
{
  "project_id": "${project_id}",
  "agent_id": "${agent_id}",
  "event_type": "${event_type}",
  "description": $(echo "$description" | jq -R .),
  "outcome": $(echo "$outcome" | jq -R .),
  "learnings": ${learnings_json},
  "created_at": "${now}"
}
EOF
)
  _sb_post "episodes" "$payload"
}

get_recent_runs() {
  local project_id="$1" agent_id="$2" limit="${3:-5}"
  _sb_get "agent_runs?project_id=eq.${project_id}&agent_id=eq.${agent_id}&select=status,outputs,token_usage,cost_cents,created_at&order=created_at.desc&limit=${limit}"
}

get_recent_episodes() {
  local project_id="$1" limit="${2:-10}"
  _sb_get "episodes?project_id=eq.${project_id}&select=agent_id,event_type,description,outcome,learnings,created_at&order=created_at.desc&limit=${limit}"
}

echo "[memory.sh] Memory layer loaded."
