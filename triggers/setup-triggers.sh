#!/usr/bin/env bash
# setup-triggers.sh — Creates RemoteTriggers or cron jobs for all agents
# Usage: ./setup-triggers.sh [project-dir]
set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCHEDULES_FILE="$PROJECT_DIR/config/schedules.json"
PROJECT_JSON="$PROJECT_DIR/project.json"
RUN_AGENT="$PROJECT_DIR/lib/run-agent.sh"

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

# ──────────────────────────────────────────────
# Validate inputs
# ──────────────────────────────────────────────
if [ ! -f "$SCHEDULES_FILE" ]; then
  err "Schedules file not found: $SCHEDULES_FILE"
  err "Run scaffold.sh first to generate config/schedules.json"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  err "jq is required but not installed. Install: brew install jq"
  exit 1
fi

PROJECT_ID=$(jq -r '.project_id // "unknown"' "$PROJECT_JSON" 2>/dev/null || echo "unknown")
AGENT_COUNT=$(jq 'length' "$SCHEDULES_FILE")

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║     GTM Trigger Setup                        ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "Project: $PROJECT_ID"
info "Agents:  $AGENT_COUNT"
info "Config:  $SCHEDULES_FILE"

# ──────────────────────────────────────────────
# Choose mode
# ──────────────────────────────────────────────
step "Select trigger mode"
echo ""
echo "  1) RemoteTrigger (persistent, survives Claude Code sessions)"
echo "     Creates .claude/scheduled_tasks.json entries"
echo ""
echo "  2) Crontab (system cron, runs independently)"
echo "     Adds entries to your system crontab"
echo ""
echo "  3) Print commands only (manual setup)"
echo "     Outputs commands you can run yourself"
echo ""
read -p "  Choice [1/2/3]: " MODE

# ──────────────────────────────────────────────
# Track results
# ──────────────────────────────────────────────
CREATED=0
SKIPPED=0
FAILED=0

# ──────────────────────────────────────────────
# Process each agent
# ──────────────────────────────────────────────
step "Setting up triggers for $AGENT_COUNT agents"

for i in $(seq 0 $((AGENT_COUNT - 1))); do
  AGENT_ID=$(jq -r ".[$i].agent_id" "$SCHEDULES_FILE")
  CRON=$(jq -r ".[$i].cron" "$SCHEDULES_FILE")
  AUTO_MODE=$(jq -r ".[$i].auto_mode" "$SCHEDULES_FILE")
  ENABLED=$(jq -r ".[$i].enabled" "$SCHEDULES_FILE")

  if [ "$ENABLED" != "true" ]; then
    warn "Skipping $AGENT_ID (disabled)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  TASK_ID="${PROJECT_ID}-${AGENT_ID}"
  PROMPT="Run the $AGENT_ID agent for project $PROJECT_ID. Execute: bash $RUN_AGENT $AGENT_ID"

  if [ "$AUTO_MODE" = "false" ]; then
    PROMPT="$PROMPT -- This agent requires human review. Present outputs for approval before taking action."
  fi

  echo ""
  info "Agent: $AGENT_ID"
  info "  Schedule: $CRON"
  info "  Auto mode: $AUTO_MODE"

  case "${MODE:-3}" in
    1)
      # RemoteTrigger via Claude Code scheduled tasks
      TASKS_DIR="$HOME/.claude/scheduled-tasks"
      TASK_DIR="$TASKS_DIR/$TASK_ID"
      mkdir -p "$TASK_DIR"

      cat > "$TASK_DIR/SKILL.md" <<SKILL
---
description: "GTM agent: $AGENT_ID for $PROJECT_ID"
schedule: "$CRON"
enabled: true
---

# $AGENT_ID Agent Trigger

$PROMPT

## Context
- Project: $PROJECT_ID
- Agent: $AGENT_ID
- Schedule: $CRON
- Auto mode: $AUTO_MODE
- Project dir: $PROJECT_DIR

