#!/usr/bin/env bash
# chmod +x lib/run-agent.sh
# GTM Company — Main Agent Runner
#
# Usage: ./lib/run-agent.sh <agent-name> [--auto]
#
# What it does:
#   1. Sources memory.sh
#   2. Verifies agent playbook exists
#   3. Loads memory context from Supabase
#   4. Loads local state
#   5. Builds prompt (playbook + config + state + memory)
#   6. Runs Claude
#   7. Syncs state to Supabase
#   8. Posts completion notification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Parse arguments ───────────────────────────────────────────────────────

AGENT_NAME="${1:?Usage: run-agent.sh <agent-name> [--auto]}"
AUTO_FLAG=""
if [[ "${2:-}" == "--auto" ]]; then
  AUTO_FLAG="--allowedTools '*'"
fi

echo "========================================"
echo " GTM Agent Runner: ${AGENT_NAME}"
echo " $(date)"
echo "========================================"

# ─── 1. Source memory layer and comms layer ───────────────────────────────

source "$SCRIPT_DIR/memory.sh"
source "$SCRIPT_DIR/sync-state.sh"
source "$SCRIPT_DIR/agent-comms.sh"

# Load env if .env exists
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

PROJECT_ID="${PROJECT_ID:-$(jq -r '.project_id' "$PROJECT_ROOT/config/project.json" 2>/dev/null || echo "ai-integrators-gtm")}"

# ─── 2. Verify playbook exists ─────────────────────────────────────────────

PLAYBOOK="$PROJECT_ROOT/agents/${AGENT_NAME}.md"
if [[ ! -f "$PLAYBOOK" ]]; then
  echo "[run-agent] FATAL: Playbook not found at ${PLAYBOOK}" >&2
  exit 1
fi
echo "[run-agent] Playbook: ${PLAYBOOK}"

# ─── 3. Load memory context from Supabase ──────────────────────────────────

MEMORY_CONTEXT=""

