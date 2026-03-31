-- ═══════════════════════════════════════════════════════════════════════════════
-- GTM Company — Supabase Migration V3: SmartLead Campaign Stats
-- ═══════════════════════════════════════════════════════════════════════════════
-- Run this after supabase-migration-v2.sql
-- Adds the campaign_stats table for SmartLead cold email data
-- ═══════════════════════════════════════════════════════════════════════════════

-- Campaign stats table — populated by smartlead.sh sync
CREATE TABLE IF NOT EXISTS campaign_stats (
  id text PRIMARY KEY,
  project_id text NOT NULL,
  campaign_name text NOT NULL,
  campaign_type text DEFAULT 'cold_email',
  status text DEFAULT 'active',
  sent integer DEFAULT 0,
  opens integer DEFAULT 0,
  replies integer DEFAULT 0,
  bounces integer DEFAULT 0,
  unsubscribed integer DEFAULT 0,
  leads_total integer DEFAULT 0,
  leads_contacted integer DEFAULT 0,
  reply_rate float DEFAULT 0,
  sequence_steps jsonb DEFAULT '{}',
  updated_at timestamptz DEFAULT now()
);

-- Index for project-scoped queries
CREATE INDEX IF NOT EXISTS idx_campaign_stats_project ON campaign_stats(project_id);

-- Row level security (permissive for anon reads, service key writes)
ALTER TABLE campaign_stats ENABLE ROW LEVEL SECURITY;

-- Allow reads for anon key (dashboard) and full access for service role
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'campaign_stats' AND policyname = 'Allow all for campaign_stats'
  ) THEN
    CREATE POLICY "Allow all for campaign_stats" ON campaign_stats FOR ALL USING (true);
  END IF;
END $$;

-- Enable realtime subscriptions so the dashboard updates live
ALTER PUBLICATION supabase_realtime ADD TABLE campaign_stats;
