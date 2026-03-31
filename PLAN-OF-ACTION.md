# GTM Company -- Plan of Action

**Date:** 2026-03-31
**Author:** Development team audit
**Status:** Pre-development honest assessment

---

## Current State (Honest Assessment)

### What's Actually Working

These components have code written and show evidence of thought-through design:

- **Supabase schema (V1-V4 migrations exist):** Tables defined for `agent_runs`, `memories`, `contacts`, `episodes`, `agent_messages`, `campaign_stats`, `agent_status`, and `call_logs`. Migration SQL files exist at `lib/supabase-migration.sql` through `lib/supabase-migration-v4.sql`. Whether these have been applied to the live Supabase instance is unverified.
- **Shell library layer is complete and well-structured:**
  - `lib/memory.sh` -- Supabase CRUD for memories, contacts, agent_runs, episodes. Uses curl with proper HTTP error checking and retry logic.
  - `lib/agent-comms.sh` -- Inter-agent messaging via `agent_messages` table. Send, receive, mark read/processed, broadcast, queue and flush outbound messages.
  - `lib/sync-state.sh` -- Syncs local JSON state files to Supabase after each run.
  - `lib/paperclip.sh` -- Heartbeat and issue reporting to the Paperclip dashboard.
  - `lib/smartlead.sh` -- Full SmartLead API bridge: fetches campaigns, stats, replies, and syncs to `campaign_stats` table.
  - `lib/run-agent.sh` -- Main agent runner. Builds a prompt from playbook + config + state + memory, pipes it to Claude CLI, handles timeouts, lock files, inbound instructions, outbound message flush, and state sync.
  - `lib/autopilot.sh` -- Cross-platform scheduling (launchd on macOS, crontab on Linux). Reads `config/schedules.json`, installs cron entries, handles log rotation.
- **Agent playbooks (8 total):** Detailed operational playbooks exist for `orchestrator`, `cold-outreach`, `linkedin-engage`, `lead-router`, `content-strategist`, `weekly-strategist`, `power-partnerships`, and `content-engine`. Each defines mission, schedule, run checklist, state files, outputs, guardrails, memory integration, and inter-agent communication protocol.
- **Dashboard Next.js app exists** at `dashboard/` with:
  - Supabase client with safe SSR proxy (`dashboard/src/lib/supabase.ts`)
  - Auth provider with login redirect (`dashboard/src/lib/auth.tsx`)
  - Login page (`dashboard/src/app/login/page.tsx`)
  - Overview dashboard (`dashboard/src/app/page.tsx`) -- reads from `agent_status`, `agent_runs`, `episodes`, `contacts`, `campaign_stats`, `agent_messages`
  - Chat page (`dashboard/src/app/chat/page.tsx`) -- sidebar with agent list, message history, campaign stat cards, daily briefing display
  - Navigation bar (`dashboard/src/app/nav.tsx`)
  - Global CSS with dark theme variables (`dashboard/src/app/globals.css`)
- **Config files are populated:**
  - `config/project.json` -- AI Integrators business config, ICP, offer tiers, channel limits, compliance settings
  - `config/schedules.json` -- Cron schedules for all 7 agents
  - `config/thresholds.json` -- Email limits, LinkedIn limits, budget caps, circuit breakers
  - `config/paperclip.json` -- Paperclip integration config
- **State file structure is seeded:** All 8 agents have `state/{agent}/last-run.json` with initial `never_run` status. `weekly-strategist` has a `strategy.json`, `power-partnerships` has a `pipeline-stage.json`, `content-engine` has a `content-library/` directory.
- **Security fix applied:** `run-agent.sh` uses temp files and safe array construction instead of `eval` for prompt injection. Lock files prevent concurrent runs. 10-minute timeout prevents hangs.

### What's Built But Untested

These components have code but have never been run end-to-end with real data:

