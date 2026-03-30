# GTM Company -- Setup Guide

Complete step-by-step installation for deploying your autonomous go-to-market system.

**Time to complete:** 30-60 minutes
**Skill level:** Basic command-line familiarity

---

## Prerequisites

Before starting installation, you need the following accounts and services.

### Required Accounts

| Service | Cost | What It Does | Sign Up |
|---------|------|--------------|---------|
| Anthropic API | $50-200/mo (usage-based) | Powers all AI agents via Claude Code | https://console.anthropic.com |
| Supabase | Free tier | Database for memory, contacts, audit logs | https://supabase.com |
| DigitalOcean VPS | $12/mo | Runs your agents 24/7 | https://cloud.digitalocean.com |
| Gmail | Free | Outreach email (create a separate account) | https://accounts.google.com |
| Cal.com or Calendly | Free tier | Booking link for meetings | https://cal.com or https://calendly.com |
| LinkedIn | Free (Premium helpful) | Content and prospect engagement | https://linkedin.com |

### Optional Accounts

| Service | Cost | What It Does | Sign Up |
|---------|------|--------------|---------|
| SmartLead | $39/mo | Scaled email sending with warmup | https://smartlead.ai |
| Firecrawl | Free (500 pages/mo) | Prospect research and web scraping | https://firecrawl.dev/app/api-keys |

### Cost Summary

| Tier | Monthly Cost | What You Get |
|------|-------------|--------------|
| **Minimum** | ~$62/mo | Anthropic ($50) + VPS ($12). Manual email, no scaled sending. |
| **Recommended** | ~$100/mo | Add SmartLead ($39) for automated email warmup and sending. |
| **Full setup** | ~$200-400/mo | All integrations, higher API usage for aggressive outreach. |

### VPS Requirements

- **Provider:** DigitalOcean (recommended), Hetzner, or any Linux VPS
- **Size:** 2GB RAM / 1 vCPU minimum (DigitalOcean "Basic $12/mo" droplet)
- **OS:** Ubuntu 24.04 LTS
- **Region:** Choose closest to your target market
- **Image:** Ubuntu 24.04 (LTS) x64

---

## Installation Steps

### Step 1: Create Your VPS

1. Go to https://cloud.digitalocean.com/droplets/new
2. Choose **Ubuntu 24.04 (LTS) x64**
3. Select **Basic plan** -- $12/mo (2 GB RAM, 1 vCPU, 50 GB SSD)
4. Choose a datacenter region near you
5. Under Authentication, select **SSH keys** (recommended) or set a root password
6. Click **Create Droplet**
7. Note the IP address shown after creation

### Step 2: SSH Into Your VPS

```bash
ssh root@YOUR_DROPLET_IP
```

If using a password, enter it when prompted. If using SSH keys, it connects automatically.

### Step 3: Install System Prerequisites

```bash
# Update system packages
apt update && apt upgrade -y

# Install essential tools
apt install -y git jq curl bash

# Install Node.js 22 via NodeSource
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs

# Verify versions
node --version   # Should show v22.x.x
npm --version    # Should show 10.x.x
jq --version     # Should show jq-1.x
bash --version   # Should show 4.x or 5.x
```

### Step 4: Install and Authenticate Claude Code

```bash
# Install Claude Code CLI globally
npm install -g @anthropic-ai/claude-code

# Authenticate with your Anthropic API key
claude auth

# Follow the prompts -- you will need your API key from:
# https://console.anthropic.com/settings/keys
```

When prompted, paste your Anthropic API key. Claude Code stores it securely.

### Step 5: Clone the Repository

```bash
cd ~
git clone https://github.com/jbellsolutions/gtm-company
cd gtm-company
```

### Step 6: Create Your Environment File

```bash
cp .env.example .env
```

### Step 7: Edit .env With Your Credentials

Open the file in your preferred editor:

```bash
nano .env
```

Fill in the required values (see `.env.example` for descriptions of each variable):

