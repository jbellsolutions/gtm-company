#!/usr/bin/env bash
# chmod +x deploy.sh
# GTM Company — Deploy to VPS
#
# Usage: ./deploy.sh <vps-host> [--setup]
#
# Deploys the entire GTM Company autonomous agent system to a VPS.
# Use --setup on first deploy to run Supabase migrations.
#
# VPS Requirements:
#   - SSH access (key-based auth)
#   - Claude Code installed and authenticated
#   - Node.js 22+
#   - Git
#   - jq
#   - curl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Parse arguments ─────────────────────────────────────────────────────────

VPS_HOST="${1:?Usage: deploy.sh <vps-host> [--setup]}"
SETUP_FLAG=""
if [[ "${2:-}" == "--setup" ]]; then
  SETUP_FLAG="true"
fi

VPS_USER="${VPS_USER:-paperclip}"
REMOTE_DIR="${REMOTE_DIR:-/home/${VPS_USER}/gtm-company}"
REPO_URL="${REPO_URL:-}"

echo "============================================"
echo " GTM Company — Deploy"
echo " Target: ${VPS_USER}@${VPS_HOST}"
echo " Remote dir: ${REMOTE_DIR}"
echo " Setup mode: ${SETUP_FLAG:-false}"
echo " $(date)"
echo "============================================"
echo ""

# ─── 1. Check VPS prerequisites ─────────────────────────────────────────────

echo "[deploy] Step 1: Checking VPS prerequisites..."

ssh "${VPS_USER}@${VPS_HOST}" bash <<'REMOTE_CHECK'
set -e
echo "  Checking commands..."

for cmd in claude node git jq curl; do
  if command -v "$cmd" &>/dev/null; then
    echo "    [OK] $cmd: $(command -v $cmd)"
  else
    echo "    [MISSING] $cmd — install before deploying" >&2
    exit 1
  fi
done

echo "  Checking Node version..."
NODE_VER=$(node --version)
echo "    Node: ${NODE_VER}"

echo "  Checking disk space..."
DISK=$(df -h / | tail -1 | awk '{print $4}')
echo "    Available: ${DISK}"

echo "  Prerequisites OK."
REMOTE_CHECK

echo ""

# ─── 2. Deploy code ─────────────────────────────────────────────────────────

echo "[deploy] Step 2: Deploying code to VPS..."

if [[ -n "$REPO_URL" ]]; then
  # Clone from git
  ssh "${VPS_USER}@${VPS_HOST}" bash <<REMOTE_GIT
set -e
if [[ -d "${REMOTE_DIR}/.git" ]]; then
  echo "  Pulling latest..."
  cd "${REMOTE_DIR}"
  git pull --ff-only
else
  echo "  Cloning repo..."
  git clone "${REPO_URL}" "${REMOTE_DIR}"
fi
REMOTE_GIT
else
  # rsync the local directory
  echo "  Syncing local files via rsync..."
  rsync -avz --exclude '.git' --exclude 'node_modules' --exclude 'logs/*.log' \
    --exclude '.env' --exclude 'state/*/last-run.json' \
    "${SCRIPT_DIR}/" "${VPS_USER}@${VPS_HOST}:${REMOTE_DIR}/"
fi

echo ""

# ─── 3. Copy .env file ──────────────────────────────────────────────────────

echo "[deploy] Step 3: Copying .env file..."

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  scp "${SCRIPT_DIR}/.env" "${VPS_USER}@${VPS_HOST}:${REMOTE_DIR}/.env"
  echo "  .env copied."
else
  echo "  WARNING: No local .env file found. Make sure ${REMOTE_DIR}/.env exists on VPS."
fi

echo ""

# ─── 4. Run Supabase migration (if --setup) ─────────────────────────────────

if [[ "$SETUP_FLAG" == "true" ]]; then
  echo "[deploy] Step 4: Running Supabase migrations..."

  ssh "${VPS_USER}@${VPS_HOST}" bash <<REMOTE_MIGRATE
set -e
cd "${REMOTE_DIR}"
source .env

echo "  Running v1 migration..."
if [[ -f lib/supabase-migration.sql ]]; then
  curl -s -X POST "\${SUPABASE_URL}/rest/v1/rpc/exec_sql" \
    -H "apikey: \${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer \${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"\$(cat lib/supabase-migration.sql | sed 's/"/\\\\"/g' | tr '\n' ' ')\"}" \
    && echo "  v1 migration applied." \
    || echo "  v1 migration: may already exist (continuing)."
