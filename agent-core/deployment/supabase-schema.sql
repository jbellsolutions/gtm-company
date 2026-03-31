-- agent-core Supabase tables
-- Run this in your Supabase SQL editor to set up the tables the agent needs.
-- The clients, client_outputs, pipeline_events tables already exist in the hub.
-- This adds the agent-specific tables.

-- Conversation memory: stores full message history per user per agent
CREATE TABLE IF NOT EXISTS agent_conversations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    agent_name TEXT NOT NULL,           -- which agent instance (e.g. 'Morgan')
    user_id TEXT NOT NULL,              -- Slack user ID
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_conversations_lookup
    ON agent_conversations (agent_name, user_id, created_at DESC);

-- Agent run log: every action the agent takes (shown in Operations tab of hub)
CREATE TABLE IF NOT EXISTS agent_run_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    agent_name TEXT NOT NULL,
    action TEXT NOT NULL,               -- human-readable description
    details JSONB DEFAULT '{}',         -- structured data about the action
    client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_run_log_recent
    ON agent_run_log (agent_name, created_at DESC);

-- Upsell log: tracks which upsell signals have been posted (prevents spam)
CREATE TABLE IF NOT EXISTS agent_upsell_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
    signal_type TEXT NOT NULL,          -- e.g. 'build997_to_training_contracts'
    posted_at TIMESTAMPTZ DEFAULT NOW(),
    actioned BOOLEAN DEFAULT FALSE,
    action_taken TEXT                   -- what Justin did about it
);

CREATE INDEX IF NOT EXISTS idx_upsell_log_active
    ON agent_upsell_log (client_id, signal_type, actioned);

-- RLS: service role key bypasses RLS (agent uses service role)
-- If you want the hub to display these, also set up anon/authenticated policies
ALTER TABLE agent_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_run_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_upsell_log ENABLE ROW LEVEL SECURITY;

-- Allow service role full access (agent uses this)
CREATE POLICY "service_role_all" ON agent_conversations
    FOR ALL TO service_role USING (true);
CREATE POLICY "service_role_all" ON agent_run_log
    FOR ALL TO service_role USING (true);
CREATE POLICY "service_role_all" ON agent_upsell_log
    FOR ALL TO service_role USING (true);
