-- ═══════════════════════════════════════════════════════════════════════════════
-- GTM Company — Supabase Migration V4: Call Center (Retell AI)
-- ═══════════════════════════════════════════════════════════════════════════════
-- Run this after supabase-migration-v3.sql
-- Adds the call_logs table for Retell AI call center integration
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS call_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id text NOT NULL,
  contact_id uuid REFERENCES contacts(id),
  contact_name text,
  contact_phone text,
  call_type text CHECK (call_type IN ('outbound', 'callback', 'voicemail_drop')),
  status text DEFAULT 'queued' CHECK (status IN ('queued', 'ringing', 'connected', 'voicemail', 'completed', 'no_answer', 'failed')),
  duration_seconds integer DEFAULT 0,
  outcome text CHECK (outcome IN ('meeting_booked', 'callback_requested', 'interested', 'not_interested', 'wrong_number', 'no_answer')),
  transcript text,
  recording_url text,
  notes text,
  retell_call_id text,
  created_at timestamptz DEFAULT now(),
  completed_at timestamptz
);

-- Indexes for common queries
CREATE INDEX idx_call_logs_project ON call_logs(project_id);
CREATE INDEX idx_call_logs_status ON call_logs(project_id, status);

-- Row level security
ALTER TABLE call_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all for call_logs" ON call_logs FOR ALL USING (true);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE call_logs;