fi

echo "  Running v2 migration (agent_messages)..."
if [[ -f lib/supabase-migration-v2.sql ]]; then
  curl -s -X POST "\${SUPABASE_URL}/rest/v1/rpc/exec_sql" \
    -H "apikey: \${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer \${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"\$(cat lib/supabase-migration-v2.sql | sed 's/"/\\\\"/g' | tr '\n' ' ')\"}" \
    && echo "  v2 migration applied." \
    || echo "  v2 migration: may already exist (continuing)."
fi

echo "  Migrations complete."
REMOTE_MIGRATE
else
  echo "[deploy] Step 4: Skipping migrations (use --setup to run)"
fi

echo ""

# ─── 5. Set up directory structure ──────────────────────────────────────────

echo "[deploy] Step 5: Setting up directories and permissions..."

ssh "${VPS_USER}@${VPS_HOST}" bash <<REMOTE_DIRS
set -e
cd "${REMOTE_DIR}"

# Create required directories
mkdir -p logs
mkdir -p state/orchestrator
mkdir -p state/cold-outreach
mkdir -p state/linkedin-engage
mkdir -p state/lead-router
mkdir -p state/content-strategist
mkdir -p state/weekly-strategist

# Make scripts executable
chmod +x lib/run-agent.sh
chmod +x lib/autopilot.sh
chmod +x lib/agent-comms.sh
chmod +x lib/memory.sh
chmod +x lib/sync-state.sh

echo "  Directories and permissions set."
REMOTE_DIRS

echo ""

# ─── 6. Install cron schedules ──────────────────────────────────────────────

echo "[deploy] Step 6: Setting up agent schedules via crontab..."

ssh "${VPS_USER}@${VPS_HOST}" bash <<REMOTE_CRON
set -e
cd "${REMOTE_DIR}"

# Use autopilot.sh to install schedules
./lib/autopilot.sh start

echo "  Schedules installed."
REMOTE_CRON

echo ""

# ─── 7. Verify first heartbeat ──────────────────────────────────────────────

echo "[deploy] Step 7: Waiting for first orchestrator heartbeat..."

# Give the orchestrator 60 seconds to complete its first heartbeat
echo "  Waiting up to 60 seconds..."
for i in $(seq 1 12); do
  sleep 5
  HEARTBEAT_EXISTS=$(ssh "${VPS_USER}@${VPS_HOST}" \
    "test -f ${REMOTE_DIR}/state/orchestrator/last-heartbeat.json && echo 'yes' || echo 'no'")
  if [[ "$HEARTBEAT_EXISTS" == "yes" ]]; then
    echo "  First heartbeat confirmed."
    break
  fi
  echo "  Still waiting... (${i}/12)"
done

if [[ "$HEARTBEAT_EXISTS" != "yes" ]]; then
  echo "  WARNING: First heartbeat not detected within 60 seconds."
  echo "  Check logs: ssh ${VPS_USER}@${VPS_HOST} 'tail -50 ${REMOTE_DIR}/logs/orchestrator.log'"
fi

echo ""

# ─── 8. Print status ────────────────────────────────────────────────────────

echo "[deploy] Step 8: Deployment status..."
echo ""

ssh "${VPS_USER}@${VPS_HOST}" bash <<REMOTE_STATUS
cd "${REMOTE_DIR}"
./lib/autopilot.sh status
REMOTE_STATUS

echo ""
echo "============================================"
echo " GTM Company — Deployment Complete"
echo "============================================"
echo ""
echo " VPS: ${VPS_USER}@${VPS_HOST}"
echo " Dir: ${REMOTE_DIR}"
echo ""
echo " Check status:   ssh ${VPS_USER}@${VPS_HOST} 'cd ${REMOTE_DIR} && ./lib/autopilot.sh status'"
echo " View logs:      ssh ${VPS_USER}@${VPS_HOST} 'tail -f ${REMOTE_DIR}/logs/orchestrator.log'"
echo " Stop agents:    ssh ${VPS_USER}@${VPS_HOST} 'cd ${REMOTE_DIR} && ./lib/autopilot.sh stop'"
echo " Manual run:     ssh ${VPS_USER}@${VPS_HOST} 'cd ${REMOTE_DIR} && ./lib/run-agent.sh <agent-name>'"
echo ""
echo "============================================"
