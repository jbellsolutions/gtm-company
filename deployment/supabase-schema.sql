-- ============================================================
-- operations-core — Base Supabase Schema
-- Run this in your Supabase SQL editor for any new project.
--
-- What's included:
--   1. entities          — the primary tracked record (clients, projects, etc.)
--   2. entity_events     — pipeline stage change history
--   3. entity_outputs    — deliverables / files per entity
--   4. agent_conversations — Morgan's per-user memory (from agent-core)
--   5. agent_run_log     — Operations tab activity feed
--   6. agent_upsell_log  — Upsell signal tracking
--
-- After running this, rename "entities" if your domain uses a
-- different name (e.g. "clients", "projects", "campaigns").
-- Update DOMAIN.entityTable in dashboard/lib/domain.ts to match.
-- ============================================================

-- ── Enable UUID extension ─────────────────────────────────────
create extension if not exists "uuid-ossp";


-- ── 1. entities ───────────────────────────────────────────────
-- The primary record for your domain. Rename to match your use case.
-- Common alternatives: clients, projects, campaigns, bookings

create table if not exists entities (
  id            uuid primary key default uuid_generate_v4(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- Identity
  name          text not null,
  company       text,
  email         text,
  phone         text,

  -- Pipeline
  stage         text not null default 'call_booked',
  tier          text,
  team_size     int,
  industry      text,
  notes         text,

  -- Extensible — add domain-specific columns here
  metadata      jsonb default '{}'
);

-- Auto-update updated_at
create or replace function update_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger entities_updated_at
  before update on entities
  for each row execute function update_updated_at();

-- Indexes
create index if not exists idx_entities_stage on entities(stage);
create index if not exists idx_entities_created_at on entities(created_at desc);


-- ── 2. entity_events ─────────────────────────────────────────
-- Pipeline history — one row per stage change or notable event

create table if not exists entity_events (
  id            uuid primary key default uuid_generate_v4(),
  created_at    timestamptz not null default now(),
  entity_id     uuid references entities(id) on delete cascade,
  event_type    text not null default 'stage_change',  -- stage_change | note | milestone
  from_stage    text,
  to_stage      text,
  note          text
);

create index if not exists idx_entity_events_entity_id on entity_events(entity_id);
create index if not exists idx_entity_events_created_at on entity_events(created_at desc);


-- ── 3. entity_outputs ────────────────────────────────────────
-- Deliverables / generated files per entity

create table if not exists entity_outputs (
  id            uuid primary key default uuid_generate_v4(),
  created_at    timestamptz not null default now(),
  client_id     uuid references entities(id) on delete cascade,  -- named client_id for agent-core compat
  output_type   text not null,   -- e.g. 'custom_course', 'sow_nda', 'roi_report'
  file_path     text,            -- relative path in the outputs/ directory
  content       text,            -- inline content (for short outputs)
  approved      boolean not null default false,
  approved_at   timestamptz,
  metadata      jsonb default '{}'
);

create index if not exists idx_entity_outputs_client_id on entity_outputs(client_id);
create index if not exists idx_entity_outputs_approved on entity_outputs(approved);


-- ── 4. agent_conversations ───────────────────────────────────
-- Morgan's memory — one row per user per agent, holds full history as JSON

create table if not exists agent_conversations (
  id            uuid primary key default uuid_generate_v4(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  user_id       text not null,     -- Slack user ID
  agent_name    text not null,     -- e.g. 'morgan'
  history       jsonb not null default '[]',
  metadata      jsonb default '{}'
);

create unique index if not exists idx_agent_conversations_user_agent
  on agent_conversations(user_id, agent_name);

create trigger agent_conversations_updated_at
  before update on agent_conversations
  for each row execute function update_updated_at();


-- ── 5. agent_run_log ─────────────────────────────────────────
-- Activity feed shown in the Operations tab

create table if not exists agent_run_log (
  id            uuid primary key default uuid_generate_v4(),
  created_at    timestamptz not null default now(),
  agent_name    text,
  action        text not null,     -- human-readable: "Sent ROI report to Acme Corp"
  client_id     uuid references entities(id) on delete set null,
  details       jsonb default '{}',  -- agent-core writes structured data here
  metadata      jsonb default '{}'
);

create index if not exists idx_agent_run_log_created_at on agent_run_log(created_at desc);
create index if not exists idx_agent_run_log_action on agent_run_log(action);


-- ── 6. agent_upsell_log ──────────────────────────────────────
-- Upsell signal tracking with cooldown management

create table if not exists agent_upsell_log (
  id            uuid primary key default uuid_generate_v4(),
  posted_at     timestamptz not null default now(),
  client_id     uuid references entities(id) on delete cascade,
  signal_type   text not null,     -- e.g. 'roi_threshold', '30_day_win', 'team_growth'
  message       text,
  actioned      boolean not null default false,
  actioned_at   timestamptz,
  action_taken  text            -- description of what was done (written by supabase_tools.log_upsell_action)
);

create index if not exists idx_agent_upsell_log_actioned on agent_upsell_log(actioned);
create index if not exists idx_agent_upsell_log_client_id on agent_upsell_log(client_id);


-- ── Row-Level Security ────────────────────────────────────────
-- Dashboard uses the service role key (bypasses RLS).
-- Enable RLS but keep service role unrestricted for server components.

alter table entities enable row level security;
alter table entity_events enable row level security;
alter table entity_outputs enable row level security;
alter table agent_conversations enable row level security;
alter table agent_run_log enable row level security;
alter table agent_upsell_log enable row level security;

-- Service role bypasses all RLS automatically — no policy needed.
-- If you add client-side anon access, add policies here.
