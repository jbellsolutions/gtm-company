#!/usr/bin/env bash
# scaffold.sh — GTM Company Template Scaffold Engine
# Usage: ./scaffold.sh <template-id> <project-name> [--config config.json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
LIB_DIR="$SCRIPT_DIR/lib"
OUTPUT_BASE="$HOME/Desktop"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}  [OK]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERR]${NC}   $*" >&2; }
step()    { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }
substep() { echo -e "  ${CYAN}-->$NC $*"; }

# ──────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────
show_help() {
  cat <<EOF
${BOLD}GTM Company Scaffold Engine${NC}

${BOLD}Usage:${NC}
  ./scaffold.sh <template-id> <project-name> [options]

${BOLD}Arguments:${NC}
  template-id     Template to use (e.g., gtm-outbound)
  project-name    Name for the new project directory

${BOLD}Options:${NC}
  --config FILE   Read config vars from a JSON file instead of prompts
  --output DIR    Output base directory (default: ~/Desktop)
  --skip-supabase Skip Supabase table setup
  --skip-triggers Skip RemoteTrigger creation
  --help          Show this help message

${BOLD}Examples:${NC}
  ./scaffold.sh gtm-outbound acme-gtm
  ./scaffold.sh gtm-outbound acme-gtm --config acme-config.json
  ./scaffold.sh gtm-outbound acme-gtm --output /opt/projects

${BOLD}Available templates:${NC}
$(ls "$TEMPLATES_DIR"/*.json 2>/dev/null | xargs -I{} basename {} .json | sed 's/^/  - /' || echo "  (none found)")
EOF
  exit 0
}

# ──────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────
TEMPLATE_ID=""
PROJECT_NAME=""
CONFIG_FILE=""
SKIP_SUPABASE=0
SKIP_TRIGGERS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) show_help ;;
    --config)  CONFIG_FILE="$2"; shift 2 ;;
    --output)  OUTPUT_BASE="$2"; shift 2 ;;
    --skip-supabase) SKIP_SUPABASE=1; shift ;;
    --skip-triggers) SKIP_TRIGGERS=1; shift ;;
    -*)        err "Unknown option: $1"; echo "Run with --help for usage."; exit 1 ;;
    *)
      if [ -z "$TEMPLATE_ID" ]; then
        TEMPLATE_ID="$1"
      elif [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME="$1"
      else
        err "Unexpected argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$TEMPLATE_ID" ] || [ -z "$PROJECT_NAME" ]; then
  err "Missing required arguments: template-id and project-name"
  echo "Run with --help for usage."
  exit 1
fi

TEMPLATE_FILE="$TEMPLATES_DIR/${TEMPLATE_ID}.json"
PROJECT_DIR="$OUTPUT_BASE/$PROJECT_NAME"

if [ ! -f "$TEMPLATE_FILE" ]; then
  err "Template not found: $TEMPLATE_FILE"
  echo "Available templates:"
  ls "$TEMPLATES_DIR"/*.json 2>/dev/null | xargs -I{} basename {} .json | sed 's/^/  - /'
  exit 1
fi

# Check for jq
if ! command -v jq &>/dev/null; then
  err "jq is required but not installed. Install: brew install jq"
  exit 1
fi

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║     GTM Company Scaffold Engine v1.0.0       ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "Template:  $TEMPLATE_ID"
info "Project:   $PROJECT_NAME"
info "Output:    $PROJECT_DIR"

# ──────────────────────────────────────────────
# Step 1: Read template manifest
# ──────────────────────────────────────────────
step "Step 1: Reading template manifest"

TEMPLATE_NAME=$(jq -r '.name' "$TEMPLATE_FILE")
TEMPLATE_VERSION=$(jq -r '.version' "$TEMPLATE_FILE")
TEMPLATE_DESC=$(jq -r '.description' "$TEMPLATE_FILE")
AGENT_COUNT=$(jq '.agents | length' "$TEMPLATE_FILE")
CONFIG_VAR_COUNT=$(jq '.config_vars | length' "$TEMPLATE_FILE")

ok "Template: $TEMPLATE_NAME v$TEMPLATE_VERSION"
ok "Description: $TEMPLATE_DESC"
ok "Agents: $AGENT_COUNT | Config vars: $CONFIG_VAR_COUNT"

# ──────────────────────────────────────────────
# Step 2: Create project directory
# ──────────────────────────────────────────────
step "Step 2: Creating project directory"

if [ -d "$PROJECT_DIR" ]; then
  warn "Directory already exists: $PROJECT_DIR"
  read -p "  Overwrite? [y/N]: " CONFIRM
  if [[ "${CONFIRM:-n}" != [yY] ]]; then
    err "Aborted"
    exit 1
  fi
fi

mkdir -p "$PROJECT_DIR"/{agents,config,state,lib,dashboards,triggers}
ok "Created project structure at $PROJECT_DIR"

# ──────────────────────────────────────────────
# Step 3: Copy agent playbooks
# ──────────────────────────────────────────────
step "Step 3: Copying agent playbooks"

for i in $(seq 0 $((AGENT_COUNT - 1))); do
  AGENT_ID=$(jq -r ".agents[$i].id" "$TEMPLATE_FILE")
  PLAYBOOK_PATH=$(jq -r ".agents[$i].playbook" "$TEMPLATE_FILE")
  SOURCE_PLAYBOOK="$SCRIPT_DIR/$PLAYBOOK_PATH"

  if [ -f "$SOURCE_PLAYBOOK" ]; then
    cp "$SOURCE_PLAYBOOK" "$PROJECT_DIR/agents/"
    ok "Copied playbook: $PLAYBOOK_PATH"
  else
    warn "Playbook not found: $SOURCE_PLAYBOOK (creating placeholder)"
    cat > "$PROJECT_DIR/agents/$(basename "$PLAYBOOK_PATH")" <<PLAYBOOK
# Agent: $AGENT_ID
# Template: $TEMPLATE_ID
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Role
You are the $AGENT_ID agent for the {{company_name}} GTM operation.

## Objective
TODO: Define specific objectives for this agent.

## Tools Available
$(jq -r ".agents[$i].tools | join(\", \")" "$TEMPLATE_FILE")

## Instructions
1. Check state/\${agent_id}/last-run.json for previous context
2. Execute your primary workflow
3. Log results to Supabase
4. Update state files
PLAYBOOK
    ok "Created placeholder: agents/$(basename "$PLAYBOOK_PATH")"
  fi
done

# ──────────────────────────────────────────────
# Step 4: Collect config vars
# ──────────────────────────────────────────────
step "Step 4: Collecting configuration"

declare -A CONFIG_VALUES

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  info "Reading config from: $CONFIG_FILE"
  for i in $(seq 0 $((CONFIG_VAR_COUNT - 1))); do
    KEY=$(jq -r ".config_vars[$i].key" "$TEMPLATE_FILE")
    VALUE=$(jq -r ".[\"$KEY\"] // empty" "$CONFIG_FILE" 2>/dev/null)
    DEFAULT=$(jq -r ".config_vars[$i].default // empty" "$TEMPLATE_FILE")
    REQUIRED=$(jq -r ".config_vars[$i].required" "$TEMPLATE_FILE")

    if [ -n "$VALUE" ]; then
      CONFIG_VALUES[$KEY]="$VALUE"
      ok "$KEY = $VALUE"
    elif [ -n "$DEFAULT" ]; then
      CONFIG_VALUES[$KEY]="$DEFAULT"
      ok "$KEY = $DEFAULT (default)"
    elif [ "$REQUIRED" = "true" ]; then
      err "Missing required config var: $KEY"
      exit 1
    fi
  done
elif [ -n "$CONFIG_FILE" ]; then
  err "Config file not found: $CONFIG_FILE"
  exit 1
else
  info "Interactive config mode"
  echo ""
  for i in $(seq 0 $((CONFIG_VAR_COUNT - 1))); do
    KEY=$(jq -r ".config_vars[$i].key" "$TEMPLATE_FILE")
    DESC=$(jq -r ".config_vars[$i].description // empty" "$TEMPLATE_FILE")
    DEFAULT=$(jq -r ".config_vars[$i].default // empty" "$TEMPLATE_FILE")
    REQUIRED=$(jq -r ".config_vars[$i].required" "$TEMPLATE_FILE")
    TYPE=$(jq -r ".config_vars[$i].type // \"string\"" "$TEMPLATE_FILE")

    PROMPT="  $KEY"
    [ -n "$DESC" ] && PROMPT="$PROMPT ($DESC)"
    [ -n "$DEFAULT" ] && PROMPT="$PROMPT [default: $DEFAULT]"
    [ "$REQUIRED" = "true" ] && PROMPT="$PROMPT ${RED}*${NC}"

    echo -e "$PROMPT"

    if [ "$TYPE" = "array" ]; then
      echo "    (comma-separated values)"
    fi

    read -p "    > " VALUE

    if [ -z "$VALUE" ] && [ -n "$DEFAULT" ]; then
      VALUE="$DEFAULT"
    fi

    if [ -z "$VALUE" ] && [ "$REQUIRED" = "true" ]; then
      err "Required value missing: $KEY"
      exit 1
    fi

    if [ -n "$VALUE" ]; then
      if [ "$TYPE" = "array" ]; then
        # Convert comma-separated to JSON array
        ARRAY_JSON=$(echo "$VALUE" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)
        CONFIG_VALUES[$KEY]="$ARRAY_JSON"
      else
        CONFIG_VALUES[$KEY]="$VALUE"
      fi
    fi
  done
fi

# ──────────────────────────────────────────────
# Step 5: Generate project.json
# ──────────────────────────────────────────────
step "Step 5: Generating project.json"

PROJECT_JSON="$PROJECT_DIR/project.json"

# Build config object
CONFIG_JSON="{}"
for KEY in "${!CONFIG_VALUES[@]}"; do
  VALUE="${CONFIG_VALUES[$KEY]}"
  # Check if value is valid JSON (array/object)
  if echo "$VALUE" | jq . &>/dev/null 2>&1; then
    CONFIG_JSON=$(echo "$CONFIG_JSON" | jq --argjson v "$VALUE" ". + {\"$KEY\": \$v}")
  else
    CONFIG_JSON=$(echo "$CONFIG_JSON" | jq --arg v "$VALUE" ". + {\"$KEY\": \$v}")
  fi
done

# Build agents array
AGENTS_JSON=$(jq '.agents' "$TEMPLATE_FILE")

# Build schedules
SCHEDULES_JSON="[]"
for i in $(seq 0 $((AGENT_COUNT - 1))); do
  AGENT_ID=$(jq -r ".agents[$i].id" "$TEMPLATE_FILE")
  SCHEDULE=$(jq -r ".agents[$i].schedule" "$TEMPLATE_FILE")
  AUTO_MODE=$(jq -r ".agents[$i].auto_mode" "$TEMPLATE_FILE")
  SCHEDULES_JSON=$(echo "$SCHEDULES_JSON" | jq \
    --arg id "$AGENT_ID" \
    --arg sched "$SCHEDULE" \
    --argjson auto "$AUTO_MODE" \
    '. + [{"agent_id": $id, "cron": $sched, "auto_mode": $auto, "enabled": true}]')
done

# Assemble full project.json
jq -n \
  --arg pid "$PROJECT_NAME" \
  --arg tid "$TEMPLATE_ID" \
  --arg tname "$TEMPLATE_NAME" \
  --arg tver "$TEMPLATE_VERSION" \
  --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --argjson config "$CONFIG_JSON" \
  --argjson agents "$AGENTS_JSON" \
  --argjson schedules "$SCHEDULES_JSON" \
  '{
    project_id: $pid,
    template_id: $tid,
    template_name: $tname,
    template_version: $tver,
    created_at: $created,
    config: $config,
    agents: $agents,
    schedules: $schedules
  }' > "$PROJECT_JSON"

ok "Generated project.json"

# Write schedules.json in the format autopilot.sh expects:
# { "agents": { "<id>": { "cron": "...", "description": "...", "priority": "...", "auto_mode": true/false } } }
AUTOPILOT_SCHEDULES="{}"
for i in $(seq 0 $((AGENT_COUNT - 1))); do
  AID=$(jq -r ".agents[$i].id" "$TEMPLATE_FILE")
  ASCHED=$(jq -r ".agents[$i].schedule" "$TEMPLATE_FILE")
  ADESC=$(jq -r ".agents[$i].description // empty" "$TEMPLATE_FILE")
  APRI=$(jq -r ".agents[$i].priority // \"medium\"" "$TEMPLATE_FILE")
  AAUTO=$(jq -r ".agents[$i].auto_mode" "$TEMPLATE_FILE")
  AFOLLOWUP=$(jq -r ".agents[$i].cron_followup // empty" "$TEMPLATE_FILE")

  AGENT_OBJ=$(jq -n \
    --arg cron "$ASCHED" \
    --arg desc "$ADESC" \
    --arg pri "$APRI" \
    --argjson auto "$AAUTO" \
    '{cron: $cron, description: $desc, priority: $pri, auto_mode: $auto}')

  if [[ -n "$AFOLLOWUP" ]]; then
    AGENT_OBJ=$(echo "$AGENT_OBJ" | jq --arg cf "$AFOLLOWUP" '. + {cron_followup: $cf}')
  fi

  AUTOPILOT_SCHEDULES=$(echo "$AUTOPILOT_SCHEDULES" | jq --arg id "$AID" --argjson obj "$AGENT_OBJ" '.[$id] = $obj')
done

jq -n --argjson agents "$AUTOPILOT_SCHEDULES" '{agents: $agents}' > "$PROJECT_DIR/config/schedules.json"
ok "Generated config/schedules.json (autopilot.sh format)"

# ──────────────────────────────────────────────
# Step 6: Initialize state directories
# ──────────────────────────────────────────────
step "Step 6: Initializing state directories"

STATE_DIRS=$(jq -r '.state_init.directories[]' "$TEMPLATE_FILE")
DEFAULT_FILES=$(jq -r '.state_init.default_files | keys[]' "$TEMPLATE_FILE")

for DIR in $STATE_DIRS; do
  mkdir -p "$PROJECT_DIR/state/$DIR"
  for FILE in $DEFAULT_FILES; do
    CONTENT=$(jq ".state_init.default_files[\"$FILE\"]" "$TEMPLATE_FILE")
    echo "$CONTENT" > "$PROJECT_DIR/state/$DIR/$FILE"
  done
  ok "Initialized state/$DIR/"
done

# ──────────────────────────────────────────────
# Step 7: Create .env from .env.example
# ──────────────────────────────────────────────
step "Step 7: Creating environment file"

cat > "$PROJECT_DIR/.env.example" <<'ENVEXAMPLE'
# GTM Company Project Environment
# Copy to .env and fill in your values

# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-role-key

# Project
PROJECT_ID=your-project-id

# OpenRouter (for agent LLM calls)
OPENROUTER_API_KEY=your-openrouter-key

# Slack
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/xxx/yyy/zzz
SLACK_CHANNEL=#gtm-ops

# Email
GMAIL_SENDER=your-email@gmail.com

# LinkedIn (browser automation)
LINKEDIN_EMAIL=your-email@example.com

# Booking
BOOKING_LINK=https://cal.com/your-link
ENVEXAMPLE

if [ ! -f "$PROJECT_DIR/.env" ]; then
  cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
  # Substitute known values
  if [ -n "${CONFIG_VALUES[booking_link]:-}" ]; then
    sed -i.bak "s|BOOKING_LINK=.*|BOOKING_LINK=${CONFIG_VALUES[booking_link]}|" "$PROJECT_DIR/.env" && rm -f "$PROJECT_DIR/.env.bak"
  fi
  if [ -n "${CONFIG_VALUES[slack_channel]:-}" ]; then
    sed -i.bak "s|SLACK_CHANNEL=.*|SLACK_CHANNEL=${CONFIG_VALUES[slack_channel]}|" "$PROJECT_DIR/.env" && rm -f "$PROJECT_DIR/.env.bak"
  fi
  sed -i.bak "s|PROJECT_ID=.*|PROJECT_ID=$PROJECT_NAME|" "$PROJECT_DIR/.env" && rm -f "$PROJECT_DIR/.env.bak"
  ok "Created .env (edit with your credentials)"
else
  ok ".env already exists, skipping"
fi

# ──────────────────────────────────────────────
# Step 8: Copy lib files
# ──────────────────────────────────────────────
step "Step 8: Copying library files"

for LIB_FILE in memory.sh sync-state.sh run-agent.sh setup-supabase.sh agent-comms.sh paperclip.sh autopilot.sh supabase-migration.sql supabase-migration-v2.sql; do
  if [ -f "$LIB_DIR/$LIB_FILE" ]; then
    cp "$LIB_DIR/$LIB_FILE" "$PROJECT_DIR/lib/"
    ok "Copied lib/$LIB_FILE"
  else
    warn "lib/$LIB_FILE not found in source (skipping)"
  fi
done

# Generate .claude/CLAUDE.md for the scaffolded project
step "Step 8b: Generating .claude/CLAUDE.md"

mkdir -p "$PROJECT_DIR/.claude"
cat > "$PROJECT_DIR/.claude/CLAUDE.md" <<CLAUDEMD
# ${PROJECT_NAME} — Claude Code Instructions

## Identity
This is an autonomous GTM operations hub scaffolded from the ${TEMPLATE_ID} template.
Claude Code is the operations runtime — it executes agent playbooks via MCP integrations.

## Architecture Rules
- NEVER delete state files — they are the memory between sessions
- NEVER auto-send emails — all outbound is Gmail DRAFTS (human approval required)
- NEVER modify production workflows without explicit approval
- ALWAYS read the playbook before executing any agent run
- ALWAYS write state files at the end of every run
- ALWAYS report to Slack after every run

## Agent Execution Pattern
Every agent run follows this exact sequence:
1. Read playbook: agents/{agent_id}.md
2. Read state: state/{agent_id}/last-run.json
3. Read config: config/schedules.json
4. Check external systems (ClickUp, Gmail, Slack)
5. Execute ops per playbook checklist
6. Write state files
7. Post summary to Slack
8. Exit

## Available Agents
$(for i in $(seq 0 $((AGENT_COUNT - 1))); do
  AID=$(jq -r ".agents[$i].id" "$TEMPLATE_FILE")
  ADESC=$(jq -r ".agents[$i].description // empty" "$TEMPLATE_FILE")
  echo "- ${AID}: ${ADESC}"
done)

## Key Files
- project.json — Project configuration and agent registry
- config/schedules.json — All agent cron schedules
- .env — Environment variables (secrets, API keys)
- lib/run-agent.sh — Agent execution wrapper
- lib/memory.sh — Supabase memory layer
- lib/agent-comms.sh — Inter-agent communication
- lib/autopilot.sh — Auto-scheduling daemon

## Constraints
- All emails are DRAFTS (human approval required)
- State stored as JSON files on disk
- Claude Code sessions are ephemeral — state files bridge sessions
CLAUDEMD
ok "Generated .claude/CLAUDE.md"

# Copy dashboards
if [ -d "$SCRIPT_DIR/dashboards" ]; then
  cp "$SCRIPT_DIR/dashboards/"*.sql "$PROJECT_DIR/dashboards/" 2>/dev/null && \
    ok "Copied dashboard queries" || warn "No dashboard files to copy"
fi

# Copy triggers setup
if [ -f "$SCRIPT_DIR/triggers/setup-triggers.sh" ]; then
  cp "$SCRIPT_DIR/triggers/setup-triggers.sh" "$PROJECT_DIR/triggers/"
  chmod +x "$PROJECT_DIR/triggers/setup-triggers.sh"
  ok "Copied triggers/setup-triggers.sh"
fi

# Make scripts executable
chmod +x "$PROJECT_DIR/lib/"*.sh 2>/dev/null || true
chmod +x "$PROJECT_DIR/triggers/"*.sh 2>/dev/null || true

# ──────────────────────────────────────────────
# Step 9: Set up Supabase tables
# ──────────────────────────────────────────────
if [ "$SKIP_SUPABASE" -eq 0 ]; then
  step "Step 9: Supabase setup"
  if [ -f "$PROJECT_DIR/lib/setup-supabase.sh" ]; then
    echo ""
    read -p "  Run Supabase setup now? [Y/n]: " RUN_SETUP
    if [[ "${RUN_SETUP:-y}" == [yY] ]]; then
      cd "$PROJECT_DIR"
      bash "$PROJECT_DIR/lib/setup-supabase.sh" || warn "Supabase setup had issues (can retry later)"
      cd "$SCRIPT_DIR"
    else
      info "Skipping. Run later: bash $PROJECT_DIR/lib/setup-supabase.sh"
    fi
  else
    warn "setup-supabase.sh not found in project lib/"
  fi
else
  info "Skipping Supabase setup (--skip-supabase)"
fi

# ──────────────────────────────────────────────
# Step 10: Create triggers (optional)
# ──────────────────────────────────────────────
if [ "$SKIP_TRIGGERS" -eq 0 ]; then
  step "Step 10: Agent triggers"
  echo ""
  echo "  Trigger options:"
  echo "    1) Set up RemoteTriggers (persistent, survives sessions)"
  echo "    2) Set up later manually"
  echo ""
  read -p "  Choice [1/2]: " TRIGGER_CHOICE

  case "${TRIGGER_CHOICE:-2}" in
    1)
      if [ -f "$PROJECT_DIR/triggers/setup-triggers.sh" ]; then
        bash "$PROJECT_DIR/triggers/setup-triggers.sh" "$PROJECT_DIR" || warn "Trigger setup had issues"
      else
        warn "setup-triggers.sh not found"
      fi
      ;;
    *)
      info "Skipping. Run later: bash $PROJECT_DIR/triggers/setup-triggers.sh $PROJECT_DIR"
      ;;
  esac
else
  info "Skipping trigger setup (--skip-triggers)"
fi

# ──────────────────────────────────────────────
# Step 11: Verification
# ──────────────────────────────────────────────
step "Step 11: Verification"

ERRORS=0

# Check critical files
for CHECK_FILE in project.json .env .env.example config/schedules.json; do
  if [ -f "$PROJECT_DIR/$CHECK_FILE" ]; then
    ok "$CHECK_FILE"
  else
    err "Missing: $CHECK_FILE"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check agent playbooks
for i in $(seq 0 $((AGENT_COUNT - 1))); do
  PLAYBOOK=$(jq -r ".agents[$i].playbook" "$TEMPLATE_FILE")
  FILENAME=$(basename "$PLAYBOOK")
  if [ -f "$PROJECT_DIR/agents/$FILENAME" ]; then
    ok "agents/$FILENAME"
  else
    err "Missing playbook: agents/$FILENAME"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check state dirs
for DIR in $STATE_DIRS; do
  if [ -d "$PROJECT_DIR/state/$DIR" ]; then
    ok "state/$DIR/"
  else
    err "Missing state dir: state/$DIR/"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check lib files
for LIB_FILE in setup-supabase.sh supabase-migration.sql; do
  if [ -f "$PROJECT_DIR/lib/$LIB_FILE" ]; then
    ok "lib/$LIB_FILE"
  else
    warn "Missing lib/$LIB_FILE (non-critical)"
  fi
done

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║       Scaffold complete!                      ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
else
  echo -e "${YELLOW}${BOLD}Scaffold complete with $ERRORS warnings${NC}"
fi

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo ""
echo "  1. Edit credentials:"
echo "     ${CYAN}nano $PROJECT_DIR/.env${NC}"
echo ""
echo "  2. Run Supabase migration (if not done):"
echo "     ${CYAN}bash $PROJECT_DIR/lib/setup-supabase.sh${NC}"
echo ""
echo "  3. Customize agent playbooks:"
echo "     ${CYAN}ls $PROJECT_DIR/agents/${NC}"
echo ""
echo "  4. Set up triggers:"
echo "     ${CYAN}bash $PROJECT_DIR/triggers/setup-triggers.sh $PROJECT_DIR${NC}"
echo ""
echo "  5. Run first agent manually:"
echo "     ${CYAN}bash $PROJECT_DIR/lib/run-agent.sh cold-outreach${NC}"
echo ""
echo -e "${BLUE}Project directory: ${BOLD}$PROJECT_DIR${NC}"
echo ""