- **run-agent.sh end-to-end on VPS:** The agent runner has never been tested with a real Claude CLI session on the GTM VPS (167.172.131.251). Unknown: Does Claude Code authenticate correctly? Does the prompt fit within context? Does the output get captured? Does state actually update?
- **SmartLead sync to Supabase:** `smartlead.sh` has a full `sl_sync_to_supabase` function but there is no evidence it has ever been run against the real SmartLead API. The `campaign_stats` table may have been seeded manually rather than through actual sync.
- **Autopilot scheduling on VPS:** `autopilot.sh` exists and handles crontab installation, but there is no evidence cron jobs are actually running on the VPS. The orchestrator heartbeat every 30 minutes has likely never fired.
- **Agent inter-communication:** `agent-comms.sh` implements the full message passing system. But no agent has ever run, so no messages have been sent through this system in production. The orchestrator reading `agent_messages` from the chat is pure design -- never tested.
- **Paperclip heartbeat integration:** `paperclip.sh` has hardcoded UUIDs for all 8 agents and sends heartbeats to `localhost:3100`. Never tested whether Paperclip actually receives and displays these heartbeats.
- **Dashboard authentication flow:** Supabase Auth is wired in `auth.tsx` with `signInWithPassword`. A user was reportedly created (justin@usingaitoscale.com). Never tested end-to-end: login, session persistence, logout, redirect on expired session.
- **Dashboard Supabase Realtime subscriptions:** The overview page and chat page both subscribe to Supabase Realtime channels for live updates. Realtime requires `ALTER PUBLICATION supabase_realtime ADD TABLE ...` to be run -- this is in the migration SQL but may not be enabled on the live database.
- **Scaffold engine:** `scaffold.sh` and `templates/gtm-outbound.json` exist for creating new client projects. Never tested with a real client.
- **Setup flow:** The full SETUP.md walkthrough (VPS provisioning through first agent run) has never been followed start-to-finish by anyone other than the builder.

### What's Broken or Missing

#### Critical: Chat Does Not Work

The chat page (`dashboard/src/app/chat/page.tsx`) inserts messages into the `agent_messages` table with `from_agent: 'user'` and `to_agent: targetAgent`. But **nothing reads those messages and responds**. The chat is a one-way write to a database table. There is no:
- API route that triggers Claude to read and respond to user messages
- WebSocket handler that invokes an AI response
- Anthropic SDK integration in the dashboard for direct LLM responses
- Polling mechanism that checks for user messages and routes them to agents

The orchestrator playbook says it should read `agent_messages` where `to_agent = 'orchestrator'`, but the orchestrator only runs when `run-agent.sh orchestrator` is invoked by cron. If cron is not running, user messages sit in the table forever.

#### Critical: Dashboard Shows Data From Tables That May Be Empty

The overview dashboard reads from `agent_status` (a table added in a later migration). If agents have never run, this table is empty, and the dashboard shows nothing. The `campaign_stats` table may only have manually seeded test data. The `contacts` table is likely empty. The KPI calculations aggregate from `agent_runs` which has no real entries.

Every number on the dashboard is plausibly zero or stale test data. There is no "last updated" timestamp. There is no health check showing whether Supabase is connected.

#### Agent Playbooks Reference Unconfigured External Tools

- `linkedin-engage.md` references "LinkedIn Autopilot v2" -- a 40+ sub-agent system that needs its own configuration and is not set up as an MCP tool
- `content-strategist.md` references "Titans Council" -- a 21 sub-agent positioning system that is not configured
- `content-engine.md` references "Titans Content Multiplier" -- not configured
- `power-partnerships.md` references a "Jay Abraham pipeline" -- not configured
- `cold-outreach.md` references Firecrawl for prospect research -- Firecrawl may not be configured as an MCP tool on the VPS

The MCP tools available to Claude Code on the VPS have never been documented or verified. There is no `.claude/settings.json` or MCP configuration file in the repo.

#### SmartLead Sync Is Manual, Not Automated

`smartlead.sh` has a `sl_sync_to_supabase` function but it is not called by cron or any automated process. The cold-outreach agent playbook says to call it during Phase 3.5, but the agent has never run. The `campaign_stats` data on the dashboard is either manually seeded or absent.

#### Missing: No API Routes in Dashboard

The Next.js dashboard has zero API routes (`app/api/` directory does not exist). Everything is client-side Supabase queries. This means:
- No server-side data aggregation
- No health check endpoint
- No webhook receiver for SmartLead callbacks
- No API for triggering agent runs from the UI
- No Anthropic SDK integration for chat responses

#### Missing: No Test Suite

Zero test files exist anywhere in the repo. No unit tests, no integration tests, no end-to-end tests. No CI/CD pipeline. No GitHub Actions. No automated verification of any kind.

#### Missing: No Error Monitoring

No Sentry, no error tracking, no alerting. If an agent fails at 3am, nobody knows until someone manually checks logs.

#### Missing: Call Center (Phase 3)

`supabase-migration-v4.sql` creates the `call_logs` table, but there is:
- No Retell AI integration code
- No call center page in the dashboard (nav references it but no page exists)
- No voicemail drop functionality
- No callback handling

#### Known Issues From Audit (Unverified Fixes)

