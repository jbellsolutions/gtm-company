-- GTM Company Memory Schema
-- Run this in Supabase SQL Editor
-- Version: 1.0.0

-- ============================================================
-- 1. Agent runs (audit trail of every agent execution)
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id text NOT NULL,
  agent_id text NOT NULL,
  started_at timestamptz DEFAULT now(),
  ended_at timestamptz,
  status text DEFAULT 'running' CHECK (status IN ('running', 'succeeded', 'failed', 'timeout')),
  outputs jsonb DEFAULT '{}',
  token_usage integer DEFAULT 0,
  cost_cents integer DEFAULT 0,
  error text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_agent_runs_project ON agent_runs(project_id);
CREATE INDEX idx_agent_runs_agent ON agent_runs(project_id, agent_id);
CREATE INDEX idx_agent_runs_status ON agent_runs(project_id, status);
CREATE INDEX idx_agent_runs_created ON agent_runs(created_at DESC);

-- ============================================================
-- 2. Semantic memories (persistent facts across sessions)
-- ============================================================
CREATE TABLE IF NOT EXISTS memories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id text NOT NULL,
  agent_id text,
  namespace text NOT NULL,
  key text NOT NULL,
  value jsonb NOT NULL,
  confidence float DEFAULT 1.0,
  source text DEFAULT 'agent_observation',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  access_count integer DEFAULT 0,
  UNIQUE(project_id, namespace, key)
);

CREATE INDEX idx_memories_project ON memories(project_id);
CREATE INDEX idx_memories_namespace ON memories(project_id, namespace);
CREATE INDEX idx_memories_agent ON memories(project_id, agent_id);

-- ============================================================
-- 3. Contacts (cross-pipeline deduplication)
-- ============================================================
CREATE TABLE IF NOT EXISTS contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id text NOT NULL,
  email text,
  linkedin_url text,
  name text,
  company text,
  title text,
  status text DEFAULT 'new' CHECK (status IN ('new', 'researched', 'contacted', 'replied', 'qualified', 'meeting_booked', 'customer', 'lost', 'do_not_contact')),
  source text CHECK (source IN ('cold_email', 'linkedin', 'inbound', 'referral', 'manual')),
  channel text,
  first_contact_at timestamptz,
  last_contact_at timestamptz,
  next_action text,
  next_action_at timestamptz,
  data jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(project_id, email)
);

CREATE INDEX idx_contacts_project ON contacts(project_id);
CREATE INDEX idx_contacts_status ON contacts(project_id, status);
CREATE INDEX idx_contacts_source ON contacts(project_id, source);
CREATE INDEX idx_contacts_email ON contacts(project_id, email);
CREATE INDEX idx_contacts_linkedin ON contacts(project_id, linkedin_url);

-- ============================================================
-- 4. Episodic memory (what worked and didn't)
-- ============================================================
CREATE TABLE IF NOT EXISTS episodes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id text NOT NULL,
  agent_id text NOT NULL,
  event_type text NOT NULL,
  description text NOT NULL,
  outcome text CHECK (outcome IN ('positive', 'negative', 'neutral')),
  learnings jsonb DEFAULT '[]',
  data jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_episodes_project ON episodes(project_id);
CREATE INDEX idx_episodes_agent ON episodes(project_id, agent_id);
CREATE INDEX idx_episodes_type ON episodes(project_id, event_type);
CREATE INDEX idx_episodes_outcome ON episodes(project_id, outcome);
CREATE INDEX idx_episodes_created ON episodes(created_at DESC);

-- ============================================================
-- Row Level Security (for future multi-tenant)
-- ============================================================
ALTER TABLE agent_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE episodes ENABLE ROW LEVEL SECURITY;

-- Permissive policies for now (tighten when selling to clients)
CREATE POLICY "Allow all for agent_runs" ON agent_runs FOR ALL USING (true);
CREATE POLICY "Allow all for memories" ON memories FOR ALL USING (true);
CREATE POLICY "Allow all for contacts" ON contacts FOR ALL USING (true);
CREATE POLICY "Allow all for episodes" ON episodes FOR ALL USING (true);

-- Enable Realtime for dashboard subscriptions
ALTER PUBLICATION supabase_realtime ADD TABLE agent_runs, memories, contacts, episodes;