# Try to load recent runs (non-fatal if Supabase not configured yet)
if mem_init 2>/dev/null; then
  echo "[run-agent] Loading memory context..."

  RECENT_RUNS=$(get_recent_runs "$PROJECT_ID" "$AGENT_NAME" 3 2>/dev/null || echo "[]")
  RECENT_EPISODES=$(get_recent_episodes "$PROJECT_ID" 5 2>/dev/null || echo "[]")
  STRATEGY=$(mem_get "$PROJECT_ID" "strategy" "current" 2>/dev/null || echo "[]")
  AGENT_MEMORIES=$(mem_search "$PROJECT_ID" "$AGENT_NAME" "" 2>/dev/null || echo "[]")

  MEMORY_CONTEXT=$(cat <<MEMEOF

## Memory Context (from Supabase)

### Recent Runs for ${AGENT_NAME}
\`\`\`json
${RECENT_RUNS}
\`\`\`

### Recent Episodes (all agents)
\`\`\`json
${RECENT_EPISODES}
\`\`\`

### Current Strategy
\`\`\`json
${STRATEGY}
\`\`\`

### Agent-Specific Memories
\`\`\`json
${AGENT_MEMORIES}
\`\`\`
MEMEOF
)
  echo "[run-agent] Memory context loaded."
else
  echo "[run-agent] WARNING: Supabase not available, running without memory context."
fi

# ─── 4. Load local state ──────────────────────────────────────────────────

STATE_DIR="$PROJECT_ROOT/state/${AGENT_NAME}"
mkdir -p "$STATE_DIR"

LAST_RUN_FILE="$STATE_DIR/last-run.json"
if [[ -f "$LAST_RUN_FILE" ]]; then
  LAST_RUN=$(cat "$LAST_RUN_FILE")
else
  LAST_RUN='{"status": "never_run", "run_count": 0, "last_run_at": null}'
fi

STRATEGY_FILE="$STATE_DIR/strategy.json"
LOCAL_STRATEGY=""
if [[ -f "$STRATEGY_FILE" ]]; then
  LOCAL_STRATEGY=$(cat "$STRATEGY_FILE")
fi

echo "[run-agent] Local state loaded."

# ─── 5. Load project config ───────────────────────────────────────────────

PROJECT_CONFIG=$(cat "$PROJECT_ROOT/config/project.json" 2>/dev/null || echo '{}')
THRESHOLDS=$(cat "$PROJECT_ROOT/config/thresholds.json" 2>/dev/null || echo '{}')

# ─── 6. Build prompt ──────────────────────────────────────────────────────

PLAYBOOK_CONTENT=$(cat "$PLAYBOOK")

PROMPT=$(cat <<PROMPTEOF
# Agent Run: ${AGENT_NAME}
**Timestamp:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Project:** ${PROJECT_ID}

## Your Playbook
${PLAYBOOK_CONTENT}

## Project Configuration
\`\`\`json
${PROJECT_CONFIG}
\`\`\`

## Operational Thresholds
\`\`\`json
${THRESHOLDS}
\`\`\`

## Your Last Run State
\`\`\`json
${LAST_RUN}
\`\`\`

$(if [[ -n "$LOCAL_STRATEGY" ]]; then echo "## Local Strategy
\`\`\`json
${LOCAL_STRATEGY}
\`\`\`"; fi)

${MEMORY_CONTEXT}

## Run Checklist
1. Read your playbook above carefully
2. Check your last run state — pick up where you left off
3. Respect all thresholds (max emails, max tokens, etc.)
4. Do your work using available MCP tools
5. When done, update your state file at: state/${AGENT_NAME}/last-run.json
   - Set status to "completed" or "partial"
   - Increment run_count
   - Set last_run_at to current UTC timestamp
   - List next_actions for your next run
   - Include any new contacts in state/${AGENT_NAME}/new-contacts.json
6. Post a summary to ${SLACK_CHANNEL:-#gtm-ops}

## Safety Rails
- NEVER auto-send emails — always create drafts
- NEVER exceed daily limits in thresholds
- If something looks wrong, STOP and post to Slack
- Log everything for Expert Series documentation
PROMPTEOF
)

echo "[run-agent] Prompt built ($(echo "$PROMPT" | wc -c | tr -d ' ') chars)."

# ─── 6b. Check for inbound instructions from orchestrator ────────────────

INBOUND_INSTRUCTIONS=""
if [[ -n "${PROJECT_ID:-}" ]]; then
  echo "[run-agent] Checking for inbound instructions..."
  INBOUND_RAW=$(get_inbound_instructions "$AGENT_NAME" 2>/dev/null || echo "[]")
  INBOUND_COUNT=$(echo "$INBOUND_RAW" | jq 'length' 2>/dev/null || echo "0")
  if [[ "$INBOUND_COUNT" -gt 0 ]]; then
    echo "[run-agent] Found ${INBOUND_COUNT} inbound instruction(s) from orchestrator."
    INBOUND_INSTRUCTIONS=$(cat <<INSTREOF

## Inbound Instructions from Orchestrator
The orchestrator has sent you the following instruction(s). Process them as part of this run.

\`\`\`json
${INBOUND_RAW}
\`\`\`

After processing, acknowledge each instruction by noting it in your run state.
INSTREOF
)
    # Mark instructions as read
    echo "$INBOUND_RAW" | jq -r '.[].id // empty' 2>/dev/null | while IFS= read -r msg_id; do
      if [[ -n "$msg_id" ]]; then
        mark_processed "$msg_id" "$AGENT_NAME" 2>/dev/null || true
      fi
    done
  else
    echo "[run-agent] No inbound instructions."
  fi
fi

# Append inbound instructions to prompt
PROMPT="${PROMPT}${INBOUND_INSTRUCTIONS}"

# ─── 7. Run Claude ─────────────────────────────────────────────────────────

echo "[run-agent] Starting Claude for ${AGENT_NAME}..."
echo "────────────────────────────────────────"

eval "echo \"\$PROMPT\" | claude ${AUTO_FLAG} --print -p -"

CLAUDE_EXIT=$?
echo "────────────────────────────────────────"

if [[ $CLAUDE_EXIT -ne 0 ]]; then
  echo "[run-agent] WARNING: Claude exited with code ${CLAUDE_EXIT}"
fi

# ─── 8. Process outbound messages and sync state ──────────────────────────

echo "[run-agent] Processing outbound messages..."
flush_outbound_queue "$AGENT_NAME" 2>/dev/null || {
  echo "[run-agent] WARNING: Outbound message flush failed"
}

# Send automatic task_complete to orchestrator
if [[ -n "${PROJECT_ID:-}" ]]; then
  RUN_STATUS="completed"
  if [[ $CLAUDE_EXIT -ne 0 ]]; then
    RUN_STATUS="failed"
  fi
  COMPLETE_PAYLOAD="{\"agent\":\"${AGENT_NAME}\",\"status\":\"${RUN_STATUS}\",\"exit_code\":${CLAUDE_EXIT},\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
  send_message "$AGENT_NAME" "orchestrator" "task_complete" "$COMPLETE_PAYLOAD" 2>/dev/null || {
    echo "[run-agent] WARNING: Failed to send task_complete to orchestrator"
  }
fi

echo "[run-agent] Syncing state to Supabase..."
sync_all "$AGENT_NAME" 2>/dev/null || {
  echo "[run-agent] WARNING: State sync failed (Supabase may not be configured)"
}

# ─── 9. Completion ─────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo " ${AGENT_NAME} run complete"
echo " $(date)"
echo "========================================"