1. `eval` injection risk in `run-agent.sh` -- reportedly fixed with temp file approach, but needs verification on VPS
2. Hardcoded UUIDs in `paperclip.sh` -- these map to the AI Integrators Paperclip company. Will break for any other client.
3. Dashboard `agent_status` table may not exist if V2/V3 migrations were not run
4. `smartlead.sh` uses `SUPABASE_SERVICE_KEY` (service role) while `memory.sh` uses `SUPABASE_ANON_KEY` -- inconsistency that will cause write failures if the wrong key is used
5. CAN-SPAM `{{PHYSICAL_ADDRESS}}` placeholder in `project.json` is still a placeholder, not a real address
6. No loading states in any React component -- dashboard shows blank screen while data loads
7. No error boundaries in React -- a single Supabase query failure crashes the whole page
8. `autopilot.sh` on macOS uses launchd, but the VPS is Linux -- only the crontab path matters for production
9. Log rotation exists in `autopilot.sh` but is never called automatically

### Architecture Diagram

```
+------------------+     +------------------+     +------------------+
|  LOCAL MACHINE   |     | VPS: 167.172.    |     | VPS: 134.122.    |
|  (Development)   |     | 131.251 (GTM)    |     | 17.43 (Cold      |
|                  |     |                  |     |  Email - Legacy)  |
|  Paperclip Hub   |     | Claude Code CLI  |     |                  |
|  :3100           |     | run-agent.sh     |     | Old cold email   |
|                  |     | autopilot.sh     |     | dashboard        |
|  gtm-company/    |     | (cron schedules) |     | (to be replaced) |
|  (source code)   |     |                  |     |                  |
+--------+---------+     | Dashboard :3200  |     +------------------+
         |                | (Next.js app)    |
         | rsync deploy   +--------+---------+
         +------------------------>|
                                   |
                    +--------------+--------------+
                    |                             |
                    v                             v
          +-----------------+           +------------------+
          | Supabase Cloud  |           | SmartLead API    |
          |                 |           | (Cold Email      |
          | agent_runs      |           |  Sending)        |
          | memories        |           |                  |
          | contacts        |           | Campaigns        |
          | episodes        |           | Analytics        |
          | agent_messages  |           | Leads/Replies    |
          | campaign_stats  |           +------------------+
          | agent_status    |
          | call_logs       |
          |                 |
          | Supabase Auth   |
          | Realtime Subs   |
          +-----------------+

Data Flow (Intended -- Not Yet Working):

  1. Cron fires every N minutes on VPS
     |
  2. run-agent.sh {agent-name} --auto
     |
  3. Loads: playbook + config + state + Supabase memory
     |
  4. Pipes prompt to: claude --print -p -
     |
  5. Claude uses MCP tools:
     |-- Gmail MCP --> Read/draft emails
     |-- Firecrawl --> Research prospects
     |-- Calendar --> Book meetings
     |-- SmartLead (via smartlead.sh) --> Sync campaign data
     |
  6. Claude writes:
     |-- state/{agent}/last-run.json (local)
     |-- state/{agent}/new-contacts.json (local)
     |
  7. run-agent.sh post-processing:
     |-- flush_outbound_queue --> agent_messages (Supabase)
     |-- send task_complete --> orchestrator (Supabase)
     |-- sync_all --> agent_runs, contacts (Supabase)
     |-- pc_heartbeat --> Paperclip :3100
     |
  8. Dashboard reads:
     |-- Supabase Realtime subscriptions
     |-- Updates UI in real-time
     |
  9. User sends chat message:
     |-- Writes to agent_messages (Supabase)
     |-- [BROKEN] Nobody reads it until orchestrator runs
     |-- [MISSING] No real-time AI response mechanism

  SmartLead Sync (Intended -- Not Automated):

  smartlead.sh sl_sync_to_supabase
     |
     |-- GET /campaigns --> list all campaigns
     |-- GET /campaigns/{id}/analytics --> stats per campaign
     |-- POST /campaign_stats --> upsert to Supabase
     |-- POST /agent_runs --> log the sync
     |
     Dashboard reads campaign_stats via Realtime
```

---

## Phase 1: Make the Dashboard Trustworthy (Week 1)

**Goal:** Every number on the dashboard traces to a real data source. The chat answers questions. A developer can trust the UI.

### 1.1 Data Integrity

- [ ] Verify all 4 Supabase migration files have been applied to the live database. Run each migration idempotently and check table existence.
- [ ] Verify Supabase Realtime is enabled for all tables listed in the migration (`agent_runs`, `memories`, `contacts`, `episodes`, `agent_messages`, `campaign_stats`, `agent_status`, `call_logs`).
- [ ] Add a `/api/health` endpoint in the dashboard that checks:
  - Supabase connection (query `agent_runs` with limit 1)
  - SmartLead API reachability (if API key is set)
  - Timestamp of most recent data in each table