## Execution
1. Source environment: \`source $PROJECT_DIR/.env\`
2. Run agent: \`bash $RUN_AGENT $AGENT_ID\`
3. Check exit code and report status
SKILL

      ok "Created RemoteTrigger: $TASK_ID"
      ok "  File: $TASK_DIR/SKILL.md"
      CREATED=$((CREATED + 1))
      ;;

    2)
      # System crontab
      CRON_CMD="$CRON cd $PROJECT_DIR && bash $RUN_AGENT $AGENT_ID >> $PROJECT_DIR/state/$AGENT_ID/cron.log 2>&1"

      # Check if already in crontab
      if crontab -l 2>/dev/null | grep -q "$TASK_ID"; then
        warn "Cron entry already exists for $TASK_ID (skipping)"
        SKIPPED=$((SKIPPED + 1))
      else
        # Add to crontab
        (crontab -l 2>/dev/null || true; echo "# $TASK_ID"; echo "$CRON_CMD") | crontab -
        if [ $? -eq 0 ]; then
          ok "Added crontab entry: $TASK_ID"
          CREATED=$((CREATED + 1))
        else
          err "Failed to add crontab entry for $TASK_ID"
          FAILED=$((FAILED + 1))
        fi
      fi
      ;;

    3)
      # Print only
      echo ""
      echo -e "  ${BOLD}# $AGENT_ID${NC}"
      echo "  # RemoteTrigger command:"
      echo "  # Task ID: $TASK_ID"
      echo "  # Cron: $CRON"
      echo "  # Prompt: $PROMPT"
      echo ""
      echo "  # Crontab entry:"
      echo "  $CRON cd $PROJECT_DIR && bash $RUN_AGENT $AGENT_ID >> $PROJECT_DIR/state/$AGENT_ID/cron.log 2>&1"
      echo ""
      CREATED=$((CREATED + 1))
      ;;
  esac
done

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
step "Trigger Setup Summary"
echo ""
echo -e "  Created:  ${GREEN}$CREATED${NC}"
echo -e "  Skipped:  ${YELLOW}$SKIPPED${NC}"
echo -e "  Failed:   ${RED}$FAILED${NC}"
echo ""

case "${MODE:-3}" in
  1)
    echo -e "${BOLD}RemoteTriggers created at:${NC}"
    echo "  $HOME/.claude/scheduled-tasks/"
    echo ""
    echo "  These will run automatically in Claude Code sessions."
    echo "  To manage: use /schedule list in Claude Code"
    ;;
  2)
    echo -e "${BOLD}Current crontab:${NC}"
    crontab -l 2>/dev/null | grep -A1 "$PROJECT_ID" || echo "  (no entries found)"
    echo ""
    echo "  To edit: crontab -e"
    echo "  To list: crontab -l"
    echo "  To remove all: crontab -r (careful!)"
    ;;
  3)
    echo "  Copy the commands above to set up triggers manually."
    ;;
esac

echo ""
echo -e "${BOLD}Trigger schedule overview:${NC}"
echo ""
printf "  ${BOLD}%-20s %-20s %-10s %-8s${NC}\n" "AGENT" "SCHEDULE" "AUTO" "STATUS"
printf "  %-20s %-20s %-10s %-8s\n" "--------------------" "--------------------" "----------" "--------"

for i in $(seq 0 $((AGENT_COUNT - 1))); do
  AGENT_ID=$(jq -r ".[$i].agent_id" "$SCHEDULES_FILE")
  CRON=$(jq -r ".[$i].cron" "$SCHEDULES_FILE")
  AUTO_MODE=$(jq -r ".[$i].auto_mode" "$SCHEDULES_FILE")
  ENABLED=$(jq -r ".[$i].enabled" "$SCHEDULES_FILE")

  STATUS="active"
  [ "$ENABLED" != "true" ] && STATUS="disabled"

  printf "  %-20s %-20s %-10s %-8s\n" "$AGENT_ID" "$CRON" "$AUTO_MODE" "$STATUS"
done

echo ""
