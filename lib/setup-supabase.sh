#!/usr/bin/env bash
# setup-supabase.sh — Initialize Supabase for a GTM Company project
# Usage: bash lib/setup-supabase.sh
#
# Reads SUPABASE_URL and SUPABASE_ANON_KEY from .env, tests connectivity,
# runs migration SQL files (v1 + v2), creates agent_status table, seeds
# agent_status rows for all 8 agents, enables Realtime publication on all
# tables, and verifies all 6 tables exist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}  [OK]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }
step()  { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }

ERRORS=0
WARNINGS=0

# ──────────────────────────────────────────────
# Load .env
# ──────────────────────────────────────────────

ENV_FILE="$PROJECT_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  err "No .env file found at $ENV_FILE"
  err "Copy .env.example to .env and fill in your Supabase credentials."
  exit 1
fi

# Source .env safely (handle quoted values)
set -a
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  val="${val%\"}" ; val="${val#\"}" ; val="${val%\'}" ; val="${val#\'}"
  export "$key=$val"
done < "$ENV_FILE"
set +a

if [[ -z "${SUPABASE_URL:-}" ]]; then
  err "SUPABASE_URL not set in .env"; exit 1
fi
if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
  err "SUPABASE_ANON_KEY not set in .env"; exit 1
fi

echo ""
echo -e "${BOLD}${BLUE}GTM Company — Supabase Setup${NC}"
echo -e "URL: ${SUPABASE_URL}"
echo ""

# ──────────────────────────────────────────────
# Helper: run SQL via best available method
# ──────────────────────────────────────────────

AUTH_KEY="${SUPABASE_SERVICE_KEY:-${SUPABASE_ANON_KEY}}"

run_sql() {
  local sql="$1"
  local label="$2"

  # Method 1: psql if DATABASE_URL is set
  if [[ -n "${DATABASE_URL:-}" ]] && command -v psql &>/dev/null; then
    echo "$sql" | psql "$DATABASE_URL" -f - 2>&1 && return 0
  fi

  # Method 2: Supabase SQL RPC endpoint
  local response http_code body
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${AUTH_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg sql "$sql" '{query: $sql}')" \
    "${SUPABASE_URL}/rest/v1/rpc/exec_sql" 2>/dev/null)
  http_code=$(echo "$response" | tail -1)

  if [[ "$http_code" -lt 400 ]]; then
    return 0
  fi

  # Method 3: pg-meta endpoint
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${AUTH_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg sql "$sql" '{query: $sql}')" \
    "${SUPABASE_URL}/pg/query" 2>/dev/null)
  http_code=$(echo "$response" | tail -1)

  if [[ "$http_code" -lt 400 ]]; then
    return 0
  fi

  return 1
}

run_sql_file() {
  local sql_file="$1"
  local label="$2"

  if [[ ! -f "$sql_file" ]]; then
    warn "SQL file not found: $sql_file"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  info "Running $label: $(basename "$sql_file")"
  local sql_content
  sql_content=$(cat "$sql_file")

  if run_sql "$sql_content" "$label"; then
    ok "$label complete"
  else
    warn "$label failed via API. Run this SQL manually in the Supabase SQL Editor:"
    warn "  File: $sql_file"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
}

# ──────────────────────────────────────────────
# Step 1: Test connectivity
# ──────────────────────────────────────────────
step "Step 1: Testing Supabase connectivity"

CONN_RESP=$(curl -s -w "\n%{http_code}" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
  "${SUPABASE_URL}/rest/v1/" 2>/dev/null)
CONN_CODE=$(echo "$CONN_RESP" | tail -1)

if [[ "$CONN_CODE" -ge 400 || "$CONN_CODE" == "000" ]]; then
  err "Cannot connect to Supabase (HTTP $CONN_CODE)"
  err "Check SUPABASE_URL and SUPABASE_ANON_KEY in .env"
  exit 1
fi
ok "Connected to Supabase"

# ──────────────────────────────────────────────
# Step 2: Run migration v1 (core tables)
# ──────────────────────────────────────────────
step "Step 2: Running migration v1 (core tables)"
run_sql_file "$SCRIPT_DIR/supabase-migration.sql" "Migration v1"

# ──────────────────────────────────────────────
# Step 3: Run migration v2 (agent_messages)
# ──────────────────────────────────────────────
step "Step 3: Running migration v2 (agent_messages)"
run_sql_file "$SCRIPT_DIR/supabase-migration-v2.sql" "Migration v2"

# ──────────────────────────────────────────────
# Step 4: Create agent_status table
# ──────────────────────────────────────────────
step "Step 4: Creating agent_status table"