- [ ] Add "Last synced: X minutes ago" to every dashboard section header. Each section should show the `updated_at` of its most recent row.
- [ ] Add loading skeletons to every React component. Currently the dashboard shows a blank screen during data fetch.
- [ ] Add error boundaries so a single failed query does not crash the whole page.
- [ ] Verify the `agent_status` table exists (V2 migration) and is populated. If agents have never run, pre-seed with `idle` status for all 8 agents so the dashboard is not blank.
- [ ] Resolve the `SUPABASE_SERVICE_KEY` vs `SUPABASE_ANON_KEY` inconsistency. `smartlead.sh` uses service key; `memory.sh` uses anon key. Dashboard uses anon key. Decide: either use anon key everywhere with permissive RLS policies (current), or use service key in shell scripts and anon key in the dashboard. Document the decision.

### 1.2 Cold Email Tab

- [ ] Run `smartlead.sh sl_sync_to_supabase` manually once to populate `campaign_stats` with real SmartLead data. Verify the data appears correctly in Supabase.
- [ ] Create a cron job on the VPS: `*/15 * * * * cd /root/gtm-company && source .env && source lib/smartlead.sh && sl_sync_to_supabase >> logs/smartlead-sync.log 2>&1`
- [ ] Verify the dashboard overview page reads `campaign_stats` correctly: campaign names, sent counts, open rates, reply rates, bounce rates.
- [ ] Compare dashboard numbers against SmartLead UI to confirm accuracy.
- [ ] Add reply classification data: the dashboard should show positive/negative/question/OOO breakdowns from the `episodes` table.

### 1.3 Chat That Actually Works

The current chat writes to `agent_messages` but nobody reads it. Two options:

**Option A (Simple, do this first):** Add a Next.js API route at `/api/chat` that:
1. Receives the user message
2. Queries Supabase for context: recent `campaign_stats`, recent `agent_runs`, pipeline counts from `contacts`, recent `episodes`
3. Calls the Anthropic API directly (using `@anthropic-ai/sdk`) with the context + user question
4. Returns the response
5. Saves both the user message and the AI response to `agent_messages`

This gives immediate, interactive chat without waiting for cron-based agent runs.

**Option B (Later, adds orchestrator intelligence):** Keep the agent_messages approach but add a webhook or polling mechanism where the orchestrator picks up user messages within 60 seconds.

Implementation for Option A:
- [ ] Install `@anthropic-ai/sdk` in the dashboard project
- [ ] Create `/api/chat/route.ts` with streaming response
- [ ] Build a system prompt that includes: project config, recent campaign stats, pipeline counts, last 10 episodes, last 5 agent runs per agent
- [ ] Update the chat UI to call `/api/chat` and display streaming responses
- [ ] Save the assistant response back to `agent_messages` with `from_agent: 'assistant'`
- [ ] Add rate limiting (max 20 questions per hour)

### 1.4 Authentication

- [ ] Test login with justin@usingaitoscale.com end-to-end: open dashboard, get redirected to `/login`, enter credentials, verify redirect to `/`, verify session persists on refresh, verify sign-out works.
- [ ] If the user does not exist in Supabase Auth, create them via the Supabase dashboard (Authentication > Users > Create User).
- [ ] Add session expiry handling: if the Supabase session expires mid-use, redirect to login gracefully instead of showing broken data.
- [ ] Add the `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` to the VPS `.env` and verify the dashboard reads them at runtime.

---

## Phase 2: Agent Execution (Week 2)

**Goal:** At least one agent runs autonomously, updates state, and the dashboard reflects the result within minutes.

### 2.1 Run-Agent End-to-End

