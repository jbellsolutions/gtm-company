-- GTM Company — Agent Messages Table (Inter-Agent Communication)
-- Run this in Supabase SQL Editor AFTER supabase-migration.sql
-- Version: 2.0.0

-- ============================================================
-- 5. Agent Messages (inter-agent communication queue)
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id text NOT NULL,
  from_agent text NOT NULL,
  to_agent text,              -- null = broadcast to all agents
  message_type text NOT NULL,  -- task_complete, lead_found, escalation, strategy_update, health_alert, instruction
  payload jsonb NOT NULL DEFAULT '{}',
  status text DEFAULT 'unread' CHECK (status IN ('unread', 'read', 'processed', 'archived')),
  priority text DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  created_at timestamptz DEFAULT now(),
  processed_at timestamptz,
  processed_by text
);

CREATE INDEX idx_messages_to ON agent_messages(project_id, to_agent, status);
CREATE INDEX idx_messages_type ON agent_messages(project_id, message_type);
CREATE INDEX idx_messages_created ON agent_messages(created_at DESC);
CREATE INDEX idx_messages_priority ON agent_messages(project_id, priority, status);

ALTER TABLE agent_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all for agent_messages" ON agent_messages FOR ALL USING (true);

ALTER PUBLICATION supabase_realtime ADD TABLE agent_messages;
