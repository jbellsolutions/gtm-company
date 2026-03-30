# GTM Company — AI Integrators Go-To-Market System

## Project Overview

This is the autonomous GTM (Go-To-Market) system for AI Integrators (UsingAIToScale.com). It runs a team of AI agents that handle cold outreach, LinkedIn engagement, lead routing, content strategy, and weekly planning — all coordinated through Supabase memory and local state files.

**Project ID:** `ai-integrators-gtm`
**Comms Channel:** Supabase `agent_messages` table (replaces Slack #gtm-ops)

## Architecture

```
config/          — project.json, schedules.json, thresholds.json
agents/          — Agent playbooks (*.md) — one per agent
lib/memory.sh    — Supabase REST API integration (source in every agent)
lib/sync-state.sh — Pushes local state to Supabase after runs
lib/run-agent.sh — Main runner: playbook + config + state + memory → Claude
state/<agent>/   — Local state files (last-run.json, strategy.json, etc.)
```

## Agent Rules

1. **Read your playbook first.** Every agent has a playbook at `agents/<name>.md`. Follow it exactly.
2. **Follow the run checklist.** Each run must:
   - Read last-run.json to understand current state
   - Do the work described in the playbook
   - Update state/<agent>/last-run.json with results
   - Send a `task_complete` message to orchestrator via agent-comms.sh
3. **Log everything.** All runs are logged to Supabase via sync-state.sh.
4. **Respect thresholds.** Check config/thresholds.json before any action. Never exceed limits.
5. **Pick up where you left off.** Check `next_actions` in last-run.json.

## Memory Integration

Every agent sources `lib/memory.sh` which provides:
- `mem_get/mem_set/mem_search/mem_list` — key-value memory store
- `contact_check/contact_upsert/contact_list` — contact management
- `log_run/log_episode` — run and episode logging
- `get_recent_runs/get_recent_episodes` — history retrieval

Memory is shared across all agents via Supabase. Use it to:
- Store learnings and strategy updates
- Track contacts across the pipeline
- Review what other agents have done recently

## Safety Rails

**CRITICAL — these are non-negotiable:**

- **NEVER auto-send emails.** Always create drafts. A human reviews before sending.
- **NEVER exceed daily limits.** Check thresholds.json:
  - Max 50 emails/day, 10 drafts/run
  - Max 1 LinkedIn post/day, 10 comments/run
  - Max 50,000 tokens/run
- **Circuit breaker:** If cost exceeds 2x normal, STOP and send an `escalation` message to orchestrator via agent-comms.sh.
- **Max 3 consecutive failures** before sending an `escalation` message to orchestrator.
- **Never modify contacts** without logging the change.
- **When in doubt, STOP** and send an `escalation` message to orchestrator via agent-comms.sh asking for guidance.

## Expert Series Mode

This system is being documented for productization. Every agent should:
- Write clear, educational summaries of what it did and why
- Document any novel techniques or approaches
- Note what worked and what didn't in learnings
- Keep state files clean and well-structured for review

## Available MCP Tools

Agents have access to these integrations:
- **Gmail** — Search, read, create drafts (NEVER send directly)
- **ClickUp** — Task management, project tracking
- **Supabase agent_messages** — Inter-agent communication and user messaging (replaces Slack)
- **Google Calendar** — Check availability, schedule meetings
- **Notion** — Documentation, knowledge base
- **Firecrawl** — Web scraping for prospect research
- **Google Drive** — Document storage and retrieval

## State Management Rules

1. **Always read last-run.json FIRST** at the start of every run.
2. **Always update last-run.json LAST** at the end of every run.
3. Required fields in last-run.json:
   ```json
   {
     "status": "completed|partial|failed",
     "run_count": <incremented>,
     "last_run_at": "<UTC ISO timestamp>",
     "next_actions": ["<what to do next run>"],
     "summary": "<what happened this run>"
   }
   ```
4. New contacts go in `state/<agent>/new-contacts.json` (array of objects with `email` field).
5. Strategy updates go in `state/weekly-strategist/strategy.json`.
6. Never delete state files — only overwrite with updated data.

## Running Agents

```bash
# Manual run (interactive)
./lib/run-agent.sh cold-outreach

# Auto mode (non-interactive)
./lib/run-agent.sh cold-outreach --auto
```

## File Conventions

- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`
- JSON: always valid, pretty-printed in config, compact in state
- Agent playbooks: Markdown with clear sections for Role, Goals, Process, Output Format
- All timestamps: UTC ISO 8601 format
