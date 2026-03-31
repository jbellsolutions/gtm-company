#!/usr/bin/env bash
# smoke-test.sh — agent-core smoke tests
# Validates the framework structure, configs, and identity files
# before any agent is deployed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

echo "========================================"
echo " agent-core Smoke Tests"
echo " $(date)"
echo "========================================"

echo ""
echo "--- Required Files ---"
for f in README.md requirements.txt main.py .env.example; do
  [[ -f "$REPO_ROOT/$f" ]] && pass "$f exists" || fail "$f MISSING"
done

echo ""
echo "--- Agent Core Modules ---"
for f in agent/__init__.py agent/agent.py agent/identity.py agent/memory.py agent/tools.py agent/slack_listener.py; do
  [[ -f "$REPO_ROOT/$f" ]] && pass "$f" || fail "$f MISSING"
done

echo ""
echo "--- Tool Modules ---"
for f in tools/__init__.py tools/base_tools.py tools/slack_tools.py tools/supabase_tools.py tools/pipeline_tools.py tools/domain_tools_template.py; do
  [[ -f "$REPO_ROOT/$f" ]] && pass "$f" || fail "$f MISSING"
done

echo ""
echo "--- Identity Files ---"
for f in identities/head-of-operations.json identities/coo-template.json identities/gtm-agent-template.json; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    # Validate JSON
    if command -v python3 &>/dev/null; then
      if python3 -c "import json; json.load(open('$REPO_ROOT/$f'))" 2>/dev/null; then
        pass "$f valid JSON"
      else
        fail "$f invalid JSON"
      fi
    else
      pass "$f exists (python3 not available for JSON validation)"
    fi
  else
    fail "$f MISSING"
  fi
done

echo ""
echo "--- Identity Required Fields ---"
if command -v python3 &>/dev/null; then
  REQUIRED_FIELDS=("name" "title" "company" "system_prompt" "heartbeat_interval_minutes" "ops_channel")
  for identity_file in "$REPO_ROOT/identities/"*.json; do
    [[ "$(basename $identity_file)" == *"template"* ]] && continue  # skip templates
    fname="$(basename $identity_file)"
    for field in "${REQUIRED_FIELDS[@]}"; do
      if python3 -c "import json; d=json.load(open('$identity_file')); assert '$field' in d, '$field missing'" 2>/dev/null; then
        pass "$fname has '$field'"
      else
        fail "$fname MISSING required field '$field'"
      fi
    done
  done
else
  pass "python3 not available — skipping field validation"
fi

echo ""
echo "--- Config Files ---"
for f in config/tools.json; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    if command -v python3 &>/dev/null; then
      python3 -c "import json; json.load(open('$REPO_ROOT/$f'))" 2>/dev/null \
        && pass "$f valid JSON" || fail "$f invalid JSON"
    else
      pass "$f exists"
    fi
  else
    fail "$f MISSING"
  fi
done

echo ""
echo "--- Tools Config Has Required Tools ---"
if command -v python3 &>/dev/null && [[ -f "$REPO_ROOT/config/tools.json" ]]; then
  REQUIRED_TOOLS=("get_pipeline_status" "get_client_info" "create_client" "run_agent" "post_slack_message" "create_slack_channel")
  TOOL_NAMES=$(python3 -c "import json; tools=json.load(open('$REPO_ROOT/config/tools.json')); print(' '.join(t['name'] for t in tools.get('tools', [])))")
  for tool in "${REQUIRED_TOOLS[@]}"; do
    echo "$TOOL_NAMES" | grep -q "$tool" \
      && pass "tools.json defines '$tool'" || fail "tools.json MISSING '$tool'"
  done
else
  pass "Skipping tools config validation (python3 not available)"
fi

echo ""
echo "--- Deployment Files ---"
for f in deployment/Dockerfile deployment/supabase-schema.sql deployment/digitalocean-app.yaml; do
  [[ -f "$REPO_ROOT/$f" ]] && pass "$f" || fail "$f MISSING"
done

echo ""
echo "--- Python Syntax Check ---"
if command -v python3 &>/dev/null; then
  SYNTAX_ERRORS=0
  for pyfile in "$REPO_ROOT/agent/"*.py "$REPO_ROOT/tools/"*.py "$REPO_ROOT/main.py"; do
    [[ "$(basename $pyfile)" == *"template"* ]] && continue
    if python3 -m py_compile "$pyfile" 2>/dev/null; then
      pass "$(basename $pyfile) syntax OK"
    else
      fail "$(basename $pyfile) SYNTAX ERROR"
      SYNTAX_ERRORS=$((SYNTAX_ERRORS+1))
    fi
  done
else
  pass "python3 not available — skipping syntax check"
fi

echo ""
echo "--- .env.example Completeness ---"
REQUIRED_VARS=("ANTHROPIC_API_KEY" "SLACK_BOT_TOKEN" "SLACK_APP_TOKEN" "SUPABASE_URL" "SUPABASE_SERVICE_ROLE_KEY" "JUSTIN_SLACK_USER_ID")
for var in "${REQUIRED_VARS[@]}"; do
  grep -q "^${var}=" "$REPO_ROOT/.env.example" \
    && pass ".env.example has $var" || fail ".env.example MISSING $var"
done

echo ""
echo "--- No Hardcoded Secrets Check ---"
# Check that no actual secrets are committed
# Grep for actual secrets — exclude comment lines (starting with #), docstrings (\"\"\" lines),
# string literals in examples ("xoxb-..." or 'xapp-...' patterns), and .env.example
SECRET_FOUND=0
# sk-ant-api is only a real secret if it appears as a full token (not in a comment or example)
if grep -rn "sk-ant-api[0-9]" "$REPO_ROOT/agent/" "$REPO_ROOT/tools/" "$REPO_ROOT/main.py" 2>/dev/null \
  | grep -v "^\s*#" | grep -v "\.env\.example" | grep -q "sk-ant-api"; then
  fail "Possible hardcoded Anthropic API key found"
  SECRET_FOUND=$((SECRET_FOUND+1))
fi
# xoxb/xapp tokens — only flag if followed by actual token chars (not just the prefix in a comment)
if grep -rn "xoxb-[A-Za-z0-9]" "$REPO_ROOT/agent/" "$REPO_ROOT/tools/" "$REPO_ROOT/main.py" 2>/dev/null \
  | grep -v "^\s*#" | grep -v "xoxb-\.\.\." | grep -v "\.env\.example" | grep -q "xoxb-"; then
  fail "Possible hardcoded Slack bot token found"
  SECRET_FOUND=$((SECRET_FOUND+1))
fi
[[ $SECRET_FOUND -eq 0 ]] && pass "No hardcoded secrets detected"

echo ""
echo "========================================"
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

[[ $FAIL -eq 0 ]] && echo " ALL TESTS PASSED" && exit 0 || echo " FAILURES DETECTED" && exit 1
