-- GTM Company Metrics Dashboard Queries
-- Run in Supabase SQL Editor or call via REST API
-- Replace 'YOUR_PROJECT_ID' with your actual project_id

-- ============================================================
-- 1. Weekly KPIs (emails sent, replies, meetings, leads by channel)
-- ============================================================
SELECT
  date_trunc('week', created_at) AS week,
  COUNT(*) FILTER (WHERE status IN ('contacted')) AS emails_sent,
  COUNT(*) FILTER (WHERE status = 'replied') AS replies,
  COUNT(*) FILTER (WHERE status = 'meeting_booked') AS meetings_booked,
  COUNT(*) FILTER (WHERE status = 'qualified') AS qualified_leads,
  COUNT(*) FILTER (WHERE status = 'customer') AS new_customers,
  source AS channel,
  ROUND(
    COUNT(*) FILTER (WHERE status = 'replied')::numeric /
    NULLIF(COUNT(*) FILTER (WHERE status IN ('contacted')), 0) * 100, 1
  ) AS reply_rate_pct
FROM contacts
WHERE project_id = 'YOUR_PROJECT_ID'
  AND created_at >= now() - interval '8 weeks'
GROUP BY week, source
ORDER BY week DESC, source;


-- ============================================================
-- 2. Cost per lead by channel
-- ============================================================
WITH channel_costs AS (
  SELECT
    c.source AS channel,
    COUNT(DISTINCT c.id) AS total_leads,
    COUNT(DISTINCT c.id) FILTER (WHERE c.status IN ('qualified', 'meeting_booked', 'customer')) AS qualified_leads,
    COALESCE(SUM(ar.cost_cents), 0) AS total_cost_cents
  FROM contacts c
  LEFT JOIN agent_runs ar ON ar.project_id = c.project_id
    AND ar.agent_id = CASE
      WHEN c.source = 'cold_email' THEN 'cold-outreach'
      WHEN c.source = 'linkedin' THEN 'linkedin-engage'
      ELSE ar.agent_id
    END
    AND ar.status = 'succeeded'
    AND ar.created_at >= now() - interval '30 days'
  WHERE c.project_id = 'YOUR_PROJECT_ID'
    AND c.created_at >= now() - interval '30 days'
  GROUP BY c.source
)
SELECT
  channel,
  total_leads,
  qualified_leads,
  total_cost_cents,
  CASE WHEN total_leads > 0
    THEN ROUND(total_cost_cents::numeric / total_leads, 2)
    ELSE 0
  END AS cost_per_lead_cents,
  CASE WHEN qualified_leads > 0
    THEN ROUND(total_cost_cents::numeric / qualified_leads, 2)
    ELSE 0
  END AS cost_per_qualified_lead_cents
FROM channel_costs
ORDER BY cost_per_lead_cents ASC;


-- ============================================================
-- 3. Pipeline funnel
--    new -> contacted -> replied -> qualified -> meeting_booked -> customer
-- ============================================================
SELECT
  status,
  COUNT(*) AS count,
  ROUND(
    COUNT(*)::numeric / NULLIF(SUM(COUNT(*)) OVER (), 0) * 100, 1
  ) AS pct_of_total,
  ROUND(
    COUNT(*)::numeric / NULLIF(LAG(COUNT(*)) OVER (
      ORDER BY ARRAY_POSITION(
        ARRAY['new', 'researched', 'contacted', 'replied', 'qualified', 'meeting_booked', 'customer'],
        status
      )
    ), 0) * 100, 1
  ) AS conversion_from_prev_pct
FROM contacts
WHERE project_id = 'YOUR_PROJECT_ID'
  AND status NOT IN ('lost', 'do_not_contact')
GROUP BY status
ORDER BY ARRAY_POSITION(
  ARRAY['new', 'researched', 'contacted', 'replied', 'qualified', 'meeting_booked', 'customer'],
  status
);


