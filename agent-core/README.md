# agent-core

> A persistent, living AI agent framework. Drop a transcript in Slack. The agent takes it from there.

Built by AI Integraterz. MIT License.

---

## What This Is

**agent-core** is the scaffolding that turns a Claude model into a real, persistent agent with:

- **Identity** — a name, voice, title, and system prompt. Sounds like a person, not a chatbot.
- **Memory** — every conversation continues where it left off. No starting fresh.
- **Tools** — real function calls: create clients, run agents, post to Slack, read pipeline state.
- **Heartbeat** — runs on a configurable interval (default 30 min). Checks state. Acts if needed. Sends morning/evening briefs.
- **Slack integration** — listens for messages, @mentions, and file uploads. Responds with the agent's voice.

**The design principle:** You should be able to talk to this agent the same way you'd talk to a sharp operator on your team. Drop a transcript and walk away. It handles the pipeline.

---

## Included Identities

| File | Agent | Role |
|------|-------|------|
| `identities/head-of-operations.json` | Morgan | Runs the AI Integraterz client pipeline |
| `identities/coo-template.json` | Alex | Executive view across multiple Heads |
| `identities/gtm-agent-template.json` | Jordan | Go-to-market, content, and leads |

**To create a new agent:** copy any identity file, change the name/title/voice/system_prompt, point `IDENTITY_FILE` at it. No code changes needed.

---

## How It Works

```
You drop a transcript in Slack
    ↓
Slack Bolt listener receives the message
    ↓
agent.handle_message() is called
    ↓
Loads your conversation history from Supabase (memory)
    ↓
Sends to Claude with: identity (system prompt) + history + tools
    ↓
Claude calls tools as needed (agentic loop):
    → create_client() → new client in pipeline
    → run_agent("extraction", client_id) → kicks off the build
    → create_slack_channel() → new channel created
    → post_slack_message() → updates posted
    ↓
Final reply sent back in Slack
    ↓
Conversation saved to Supabase for next time
```

Every 30 minutes (configurable):

```
Heartbeat fires
    ↓
Loads pipeline context from Supabase
    ↓
Claude reviews pipeline + decides if anything needs attention
    ↓
If action needed: calls tools, posts to Slack
If 8am: sends morning brief to Justin
If 8pm: sends evening summary
If nothing needed: stays quiet
```

---

## Quick Start

### 1. Clone and install

```bash
git clone https://github.com/jbellsolutions/agent-core.git
cd agent-core
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
```

### 2. Set up environment

```bash
cp .env.example .env
# Fill in: ANTHROPIC_API_KEY, SLACK_BOT_TOKEN, SLACK_APP_TOKEN,
#           SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, JUSTIN_SLACK_USER_ID
```

### 3. Set up Supabase tables

```sql
-- Run deployment/supabase-schema.sql in your Supabase SQL editor
```

### 4. Set up Slack app

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → Create New App → From scratch
2. **Socket Mode** → Enable → Generate App Token (xapp-...) → save as `SLACK_APP_TOKEN`
3. **OAuth & Permissions** → Bot Token Scopes: `channels:manage`, `chat:write`, `files:read`, `groups:write`, `im:history`, `im:write`, `mpim:write`, `reactions:write`, `users:read`
4. Install to workspace → copy Bot Token (xoxb-...) → save as `SLACK_BOT_TOKEN`
5. **Event Subscriptions** → Enable → Subscribe to bot events: `message.channels`, `message.groups`, `message.im`, `message.mpim`, `app_mention`
6. Invite the bot to your `#ai-integraterz-ops` channel

### 5. Start the agent

```bash
python main.py
```

You'll see: `✅ Morgan is online. Heartbeat active every 30 minutes.`

---

## Using a Different Identity

```bash
# COO
IDENTITY_FILE=identities/coo-template.json python main.py

# GTM Agent
IDENTITY_FILE=identities/gtm-agent-template.json python main.py

# Your own identity file
IDENTITY_FILE=identities/my-agent.json python main.py
```

---

## Deploy to DigitalOcean (always-on)

```bash
# Build and push Docker image
docker build -t agent-core -f deployment/Dockerfile .

# Run on droplet (with .env file)
docker run -d --env-file .env --restart always --name morgan agent-core
```

Or use the App Platform — see `deployment/digitalocean-app.yaml`.

---

## Adding New Tools

1. **Implement** the function in `tools/<category>_tools.py`
2. **Register** it in `agent/tools.py` → `_register_implementations()`
3. **Add the schema** to `config/tools.json` in Claude tool-use format

The agent will automatically have access to the new tool on next restart.

---

## Org Chart (AI Integraterz)

```
Justin Bell (CEO)
    └── Alex (COO) — agent-core + coo-template.json
            ├── Morgan (Head of Operations) — agent-core + head-of-operations.json
            │       └── [14 specialist agents in ai-integraterz repo]
            └── Jordan (Head of Growth) — agent-core + gtm-agent-template.json
                    └── [Expert Series, Content Multiplier, GTM Deploy]
```

Each box in this chart is one running instance of agent-core with a different identity file.

---

## Architecture

```
agent-core/
├── main.py                    # Entrypoint — loads identity, starts agent
├── agent/
│   ├── agent.py               # PersistentAgent — heartbeat + message handler + agentic loop
│   ├── identity.py            # Loads identity JSON → system prompt
│   ├── memory.py              # Supabase: conversation history + pipeline context
│   ├── tools.py               # Tool registry — maps names to implementations
│   └── slack_listener.py      # Slack Bolt — listens for messages + file uploads
├── tools/
│   ├── pipeline_tools.py      # create_client, run_agent, get_pipeline_status, etc.
│   ├── slack_tools.py         # post_slack_message, create_slack_channel, dm_user
│   └── supabase_tools.py      # read_client_outputs, get_upsell_signals, etc.
├── config/
│   └── tools.json             # Tool schemas in Claude API format
├── identities/
│   ├── head-of-operations.json
│   ├── coo-template.json
│   └── gtm-agent-template.json
└── deployment/
    ├── Dockerfile
    ├── supabase-schema.sql
    └── digitalocean-app.yaml
```

---

## Relationship to ai-integraterz repo

**agent-core** is the agent runtime. **ai-integraterz** is the playbook library.

- agent-core's `run_agent()` tool calls `ai-integraterz/lib/run-agent.sh`
- The 14 `.md` playbooks in ai-integraterz are the standard operating procedures Morgan follows
- Morgan doesn't read the playbooks directly — she calls `run_agent()` and the right specialist agent executes the playbook

Think of it as: Morgan is the manager, the playbooks are the procedures, the specialist agents are the team.

---

## Built by AI Integraterz
[usingaitoscale.com](https://usingaitoscale.com) · justin@usingaitoscale.com