- [ ] SSH into the GTM VPS (167.172.131.251).
- [ ] Verify Claude Code CLI is installed: `which claude && claude --version`
- [ ] Verify Claude Code is authenticated: `claude auth status`
- [ ] Verify `.env` is populated with `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `PROJECT_ID`, and optionally `SMARTLEAD_API_KEY`.
- [ ] Run: `cd ~/gtm-company && ./lib/run-agent.sh cold-outreach` (without `--auto` first, to see what Claude does in interactive mode)
- [ ] Verify each step:
  - Prompt builds correctly (check the temp file or log output)
  - Claude receives the prompt and responds
  - State file is updated at `state/cold-outreach/last-run.json`
  - Supabase `agent_runs` has a new row
  - `agent_messages` has a `task_complete` message from `cold-outreach` to `orchestrator`
  - Paperclip heartbeat was attempted (will fail if Paperclip is not running -- that is OK)
- [ ] Run again with `--auto` flag: `./lib/run-agent.sh cold-outreach --auto`
- [ ] Measure: How long does a run take? How many tokens? What does it cost?

### 2.2 MCP Tool Configuration on VPS

Claude Code on the VPS needs MCP tools configured. Without them, agents cannot actually do their work.

- [ ] Document what MCP tools are currently configured on the VPS: `cat ~/.claude/settings.json` or equivalent
- [ ] Required for Phase 2 (cold-outreach agent):
  - Gmail MCP -- for reading replies and creating drafts
  - Firecrawl -- for prospect research (requires `FIRECRAWL_API_KEY`)
- [ ] Required for Phase 2 (orchestrator agent):
  - No MCP tools needed -- orchestrator only reads/writes Supabase via shell functions
- [ ] Required for Phase 4 (linkedin-engage, content-strategist, content-engine):
  - LinkedIn Autopilot v2 -- this is a separate system, not an MCP tool. Need to define how the agent invokes it.
  - Titans Council -- same issue. These are prompt-based systems, not MCP tools. The playbooks need to be rewritten to use available tools.
- [ ] Create a `.claude/settings.json` in the repo that documents all required MCP configurations
- [ ] Test each MCP tool individually: send a test Gmail search, run a test Firecrawl scrape

### 2.3 Cold Outreach Agent End-to-End

This is the first agent to make fully work because the cold email infrastructure already exists (SmartLead is running campaigns).

- [ ] Manual run with `--auto` flag
- [ ] Verify Phase 1 (Load State): reads `state/cold-outreach/last-run.json`
- [ ] Verify Phase 2 (Process Replies): searches Gmail for recent replies, classifies them
- [ ] Verify Phase 3 (New Outreach): researches prospects, drafts emails (as Gmail DRAFTS only)
- [ ] Verify Phase 3.5 (SmartLead Sync): sources `smartlead.sh` and runs `sl_sync_to_supabase`
- [ ] Verify Phase 4 (Update State): writes updated `last-run.json` and `pipeline.json`
- [ ] Verify Phase 5 (Report): sends `task_complete` to orchestrator via `agent_messages`
- [ ] Check dashboard: do the numbers update?
- [ ] Check Supabase: are `agent_runs`, `contacts`, `episodes`, `campaign_stats` populated?

### 2.4 Orchestrator Agent End-to-End

- [ ] Manual run: `./lib/run-agent.sh orchestrator --auto`
- [ ] Verify it reads `agent_messages` for unread messages (including the `task_complete` from cold-outreach)
- [ ] Verify it checks agent health (queries `agent_runs` for recent runs vs expected schedules)
- [ ] Verify it generates a daily briefing and posts to `agent_messages` with `to_agent: 'user'`
- [ ] Verify it reads and processes user messages from the chat (if any exist in `agent_messages` with `from_agent: 'user'`)
- [ ] Verify state files update: `state/orchestrator/last-heartbeat.json`
- [ ] Check that the daily briefing appears in the chat UI

### 2.5 Enable Autopilot

- [ ] On VPS, run: `./lib/autopilot.sh start`
- [ ] Verify crontab entries: `crontab -l`
- [ ] Wait for the first scheduled cold-outreach run (every 2 hours at :07)
- [ ] Check logs: `tail -f logs/cold-outreach.log`
- [ ] Wait for the first orchestrator heartbeat (every 30 minutes)
- [ ] Check logs: `tail -f logs/orchestrator.log`
- [ ] Verify the dashboard updates without manual intervention
- [ ] Monitor for 24 hours. Check for: failed runs, stuck locks, disk space issues, log growth

---

## Phase 3: Call Center (Week 3)

**Goal:** Automated outbound calls with voicemail drops and callback tracking.

### 3.1 Retell AI Integration

- [ ] Create Retell AI account (https://retellai.com)
- [ ] Design the AI calling agent with the staffing agency pitch (use ICP and offer from `config/project.json`)
- [ ] Create a Retell AI agent via their API or dashboard
- [ ] Build `lib/retell.sh` -- a shell library similar to `smartlead.sh` that:
  - Queues a call: takes contact_id, phone number, campaign
  - Checks call status
  - Retrieves transcript and outcome
  - Syncs results to `call_logs` table
- [ ] Verify `supabase-migration-v4.sql` has been applied (creates `call_logs` table)

### 3.2 Call Center Dashboard Page

- [ ] Create `dashboard/src/app/calls/page.tsx`
- [ ] Show: queued calls, active calls, completed calls, outcomes
- [ ] Display call metrics: calls made today, voicemails dropped, callbacks received, meetings booked
- [ ] Show recent call transcripts
- [ ] Add to navigation

### 3.3 Voicemail Drops

- [ ] Configure Retell for voicemail detection
- [ ] Pre-record or AI-generate voicemail messages
- [ ] Track voicemail drops as `call_type: 'voicemail_drop'` in `call_logs`
- [ ] Track callbacks: when a prospect calls back, create a new `call_logs` entry with `call_type: 'callback'`

### 3.4 Call-to-Meeting Pipeline

- [ ] When a call outcome is `meeting_booked`, create a calendar event
- [ ] When a call outcome is `interested`, route to email follow-up (post to `agent_messages` for cold-outreach or lead-router)
- [ ] Callbacks route through the same system

---

## Phase 4: Content and LinkedIn (Week 4)

**Goal:** LinkedIn posts publishing, content being produced, partnerships being researched.

### 4.1 LinkedIn Engage Agent

The current playbook references "LinkedIn Autopilot v2" which is a separate system. This needs a realistic implementation plan.

**Option A (Simple):** Rewrite the playbook to use Claude directly:
- [ ] Claude drafts LinkedIn posts based on content strategy
- [ ] Posts are saved to `state/linkedin-engage/drafts/` for manual posting
- [ ] Claude monitors a dedicated Gmail or spreadsheet for LinkedIn lead notifications
- [ ] Leads are logged to `contacts` table with `source: 'linkedin'`

**Option B (Full Automation):** Requires browser automation or LinkedIn API:
- [ ] This is risky and may violate LinkedIn ToS
- [ ] Defer to Phase 5 or later

For now, implement Option A:
- [ ] Rewrite `agents/linkedin-engage.md` to remove references to unconfigured tools
- [ ] Test agent run: generates post drafts, saves to state
- [ ] Test lead detection: reads manual inputs, creates contact records

### 4.2 Content Engine Agent

- [ ] Rewrite `agents/content-engine.md` to use Claude directly instead of "Titans Content Multiplier"
- [ ] Agent takes weekly strategy from `state/weekly-strategist/strategy.json` and generates:
  - 5 LinkedIn post drafts
  - 2 email newsletter drafts
  - 1 long-form thought leadership piece
- [ ] Content saved to `state/content-engine/content-library/`
- [ ] Test: manual run, verify content quality, verify state updates

### 4.3 Content Strategist Agent

- [ ] Rewrite `agents/content-strategist.md` to use Claude directly instead of "Titans Council"
- [ ] Agent reads: recent episode data (what messaging worked), campaign stats (what got replies), and generates updated positioning/messaging guidance
- [ ] Output: updated `state/weekly-strategist/strategy.json`
- [ ] Test: manual run, verify strategy output is actionable

### 4.4 Power Partnerships Agent

- [ ] Rewrite `agents/power-partnerships.md` to remove "Jay Abraham pipeline" references
- [ ] Agent researches complementary businesses using Firecrawl
- [ ] Generates partnership proposals as drafts
- [ ] Tracks partnership pipeline in `state/power-partnerships/pipeline-stage.json`
- [ ] Test: manual run, verify research quality

---

## Phase 5: Productization (Week 5+)

**Goal:** A new client can be onboarded in under 60 minutes.

### 5.1 Scaffold Engine

- [ ] Test `scaffold.sh gtm-outbound test-client-gtm` end-to-end
- [ ] Verify all files are created correctly
- [ ] Verify `config/project.json` is properly templated
- [ ] Verify `.env.example` is generated
- [ ] Run agents in the new project directory
- [ ] Create additional templates: `gtm-content-only`, `gtm-calling`

### 5.2 Client Onboarding

- [ ] Follow SETUP.md from scratch on a brand new DigitalOcean droplet
- [ ] Time every step. Target: under 60 minutes total.
- [ ] Document every point where something breaks or is confusing
- [ ] Fix each issue and re-test
- [ ] Create a video walkthrough or automated setup script

### 5.3 Pricing and Packaging

- [ ] Calculate actual running costs per client:
  - Anthropic API: measure actual token usage per agent run, multiply by schedule frequency
  - VPS: $12/mo
  - SmartLead: $39/mo
  - Supabase: free tier for single client, $25/mo for Pro
- [ ] Validate tier pricing from `config/project.json`:
  - Foundation ($300/mo): cold email only
  - Growth ($697-$1,497/mo): email + LinkedIn + content
  - Full GTM ($2,997-$4,997/mo): everything + custom agents
- [ ] Create a sales page or proposal template
- [ ] Define SLA: what uptime/response time is guaranteed?

---

## Development Workflow

### For Each Task

1. Create a feature branch: `git checkout -b feature/phase1-health-check`
2. Implement the change
3. Test locally if possible (dashboard changes can be tested locally with Supabase)
4. Test on VPS for shell script changes
5. Commit with descriptive message: `feat(dashboard): add health check endpoint`
6. Push and create PR (or merge directly to main for single-developer workflow)
7. Update this PLAN-OF-ACTION.md: change `[ ]` to `[x]` for completed items

### Testing Checklist Template

For each component being verified:
- [ ] Isolation test: does the function work with correct inputs?
- [ ] Integration test: does it work with real Supabase / SmartLead / Gmail?
- [ ] End-to-end test: does the full flow from trigger to dashboard display work?
- [ ] Failure test: what happens when Supabase is unreachable? When SmartLead returns an error? When Claude times out?
- [ ] Recovery test: after a failure, does the next run pick up correctly?
- [ ] Idempotency test: running the same operation twice does not create duplicates?

---

## Key Files Reference

| File | Purpose | Status |
|------|---------|--------|
| `lib/run-agent.sh` | Main agent runner -- builds prompt, runs Claude, syncs state | Written, untested on VPS |
| `lib/memory.sh` | Supabase CRUD for memories, contacts, runs, episodes | Written, untested with real data |
| `lib/agent-comms.sh` | Inter-agent messaging via `agent_messages` table | Written, untested |
| `lib/sync-state.sh` | Syncs local JSON state to Supabase after runs | Written, untested |
| `lib/paperclip.sh` | Heartbeat reporting to Paperclip dashboard | Written, hardcoded UUIDs |
| `lib/smartlead.sh` | SmartLead API bridge, campaign sync to Supabase | Written, untested against real API |
| `lib/autopilot.sh` | Cross-platform cron scheduling for all agents | Written, untested on VPS |
| `lib/setup-supabase.sh` | Runs SQL migrations against Supabase | Written, unknown if run |
| `lib/supabase-migration.sql` | V1 schema: agent_runs, memories, contacts, episodes | Written |
| `lib/supabase-migration-v2.sql` | V2 schema: agent_messages, agent_status | Written, unknown if applied |
| `lib/supabase-migration-v3.sql` | V3 schema: campaign_stats | Written, unknown if applied |
| `lib/supabase-migration-v4.sql` | V4 schema: call_logs (Retell AI) | Written, unknown if applied |
| `config/project.json` | Business config, ICP, offer, channels, compliance | Populated for AI Integrators |
| `config/schedules.json` | Cron schedules for all 7 agents | Populated |
| `config/thresholds.json` | Email/LinkedIn/budget limits, circuit breakers | Populated |
| `config/paperclip.json` | Paperclip integration config | Populated |
| `agents/orchestrator.md` | Orchestrator playbook -- health monitoring, routing, briefings | Written, untested |
| `agents/cold-outreach.md` | Cold email playbook -- reply processing, new outreach, SmartLead sync | Written, untested |
| `agents/linkedin-engage.md` | LinkedIn playbook -- references unconfigured tools | Written, needs rewrite |
| `agents/lead-router.md` | Lead routing playbook -- cross-channel dedup | Written, untested |
| `agents/content-strategist.md` | Content strategy playbook -- references Titans Council | Written, needs rewrite |
| `agents/weekly-strategist.md` | Weekly strategy playbook | Written, untested |
| `agents/power-partnerships.md` | Partnerships playbook -- references unconfigured tools | Written, needs rewrite |
| `agents/content-engine.md` | Content production playbook -- references unconfigured tools | Written, needs rewrite |
| `dashboard/src/app/page.tsx` | Overview dashboard -- agents, pipeline, KPIs, activity | Written, untested with real data |
| `dashboard/src/app/chat/page.tsx` | Chat page -- writes to agent_messages, no AI response | Broken -- one-way only |
| `dashboard/src/app/login/page.tsx` | Login page with Supabase Auth | Written, untested |
| `dashboard/src/lib/supabase.ts` | Supabase client with SSR-safe proxy | Working |
| `dashboard/src/lib/auth.tsx` | Auth context with login redirect | Written, untested |
| `dashboard/src/app/nav.tsx` | Navigation bar | Working |
| `dashboard/src/app/globals.css` | Dark theme CSS variables | Working |
| `scaffold.sh` | Template engine for creating new client projects | Written, untested |
| `templates/gtm-outbound.json` | Template manifest for GTM outbound projects | Written |
| `triggers/setup-triggers.sh` | Trigger setup script | Written, unknown status |

---

## Technical Debt

| Item | Severity | Notes |
|------|----------|-------|
| No test suite at all | High | Zero tests anywhere. Add at minimum: shell function tests for memory.sh, integration tests for Supabase queries, component tests for dashboard. |
| No CI/CD pipeline | High | Manual deployment via rsync. Need GitHub Actions: lint, test, build dashboard, deploy to VPS. |
| Hardcoded UUIDs in paperclip.sh | Medium | Agent-to-UUID mapping breaks for any non-AI-Integrators client. Should be dynamic or config-driven. |
| No loading states in React | Medium | Dashboard shows blank screen during data fetch. Add skeletons. |
| No error boundaries in React | Medium | Single failed query crashes the whole page. |
| No error monitoring | High | No Sentry, no alerting. Agent failures are silent. |
| Secrets in .env files | Medium | No proper secrets management. Fine for single-operator, but needs Vault or similar for multi-client. |
| Manual deployments | Medium | rsync to VPS. Should be git pull on VPS or CI/CD deploy. |
| No health check endpoint | Medium | Cannot programmatically verify the system is working. |
| `{{PHYSICAL_ADDRESS}}` placeholder | Low | CAN-SPAM compliance: must be replaced before any real email sending. |
| Dashboard has no API routes | Medium | All queries are client-side. Need server-side routes for chat, health, webhooks. |
| 4 agent playbooks reference unconfigured tools | High | linkedin-engage, content-strategist, content-engine, power-partnerships all reference systems that do not exist as MCP tools. Playbooks need rewriting. |
| No log shipping | Low | Logs stay on VPS. Should ship to a centralized log service for debugging. |
| No backup strategy | Medium | Supabase free tier has point-in-time recovery. State files on VPS have no backup. |
| SmartLead uses service key, memory uses anon key | Low | Inconsistency. Choose one approach and document it. |

---

## Success Criteria

### Phase 1: Dashboard Is Trustworthy
- Every number on the dashboard traces to a Supabase query on a table with real data
- Every section shows "Last synced: X minutes ago" or equivalent
- SmartLead data syncs automatically every 15 minutes and matches the SmartLead UI
- Chat accepts a question like "How are campaigns doing?" and returns an accurate, AI-generated answer within 5 seconds
- Login works end-to-end. Unauthenticated users see the login page.
- Health check endpoint returns 200 with connection status for all data sources.

### Phase 2: Agents Run Autonomously
- `cold-outreach` runs every 2 hours on the VPS without human intervention
- `orchestrator` runs every 30 minutes and generates daily briefings
- State files update after every run. Supabase `agent_runs` has entries.
- Dashboard shows real-time updates when an agent completes a run
- At least one Gmail draft is created by the cold-outreach agent
- The orchestrator reads and responds to user chat messages within one heartbeat cycle (30 min max)

### Phase 3: Calls Are Being Made
- Retell AI makes at least 10 outbound calls per day
- Voicemails are dropped when no answer
- Callbacks are tracked in `call_logs`
- Call outcomes feed into the pipeline (meetings booked, follow-ups needed)
- Dashboard call center page shows real call data

### Phase 4: Content Is Being Produced
- At least 3 LinkedIn post drafts per week, saved to state
- Content strategy updates weekly based on campaign performance
- Partnership research produces actionable prospect lists
- All agents reference only tools that are actually configured and available

### Phase 5: New Client Onboarding
- A fresh VPS can be set up with a working GTM system in under 60 minutes
- `scaffold.sh` creates a clean, runnable project
- SETUP.md is tested and accurate with zero undocumented gotchas
- Running costs are documented and match tier pricing

---

## Priority Order (What to Do First)

1. **Verify Supabase migrations are applied** -- 15 minutes, unblocks everything
2. **Run SmartLead sync once manually** -- 10 minutes, populates real data
3. **Add `/api/chat` route with Anthropic SDK** -- 2-3 hours, makes the chat work
4. **Add loading states and error boundaries to dashboard** -- 1-2 hours, prevents blank screens
5. **Test `run-agent.sh` on VPS with cold-outreach** -- 1-2 hours, proves agents work
6. **Set up SmartLead cron sync** -- 15 minutes, keeps data fresh
7. **Test orchestrator on VPS** -- 1 hour, proves the coordination layer works
8. **Enable autopilot and monitor for 24 hours** -- ongoing, proves the system runs
9. **Rewrite 4 playbooks to remove phantom tool references** -- 4-6 hours, makes agents honest about capabilities
10. **Build call center integration** -- 1-2 weeks, new capability
