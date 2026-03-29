# GTM Company — Autonomous Go-To-Market Machine

An integrated go-to-market operation that runs cold email outreach, LinkedIn engagement, content strategy, and lead routing autonomously using AI agents powered by Claude Code + MCP integrations.

Built for **AI Integrators** (UsingAIToScale.com) as an internal GTM system and the first working example for the Expert Series product.

## What It Does

| Agent | Deliverable | Schedule |
|-------|------------|----------|
| `cold-outreach` | Send personalized cold emails, handle replies | Every 2 hours |
| `linkedin-engage` | Post content, engage with prospects, detect leads | 3x daily |
| `lead-router` | Deduplicate contacts across channels, route to best channel | Every 2h (offset) |
| `content-strategist` | Weekly positioning refresh via Titans Council | Monday 9am |
| `weekly-strategist` | Analyze what worked, update strategy | Sunday 8pm |

## Architecture

```
Claude Code + MCP Tools (Runtime)
    |
    ├── Gmail MCP → Send/read emails
    ├── Firecrawl → Research prospects
    ├── ClickUp MCP → Task management
    ├── Slack MCP → Team notifications
    ├── Calendar MCP → Meeting booking
    └── Notion MCP → Knowledge base

Supabase PostgreSQL (Persistence)
    |
    ├── agent_runs → Audit trail of every execution
    ├── memories → Facts that persist across sessions
    ├── contacts → Cross-pipeline deduplication
    └── episodes → What worked / what didn't

Local State Files (Hot Cache)
    |
    └── state/{agent}/last-run.json → Fast reads during runs
```

## Quick Start

```bash
# 1. Clone and enter
cd ~/Desktop/gtm-company

# 2. Set up environment
cp .env.example .env
# Edit .env with your Supabase credentials

# 3. Set up Supabase database
./lib/setup-supabase.sh

# 4. Run your first agent
./lib/run-agent.sh cold-outreach

# 5. Set up automated scheduling
./triggers/setup-triggers.sh
```

## Scaffold a New Project From This Template

```bash
# Create a new GTM operation for a different business
./scaffold.sh gtm-outbound acme-corp-gtm

# Or with a config file
./scaffold.sh gtm-outbound acme-corp-gtm --config /path/to/config.json
```

## Key Design Principles

1. **Output-first** — Agents defined by deliverable, not by title
2. **Parallel execution** — No delegation chains; each agent does its own work
3. **Persistence** — Supabase for cross-session memory; local JSON for speed
4. **Safety** — All emails are DRAFTS in V1 (human approves before sending)
5. **Measurable** — Every run logs outputs (emails sent, leads created, etc.)
6. **Expert Series ready** — Everything documented for productization

## Wraps Existing Systems

This project doesn't rebuild from scratch. It orchestrates:

- **Cold Email Agent** (16 sub-agents) — prospect research, email generation, quality gauntlet
- **LinkedIn Autopilot v2** (40+ sub-agents) — content engine, engagement engine, self-learning
- **Titans Council** (21 sub-agents) — positioning, messaging, offer strategy from 18 legendary copywriters

## File Structure

```
gtm-company/
├── agents/           # One playbook per deliverable
├── config/           # Business config, schedules, guardrails
├── dashboards/       # Supabase SQL queries for KPIs
├── lib/              # Memory library, agent runner, sync tools
├── scaffold.sh       # Template engine for new projects
├── state/            # Local JSON state (hot cache)
├── templates/        # Template manifests for scaffold engine
└── triggers/         # Scheduling setup scripts
```

## Environment Variables

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
PROJECT_ID=ai-integrators-gtm
SLACK_CHANNEL=#gtm-ops
```