AGENT_STATUS_SQL=$(cat <<'EOSQL'
CREATE TABLE IF NOT EXISTS agent_status (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id text NOT NULL,
  agent_id text NOT NULL,
  status text DEFAULT 'idle' CHECK (status IN ('idle', 'running', 'error', 'disabled')),
  last_run_at timestamptz,
  next_run_at timestamptz,
  run_count integer DEFAULT 0,
  error_count integer DEFAULT 0,
  last_error text,
  config jsonb DEFAULT '{}',
  updated_at timestamptz DEFAULT now(),
  UNIQUE(project_id, agent_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_status_project ON agent_status(project_id);
CREATE INDEX IF NOT EXISTS idx_agent_status_agent ON agent_status(project_id, agent_id);

ALTER TABLE agent_status ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow all for agent_status') THEN
    CREATE POLICY "Allow all for agent_status" ON agent_status FOR ALL USING (true);
  END IF;
END $$;
EOSQL
)

if run_sql "$AGENT_STATUS_SQL" "agent_status"; then
  ok "agent_status table created"
else
  warn "Could not create agent_status via API. Run the SQL manually."
  WARNINGS=$((WARNINGS + 1))
fi

# ──────────────────────────────────────────────
# Step 5: Seed agent_status rows for all 8 agents
# ──────────────────────────────────────────────
step "Step 5: Seeding agent_status rows"

PROJECT_ID="${PROJECT_ID:-$(jq -r '.project_id // empty' "$PROJECT_ROOT/config/project.json" 2>/dev/null || basename "$PROJECT_ROOT")}"

AGENTS=("cold-outreach" "linkedin-engage" "lead-router" "content-strategist" "weekly-strategist" "power-partnerships" "content-engine" "orchestrator")

for agent in "${AGENTS[@]}"; do
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  SEED_PAYLOAD=$(jq -n \
    --arg pid "$PROJECT_ID" \
    --arg aid "$agent" \
    --arg now "$NOW" \
    '{project_id: $pid, agent_id: $aid, status: "idle", run_count: 0, error_count: 0, updated_at: $now}')

  SEED_RESP=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=representation" \
    -d "$SEED_PAYLOAD" \
    "${SUPABASE_URL}/rest/v1/agent_status" 2>/dev/null)
  SEED_CODE=$(echo "$SEED_RESP" | tail -1)

  if [[ "$SEED_CODE" -lt 400 ]]; then
    ok "Seeded: $agent"
  else
    warn "Failed to seed agent_status for $agent (HTTP $SEED_CODE)"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# ──────────────────────────────────────────────
# Step 6: Enable Realtime publication
# ──────────────────────────────────────────────
step "Step 6: Enabling Realtime publication"

REALTIME_SQL="ALTER PUBLICATION supabase_realtime ADD TABLE agent_runs, memories, contacts, episodes, agent_messages, agent_status;"

if run_sql "$REALTIME_SQL" "Realtime"; then
  ok "Realtime enabled on all tables"
else
  warn "Realtime publication may need manual setup in Supabase SQL Editor."
  WARNINGS=$((WARNINGS + 1))
fi

# ──────────────────────────────────────────────
# Step 7: Verify all 6 tables exist
# ──────────────────────────────────────────────
step "Step 7: Verifying all tables"

EXPECTED_TABLES=("agent_runs" "memories" "contacts" "episodes" "agent_messages" "agent_status")

for table in "${EXPECTED_TABLES[@]}"; do
  VERIFY_RESP=$(curl -s -w "\n%{http_code}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    "${SUPABASE_URL}/rest/v1/${table}?limit=0" 2>/dev/null)
  VERIFY_CODE=$(echo "$VERIFY_RESP" | tail -1)

  if [[ "$VERIFY_CODE" -lt 400 ]]; then
    ok "Table exists: $table"
  else
    err "Table NOT found: $table (HTTP $VERIFY_CODE)"
    ERRORS=$((ERRORS + 1))
  fi
done

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo ""
echo "========================================="
if [[ "$ERRORS" -eq 0 && "$WARNINGS" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  Supabase setup complete!${NC}"
  echo -e "${GREEN}  All 6 tables created and verified.${NC}"
  echo -e "${GREEN}  Realtime publication enabled.${NC}"
  echo -e "${GREEN}  8 agents seeded in agent_status.${NC}"
elif [[ "$ERRORS" -eq 0 ]]; then
  echo -e "${YELLOW}${BOLD}  Setup complete with $WARNINGS warnings.${NC}"
  echo -e "  Some operations may need manual SQL execution."
else
  echo -e "${RED}${BOLD}  Setup completed with $ERRORS errors and $WARNINGS warnings.${NC}"
  echo -e "  Check the output above and run missing SQL manually."
fi
echo "========================================="
echo ""
