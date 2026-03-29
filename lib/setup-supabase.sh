#!/usr/bin/env bash
# setup-supabase.sh — Guides user through Supabase setup for GTM Company
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MIGRATION_FILE="$SCRIPT_DIR/supabase-migration.sql"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_EXAMPLE="$PROJECT_ROOT/.env.example"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; }
step()  { echo -e "\n${CYAN}==> $*${NC}"; }

# ──────────────────────────────────────────────
# Step 1: Check .env
# ──────────────────────────────────────────────
step "Step 1: Checking environment configuration"

if [ -f "$ENV_FILE" ]; then
  ok ".env file exists"
  source "$ENV_FILE"
else
  warn ".env file not found"
  if [ -f "$ENV_EXAMPLE" ]; then
    info "Creating .env from .env.example"
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    warn "Please edit .env with your actual Supabase credentials"
    echo ""
    echo "  Required variables:"
    echo "    SUPABASE_URL=https://your-project.supabase.co"
    echo "    SUPABASE_ANON_KEY=your-anon-key"
    echo "    SUPABASE_SERVICE_KEY=your-service-role-key"
    echo ""
    read -p "Press Enter after editing .env, or Ctrl+C to abort... "
    source "$ENV_FILE"
  else
    err "No .env or .env.example found"
    echo ""
    echo "Create .env with these variables:"
    echo ""
    echo "  SUPABASE_URL=https://your-project.supabase.co"
    echo "  SUPABASE_ANON_KEY=your-anon-key"
    echo "  SUPABASE_SERVICE_KEY=your-service-role-key"
    echo "  PROJECT_ID=my-gtm-project"
    echo ""
    exit 1
  fi
fi

# Validate required vars
MISSING=0
for VAR in SUPABASE_URL SUPABASE_ANON_KEY; do
  if [ -z "${!VAR:-}" ]; then
    err "Missing required variable: $VAR"
    MISSING=1
  fi
done
if [ "$MISSING" -eq 1 ]; then
  err "Please set all required variables in .env"
  exit 1
fi
ok "Required environment variables set"

# ──────────────────────────────────────────────
# Step 2: Test connectivity
# ──────────────────────────────────────────────
step "Step 2: Testing Supabase connectivity"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "${SUPABASE_URL}/rest/v1/" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
  2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
  ok "Supabase REST API reachable (HTTP $HTTP_CODE)"
elif [ "$HTTP_CODE" = "000" ]; then
  err "Cannot reach Supabase at ${SUPABASE_URL}"
  err "Check your SUPABASE_URL and network connection"
  exit 1
else
  warn "Supabase returned HTTP $HTTP_CODE (may still work)"
fi

# ──────────────────────────────────────────────
# Step 3: Run migration
# ──────────────────────────────────────────────
step "Step 3: Running database migration"

if ! [ -f "$MIGRATION_FILE" ]; then
  err "Migration file not found: $MIGRATION_FILE"
  exit 1
fi

echo ""
echo "  Choose migration method:"
echo "    1) Run via Supabase CLI (requires 'supabase' installed)"
echo "    2) Run via psql (requires database URL)"
echo "    3) Print SQL for manual copy into Supabase SQL Editor"
echo ""
read -p "  Choice [1/2/3]: " CHOICE

case "${CHOICE:-3}" in
  1)
    if command -v supabase &>/dev/null; then
      info "Running migration via Supabase CLI..."
      supabase db push --db-url "${DATABASE_URL:-}" < "$MIGRATION_FILE" 2>/dev/null || {
        warn "Supabase CLI push failed. Trying direct execution..."
        supabase sql --file "$MIGRATION_FILE" 2>/dev/null || {
          err "Supabase CLI execution failed"
          warn "Falling back to printing SQL..."
          CHOICE=3
        }
      }
      if [ "$CHOICE" != "3" ]; then
        ok "Migration applied via Supabase CLI"
      fi
    else
      warn "Supabase CLI not found. Install: brew install supabase/tap/supabase"
      CHOICE=3
    fi
    ;;
  2)
    if [ -z "${DATABASE_URL:-}" ]; then
      echo ""
      echo "  Enter your Supabase database URL:"
      echo "  (Find it in Supabase Dashboard > Settings > Database > Connection string > URI)"
      read -p "  DATABASE_URL: " DATABASE_URL
    fi
    if command -v psql &>/dev/null; then
      info "Running migration via psql..."
      psql "$DATABASE_URL" -f "$MIGRATION_FILE" && ok "Migration applied via psql" || {
        err "psql execution failed"
        CHOICE=3
      }
    else
      warn "psql not found. Install: brew install postgresql"
      CHOICE=3
    fi
    ;;
esac

if [ "${CHOICE:-3}" = "3" ]; then
  echo ""
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}  Copy the SQL below into Supabase SQL Editor:${NC}"
  echo -e "${YELLOW}  Dashboard > SQL Editor > New Query > Paste > Run${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  cat "$MIGRATION_FILE"
  echo ""
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  read -p "Press Enter after running the SQL in Supabase... "
fi

# ──────────────────────────────────────────────
# Step 4: Verify tables exist
# ──────────────────────────────────────────────
step "Step 4: Verifying tables"

AUTH_KEY="${SUPABASE_SERVICE_KEY:-${SUPABASE_ANON_KEY}}"
TABLES=("agent_runs" "memories" "contacts" "episodes")
ALL_OK=1

for TABLE in "${TABLES[@]}"; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${SUPABASE_URL}/rest/v1/${TABLE}?select=id&limit=0" \
    -H "apikey: ${AUTH_KEY}" \
    -H "Authorization: Bearer ${AUTH_KEY}" \
    2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "200" ]; then
    ok "Table '${TABLE}' exists and accessible"
  else
    err "Table '${TABLE}' not found or not accessible (HTTP $HTTP_CODE)"
    ALL_OK=0
  fi
done

echo ""
if [ "$ALL_OK" -eq 1 ]; then
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  Supabase setup complete!${NC}"
  echo -e "${GREEN}  All 4 tables created and verified.${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}  Some tables could not be verified.${NC}"
  echo -e "${RED}  Check Supabase Dashboard > Table Editor${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  exit 1
fi