| Variable | Where to Find It |
|----------|-----------------|
| `SUPABASE_URL` | Supabase Dashboard > Project Settings > API > Project URL |
| `SUPABASE_ANON_KEY` | Supabase Dashboard > Project Settings > API > anon/public key |
| `PROJECT_ID` | Choose a kebab-case name for your project (e.g., `acme-corp-gtm`) |

Save and exit (in nano: `Ctrl+O`, `Enter`, `Ctrl+X`).

### Step 8: Create Your Supabase Project

1. Go to https://supabase.com/dashboard
2. Click **New Project**
3. Choose your organization (or create one)
4. Set a project name (e.g., `my-company-gtm`)
5. Set a strong database password (save this somewhere safe)
6. Choose a region close to your VPS
7. Click **Create new project**
8. Wait for the project to finish provisioning (1-2 minutes)
9. Go to **Project Settings > API** and copy the **Project URL** and **anon public** key into your `.env` file

The free tier includes 500MB database, 1GB file storage, and 2GB bandwidth -- more than enough for a single GTM operation.

### Step 9: Run Database Setup

```bash
chmod +x lib/setup-supabase.sh
./lib/setup-supabase.sh
```

This creates the required tables in your Supabase project:
- `agent_runs` -- Audit trail of every agent execution
- `memories` -- Facts that persist across Claude Code sessions
- `contacts` -- Cross-pipeline contact deduplication
- `episodes` -- What worked and what did not (learning loop)

Verify by going to your Supabase Dashboard > Table Editor. You should see all four tables.

### Step 10: Configure Your Business

Edit the project configuration with your business details:

```bash
nano config/project.json
```

Key fields to customize:

| Field | What to Enter |
|-------|--------------|
| `project_id` | Unique kebab-case ID (e.g., `acme-corp-gtm`) |
| `company_name` | Your company name and website |
| `mission` | One-sentence description of what your company does |
| `icp.description` | Who is your ideal customer? |
| `icp.verticals` | Array of 3-5 industries you target |
| `icp.pain_points` | Array of problems your customers face |
| `offer.name` | Name of your main service/product |
| `offer.tagline` | One-line pitch |
| `offer.proof_points` | Array of results, testimonials, or case studies |
| `channels.cold_email.daily_limit` | Max cold emails per day (start with 20-30) |
| `channels.cold_email.booking_link` | Your Cal.com or Calendly URL |

### Step 11: Customize Agent Playbooks (Optional)

Agent playbooks live in `agents/`. Each file defines what one agent does:

```
agents/
  cold-outreach.md    -- Prospect research, email generation, reply handling
  linkedin-engage.md  -- Content posting, engagement, lead detection
  lead-router.md      -- Cross-channel deduplication and routing
  content-strategist.md -- Weekly positioning refresh
  weekly-strategist.md  -- Performance analysis and strategy updates
```

You can edit these to adjust:
- Tone and voice for emails and content
- Qualifying criteria for leads
- Engagement rules (who to comment on, how often)
- Reporting format and frequency

If you are not sure what to change, leave them as-is. The defaults work well for most B2B service businesses.

### Step 12: Deploy the Dashboard

The dashboard gives you visibility into agent activity, contacts, and performance.

**Option A: Self-hosted on your VPS (recommended for simplicity)**

```bash
cd dashboard
npm install
npm run build
npm start
# Dashboard runs on http://YOUR_VPS_IP:3100
```

**Option B: Deploy to Vercel (recommended for reliability)**

```bash
cd dashboard
npm install -g vercel
vercel
# Follow prompts to deploy
# Note the URL Vercel gives you
```

Update your `.env` if using Paperclip dashboard:
```
PAPERCLIP_URL=http://localhost:3100  # or your Vercel URL
```

### Step 13: Start Autopilot

```bash
chmod +x lib/autopilot.sh
./lib/autopilot.sh start
```

This sets up cron jobs based on `config/schedules.json` to run agents automatically:
- Cold outreach: every 2 hours during business hours
- LinkedIn engage: 3 times daily
- Lead router: every 2 hours (offset from outreach)
- Content strategist: Monday 9am
- Weekly strategist: Sunday 8pm