-- ============================================================
-- 4. Agent health (runs per agent, success rate, avg duration)
-- ============================================================
SELECT
  agent_id,
  COUNT(*) AS total_runs,
  COUNT(*) FILTER (WHERE status = 'succeeded') AS succeeded,
  COUNT(*) FILTER (WHERE status = 'failed') AS failed,
  COUNT(*) FILTER (WHERE status = 'timeout') AS timeouts,
  ROUND(
    COUNT(*) FILTER (WHERE status = 'succeeded')::numeric /
    NULLIF(COUNT(*), 0) * 100, 1
  ) AS success_rate_pct,
  ROUND(
    AVG(EXTRACT(EPOCH FROM (ended_at - started_at)))::numeric, 1
  ) AS avg_duration_seconds,
  SUM(token_usage) AS total_tokens,
  SUM(cost_cents) AS total_cost_cents,
  MAX(started_at) AS last_run_at
FROM agent_runs
WHERE project_id = 'YOUR_PROJECT_ID'
  AND created_at >= now() - interval '7 days'
GROUP BY agent_id
ORDER BY total_runs DESC;


-- ============================================================
-- 5. Top performing email angles (from episodes)
-- ============================================================
SELECT
  e.data->>'subject_line' AS subject_line,
  e.data->>'email_angle' AS angle,
  COUNT(*) AS times_used,
  COUNT(*) FILTER (WHERE e.outcome = 'positive') AS positive_outcomes,
  COUNT(*) FILTER (WHERE e.outcome = 'negative') AS negative_outcomes,
  ROUND(
    COUNT(*) FILTER (WHERE e.outcome = 'positive')::numeric /
    NULLIF(COUNT(*), 0) * 100, 1
  ) AS positive_rate_pct,
  jsonb_agg(DISTINCT e.learnings) FILTER (WHERE e.outcome = 'positive') AS winning_learnings
FROM episodes e
WHERE e.project_id = 'YOUR_PROJECT_ID'
  AND e.agent_id = 'cold-outreach'
  AND e.event_type IN ('email_sent', 'email_reply_received')
  AND e.created_at >= now() - interval '30 days'
GROUP BY e.data->>'subject_line', e.data->>'email_angle'
HAVING COUNT(*) >= 3
ORDER BY positive_rate_pct DESC
LIMIT 20;


-- ============================================================
-- 6. LinkedIn engagement trends
-- ============================================================
SELECT
  date_trunc('week', e.created_at) AS week,
  e.event_type,
  COUNT(*) AS total_events,
  COUNT(*) FILTER (WHERE e.outcome = 'positive') AS positive,
  COUNT(*) FILTER (WHERE e.outcome = 'negative') AS negative,
  COUNT(*) FILTER (WHERE e.outcome = 'neutral') AS neutral,
  ROUND(
    COUNT(*) FILTER (WHERE e.outcome = 'positive')::numeric /
    NULLIF(COUNT(*), 0) * 100, 1
  ) AS positive_rate_pct
FROM episodes e
WHERE e.project_id = 'YOUR_PROJECT_ID'
  AND e.agent_id = 'linkedin-engage'
  AND e.created_at >= now() - interval '8 weeks'
GROUP BY week, e.event_type
ORDER BY week DESC, e.event_type;


-- ============================================================
-- 7. Quick summary (single row for dashboard header)
-- ============================================================
SELECT
  (SELECT COUNT(*) FROM contacts WHERE project_id = 'YOUR_PROJECT_ID' AND created_at >= now() - interval '7 days') AS new_contacts_7d,
  (SELECT COUNT(*) FROM contacts WHERE project_id = 'YOUR_PROJECT_ID' AND status = 'replied' AND updated_at >= now() - interval '7 days') AS replies_7d,
  (SELECT COUNT(*) FROM contacts WHERE project_id = 'YOUR_PROJECT_ID' AND status = 'meeting_booked' AND updated_at >= now() - interval '7 days') AS meetings_7d,
  (SELECT COUNT(*) FROM agent_runs WHERE project_id = 'YOUR_PROJECT_ID' AND created_at >= now() - interval '7 days') AS agent_runs_7d,
  (SELECT SUM(cost_cents) FROM agent_runs WHERE project_id = 'YOUR_PROJECT_ID' AND created_at >= now() - interval '7 days') AS total_cost_cents_7d,
  (SELECT COUNT(*) FROM agent_runs WHERE project_id = 'YOUR_PROJECT_ID' AND status = 'failed' AND created_at >= now() - interval '7 days') AS failed_runs_7d;