To check the cron schedule:
```bash
crontab -l
```

To stop autopilot:
```bash
./lib/autopilot.sh stop
```

### Step 14: Verify Everything Works

Run these checks to confirm your setup is working:

```bash
# 1. Check that environment is loaded
source .env && echo "Project: $PROJECT_ID"

# 2. Test Supabase connection
./lib/sync-state.sh

# 3. Run one agent manually to verify
./lib/run-agent.sh cold-outreach

# 4. Check the dashboard
# Open http://YOUR_VPS_IP:3100 in your browser

# 5. Check logs
ls -la logs/
cat logs/cold-outreach-latest.log
```

You should see:
- Agent run logged in `logs/`
- A new row in Supabase `agent_runs` table
- State file written in `state/cold-outreach/last-run.json`

### Step 15: Send Your First Dashboard Message

If using the Paperclip dashboard, open it in your browser and use the chat interface to send a message to the orchestrator. Try:

> "Show me the current agent schedule and last run status."

The orchestrator will respond with the state of all agents and their next scheduled runs.

---

## Troubleshooting

### "Agent isn't running"

1. Check crontab is set up:
   ```bash
   crontab -l
   ```
   If empty, re-run `./lib/autopilot.sh start`.

2. Check agent logs:
   ```bash
   cat logs/cold-outreach-latest.log
   ```

3. Verify Claude Code is authenticated:
   ```bash
   claude auth status
   ```

4. Make sure scripts are executable:
   ```bash
   chmod +x lib/*.sh triggers/*.sh
   ```

### "Dashboard shows no data"

1. Verify Supabase credentials in `.env`:
   ```bash
   source .env
   echo $SUPABASE_URL
   echo $SUPABASE_ANON_KEY
   ```

2. Check that Supabase Realtime is enabled:
   - Go to Supabase Dashboard > Database > Replication
   - Ensure the tables are in the "Source" list

3. Run a manual agent to generate data:
   ```bash
   ./lib/run-agent.sh cold-outreach
   ```

4. Check browser console for connection errors (F12 > Console tab).

### "Claude errors / API failures"

1. Check your API key is valid:
   ```bash
   claude auth status
   ```

2. Check your Anthropic usage at https://console.anthropic.com/settings/billing
   - Verify you have credits remaining
   - Check you have not hit rate limits

3. Check token limits in `config/thresholds.json`:
   ```bash
   cat config/thresholds.json
   ```
   If agents are running into token limits, increase `max_tokens_per_run`.

4. Re-authenticate if needed:
   ```bash
   claude auth
   ```

### "Memory not persisting between runs"

1. Verify Supabase connection:
   ```bash
   source .env
   curl -s "$SUPABASE_URL/rest/v1/memories?select=count" \
     -H "apikey: $SUPABASE_ANON_KEY" \
     -H "Authorization: Bearer $SUPABASE_ANON_KEY"
   ```

2. Check that `lib/memory.sh` is being sourced in agent runs:
   ```bash
   grep -l "memory.sh" agents/*.md
   ```

3. Check local state files exist:
   ```bash
   ls -la state/*/last-run.json
   ```

4. Re-run database setup if tables are missing:
   ```bash
   ./lib/setup-supabase.sh
   ```

### "Emails not sending / stuck in drafts"

This is by design in V1. All emails are created as **Gmail drafts** for human review. To send:

1. Open Gmail for your outreach account
2. Go to Drafts
3. Review each draft the agent created
4. Send or discard manually

If you want automated sending, set up SmartLead integration (see `SMARTLEAD_API_KEY` in `.env`).

---

## Updating

To pull the latest version:

```bash
cd ~/gtm-company
git pull origin main
```

Then re-run database migrations if needed:

```bash
./lib/setup-supabase.sh
```

---

## Getting Help

- Check `logs/` for detailed agent execution logs
- Review `state/` for the last known state of each agent
- Open your Supabase Dashboard to inspect raw data
- File issues at https://github.com/jbellsolutions/gtm-company/issues
