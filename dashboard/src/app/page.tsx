'use client';

// ─── Supabase Realtime Requirement ─────────────────────────────────────────
// Ensure these tables have Realtime enabled:
//   ALTER PUBLICATION supabase_realtime ADD TABLE agent_status;
//   ALTER PUBLICATION supabase_realtime ADD TABLE agent_runs;
//   ALTER PUBLICATION supabase_realtime ADD TABLE episodes;
//   ALTER PUBLICATION supabase_realtime ADD TABLE contacts;
//   ALTER PUBLICATION supabase_realtime ADD TABLE agent_messages;
//   ALTER PUBLICATION supabase_realtime ADD TABLE campaign_stats;
// ────────────────────────────────────────────────────────────────────────────

import { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import Link from 'next/link';

// ─── Types ───────────────────────────────────────────────────────────────────

interface AgentStatus {
  id: string;
  project_id: string;
  agent_id: string;
  status: 'running' | 'idle' | 'error' | 'disabled';
  last_run_at: string | null;
  next_run_at: string | null;
  last_run_status: string | null;
  last_run_outputs: Record<string, any> | null;
  error_message: string | null;
  run_count: number;
  consecutive_failures: number;
  updated_at: string;
}

interface AgentRun {
  id: string;
  agent_id: string;
  status: string;
  outputs: Record<string, any> | null;
  cost_cents: number | null;
  created_at: string;
}

interface Episode {
  id: string;
  agent_id: string;
  event_type: string;
  description: string;
  created_at: string;
}

interface CampaignStat {
  id: string;
  campaign_name: string;
  status: string;
  sent: number;
  opens: number;
  replies: number;
  bounces: number;
  reply_rate: number;
  updated_at: string;
}

// ─── Constants ───────────────────────────────────────────────────────────────

const AGENTS = [
  { name: 'orchestrator', label: 'Orchestrator', icon: '~' },
  { name: 'cold-outreach', label: 'Cold Outreach', icon: 'E' },
  { name: 'linkedin-engage', label: 'LinkedIn Engage', icon: 'L' },
  { name: 'lead-router', label: 'Lead Router', icon: 'R' },
  { name: 'content-strategist', label: 'Content Strategist', icon: 'C' },
  { name: 'weekly-strategist', label: 'Weekly Strategist', icon: 'W' },
  { name: 'power-partnerships', label: 'Power Partnerships', icon: 'P' },
  { name: 'content-engine', label: 'Content Engine', icon: 'N' },
];

// ─── Helpers ─────────────────────────────────────────────────────────────────

function timeAgo(dateStr: string | null): string {
  if (!dateStr) return 'Never';
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'Just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days}d ago`;
}

function formatTime(dateStr: string | null): string {
  if (!dateStr) return '--';
  return new Date(dateStr).toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
  });
}

function statusColor(status: string): string {
  switch (status) {
    case 'running': return 'var(--accent-blue)';
    case 'idle': return 'var(--accent-green)';
    case 'error': return 'var(--accent-red)';
    case 'disabled': return 'var(--text-muted)';
    default: return 'var(--text-secondary)';
  }
}

function statusBg(status: string): string {
  switch (status) {
    case 'running': return 'var(--accent-blue-dim)';
    case 'idle': return 'var(--accent-green-dim)';
    case 'error': return 'var(--accent-red-dim)';
    default: return 'rgba(85,85,85,0.12)';
  }
}

function overallHealth(agents: AgentStatus[]): 'green' | 'yellow' | 'red' {
  if (agents.length === 0) return 'yellow';
  const hasError = agents.some(a => a.status === 'error');
  if (hasError) return 'red';
  const hasWarning = agents.some(a => {
    if (!a.next_run_at) return false;
    return new Date(a.next_run_at).getTime() - Date.now() < 0;
  });
  if (hasWarning) return 'yellow';
  return 'green';
}

// ─── Main Component ──────────────────────────────────────────────────────────

export default function OverviewPage() {
  const [agents, setAgents] = useState<AgentStatus[]>([]);
  const [campaigns, setCampaigns] = useState<CampaignStat[]>([]);
  const [activity, setActivity] = useState<(AgentRun | Episode | any)[]>([]);
  const [meetingsBooked, setMeetingsBooked] = useState(0);
  const [pipelineCount, setPipelineCount] = useState(0);
  const [lastSyncTimes, setLastSyncTimes] = useState<Record<string, string | null>>({
    agents: null,
    campaigns: null,
    activity: null,
    contacts: null,
  });

  // ── Data fetching ──────────────────────────────────────────────────────────

  const fetchAgents = useCallback(async () => {
    const { data } = await supabase
      .from('agent_status')
      .select('id, project_id, agent_id, status, last_run_at, next_run_at, last_run_status, last_run_outputs, error_message, run_count, consecutive_failures, updated_at')
      .order('agent_id');
    if (data) {
      setAgents(data);
      setLastSyncTimes(prev => ({ ...prev, agents: new Date().toISOString() }));
    }
  }, []);

  const fetchCampaigns = useCallback(async () => {
    const { data } = await supabase
      .from('campaign_stats')
      .select('id, campaign_name, status, sent, opens, replies, bounces, reply_rate, updated_at')
      .order('updated_at', { ascending: false });
    if (data) {
      setCampaigns(data);
      setLastSyncTimes(prev => ({ ...prev, campaigns: data[0]?.updated_at || new Date().toISOString() }));
    }
  }, []);

  const fetchActivity = useCallback(async () => {
    const [runsRes, episodesRes] = await Promise.all([
      supabase.from('agent_runs').select('id, agent_id, status, outputs, cost_cents, created_at').order('created_at', { ascending: false }).limit(15),
      supabase.from('episodes').select('id, agent_id, event_type, description, created_at').order('created_at', { ascending: false }).limit(15),
    ]);

    const runs = (runsRes.data || []).map(r => ({ ...r, _type: 'run' }));
    const episodes = (episodesRes.data || []).map(e => ({ ...e, _type: 'episode' }));
    const combined = [...runs, ...episodes]
      .sort((a, b) => new Date(b.created_at || '').getTime() - new Date(a.created_at || '').getTime())
      .slice(0, 20);
    setActivity(combined);
    setLastSyncTimes(prev => ({ ...prev, activity: new Date().toISOString() }));
  }, []);

  const fetchContacts = useCallback(async () => {
    const { data } = await supabase
      .from('contacts')
      .select('status');
    if (data) {
      const meetings = data.filter((c: { status: string }) =>
        c.status?.toLowerCase().replace(/\s+/g, '_') === 'meeting_booked'
      ).length;
      const active = data.filter((c: { status: string }) => {
        const s = c.status?.toLowerCase().replace(/\s+/g, '_') || '';
        return ['contacted', 'replied', 'qualified', 'meeting_booked'].includes(s);
      }).length;
      setMeetingsBooked(meetings);
      setPipelineCount(active);
      setLastSyncTimes(prev => ({ ...prev, contacts: new Date().toISOString() }));
    }
  }, []);

  // ── Subscriptions ──────────────────────────────────────────────────────────

  useEffect(() => {
    fetchAgents();
    fetchCampaigns();
    fetchActivity();
    fetchContacts();

    const agentSub = supabase
      .channel('overview-agent-status')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'agent_status' }, () => fetchAgents())
      .subscribe();

    const runsSub = supabase
      .channel('overview-agent-runs')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'agent_runs' }, () => fetchActivity())
      .subscribe();

    const episodeSub = supabase
      .channel('overview-episodes')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'episodes' }, () => fetchActivity())
      .subscribe();

    const contactSub = supabase
      .channel('overview-contacts')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'contacts' }, () => fetchContacts())
      .subscribe();

    const campaignSub = supabase
      .channel('overview-campaigns')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'campaign_stats' }, () => fetchCampaigns())
      .subscribe();

    return () => {
      supabase.removeChannel(agentSub);
      supabase.removeChannel(runsSub);
      supabase.removeChannel(episodeSub);
      supabase.removeChannel(contactSub);
      supabase.removeChannel(campaignSub);
    };
  }, [fetchAgents, fetchCampaigns, fetchActivity, fetchContacts]);

  // ── Derived ────────────────────────────────────────────────────────────────

  const health = overallHealth(agents);
  const healthColors: Record<string, string> = {
    green: 'var(--accent-green)',
    yellow: 'var(--accent-yellow)',
    red: 'var(--accent-red)',
  };
  const healthLabels: Record<string, string> = {
    green: 'All Systems Operational',
    yellow: 'Warning',
    red: 'System Error',
  };
  const totalSent = campaigns.reduce((s, c) => s + c.sent, 0);
  const totalReplies = campaigns.reduce((s, c) => s + c.replies, 0);

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <main style={{ padding: '24px', maxWidth: 1400, margin: '0 auto' }}>

      {/* ── Header Bar ───────────────────────────────────────────────────── */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        marginBottom: 24,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <div>
            <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-0.02em' }}>
              GTM Command Center
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              AI Integrators
            </div>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: 'var(--text-secondary)' }}>
            <div className={`status-dot status-dot-${health}`} />
            {healthLabels[health]}
          </div>
          <span className="last-synced">
            Data synced {timeAgo(lastSyncTimes.campaigns)}
          </span>
        </div>
      </div>

      {/* ── Top KPI Row ──────────────────────────────────────────────────── */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(4, 1fr)',
        gap: 16,
        marginBottom: 24,
      }}>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-blue)' }}>
            {totalSent.toLocaleString()}
          </div>
          <div className="kpi-label">Total Emails Sent</div>
          <span className="last-synced">Synced {timeAgo(lastSyncTimes.campaigns)}</span>
        </div>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-green)' }}>
            {totalReplies}
          </div>
          <div className="kpi-label">Total Replies</div>
          <span className="last-synced">Synced {timeAgo(lastSyncTimes.campaigns)}</span>
        </div>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-yellow)' }}>
            {meetingsBooked}
          </div>
          <div className="kpi-label">Meetings Booked</div>
          <span className="last-synced">Synced {timeAgo(lastSyncTimes.contacts)}</span>
        </div>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-purple)' }}>
            {pipelineCount}
          </div>
          <div className="kpi-label">Pipeline (Active)</div>
          <span className="last-synced">Synced {timeAgo(lastSyncTimes.contacts)}</span>
        </div>
      </div>

      {/* ── Agent Status Grid ────────────────────────────────────────────── */}
      <section style={{ marginBottom: 24 }}>
        <div className="section-header">
          <div className="section-title">Agent Status</div>
          <span className="last-synced">Synced {timeAgo(lastSyncTimes.agents)}</span>
        </div>
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
          gap: 12,
        }}>
          {AGENTS.map(agentDef => {
            const agent = agents.find(a => a.agent_id === agentDef.name);
            const status = agent?.status || 'idle';
            const isOrchestrator = agentDef.name === 'orchestrator';

            return (
              <div key={agentDef.name} style={{
                background: 'var(--bg-card)',
                border: `1px solid ${status === 'error' ? 'var(--accent-red)' : 'var(--border)'}`,
                borderRadius: 'var(--radius-lg)',
                padding: 16,
                animation: 'fadeIn 0.3s ease',
              }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <div style={{
                      width: 28, height: 28, borderRadius: 6,
                      background: isOrchestrator
                        ? 'linear-gradient(135deg, var(--accent-blue), var(--accent-purple))'
                        : 'var(--bg-input)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 12, fontWeight: 600,
                      color: isOrchestrator ? 'white' : 'var(--text-secondary)',
                      fontFamily: 'var(--font-mono)',
                    }}>
                      {agentDef.icon}
                    </div>
                    <span style={{ fontSize: 13, fontWeight: 500 }}>{agentDef.label}</span>
                  </div>
                  <div style={{
                    padding: '2px 8px', borderRadius: 20,
                    fontSize: 11, fontWeight: 500,
                    color: statusColor(status), background: statusBg(status),
                    textTransform: 'capitalize',
                  }}>
                    {status === 'running' && (
                      <span style={{ display: 'inline-block', width: 6, height: 6, borderRadius: '50%', background: statusColor(status), marginRight: 4, animation: 'pulse 1.5s infinite' }} />
                    )}
                    {status}
                  </div>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11 }}>
                    <span style={{ color: 'var(--text-muted)' }}>Last run</span>
                    <span style={{ color: 'var(--text-secondary)' }}>{timeAgo(agent?.last_run_at || null)}</span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11 }}>
                    <span style={{ color: 'var(--text-muted)' }}>Next run</span>
                    <span style={{ color: 'var(--text-secondary)' }}>{agent?.next_run_at ? formatTime(agent.next_run_at) : '--'}</span>
                  </div>
                  {agent?.error_message && (
                    <div style={{
                      marginTop: 4, padding: '4px 8px',
                      background: 'var(--accent-red-dim)', borderRadius: 4,
                      fontSize: 11, color: 'var(--accent-red)',
                      whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                    }}>
                      {agent.error_message}
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* ── Cold Email Summary (compact) ─────────────────────────────────── */}
      {campaigns.length > 0 && (
        <section style={{ marginBottom: 24 }}>
          <div className="section-header">
            <div className="section-title">Cold Email Campaigns</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <span className="last-synced">Synced {timeAgo(lastSyncTimes.campaigns)}</span>
              <Link href="/emails" style={{ fontSize: 12, color: 'var(--accent-blue)', textDecoration: 'none' }}>
                View All
              </Link>
            </div>
          </div>
          <div style={{
            background: 'var(--bg-card)',
            border: '1px solid var(--border)',
            borderRadius: 'var(--radius-lg)',
            overflow: 'hidden',
          }}>
            <table className="campaign-table">
              <thead>
                <tr>
                  <th>Campaign</th>
                  <th>Sent</th>
                  <th>Replies</th>
                  <th>Reply Rate</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {campaigns.slice(0, 6).map(c => {
                  const replyRate = c.sent > 0 ? ((c.replies / c.sent) * 100).toFixed(1) : '0.0';
                  const isActive = c.status === 'active' || c.status === 'STARTED';
                  return (
                    <tr key={c.id}>
                      <td style={{ color: 'var(--text-primary)', fontWeight: 500 }}>
                        {c.campaign_name}
                      </td>
                      <td className="mono">{c.sent.toLocaleString()}</td>
                      <td className="mono" style={{ color: 'var(--accent-green)' }}>{c.replies}</td>
                      <td className="mono" style={{
                        color: parseFloat(replyRate) > 2 ? 'var(--accent-green)' : parseFloat(replyRate) > 1 ? 'var(--accent-yellow)' : 'var(--accent-red)',
                      }}>{replyRate}%</td>
                      <td>
                        <span style={{
                          padding: '2px 8px', borderRadius: 20, fontSize: 11, fontWeight: 500,
                          color: isActive ? 'var(--accent-green)' : 'var(--text-muted)',
                          background: isActive ? 'var(--accent-green-dim)' : 'rgba(85,85,85,0.12)',
                          textTransform: 'capitalize',
                        }}>
                          {c.status}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {/* ── Activity Feed ─────────────────────────────────────────────────── */}
      <section style={{
        background: 'var(--bg-card)',
        border: '1px solid var(--border)',
        borderRadius: 'var(--radius-lg)',
        padding: 20,
      }}>
        <div className="section-header">
          <div className="section-title">Recent Activity</div>
          <span className="last-synced">Synced {timeAgo(lastSyncTimes.activity)}</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          {activity.length === 0 && (
            <div style={{ padding: '32px 0', textAlign: 'center', color: 'var(--text-muted)', fontSize: 13 }}>
              No activity yet. Agents will populate this feed as they run.
            </div>
          )}
          {activity.map((item, i) => {
            const isRun = item._type === 'run';
            const timestamp = item.created_at;
            const agentName = item.agent_id || 'system';
            const actionText = isRun
              ? `${item.status || 'run'}${item.cost_cents ? ` ($${(item.cost_cents / 100).toFixed(2)})` : ''}`
              : `${item.event_type || 'event'}`;
            const outcome = isRun
              ? (item.outputs ? Object.entries(item.outputs).map(([k, v]) => `${k}: ${v}`).join(', ') : item.status || '')
              : (item.description || '');

            return (
              <div key={`${i}-${item.id}`} style={{
                display: 'flex', alignItems: 'flex-start', gap: 12,
                padding: '10px 0',
                borderBottom: i < activity.length - 1 ? '1px solid var(--border)' : 'none',
              }}>
                <div style={{
                  width: 6, height: 6, borderRadius: '50%',
                  background: isRun ? 'var(--accent-blue)' : 'var(--accent-purple)',
                  marginTop: 6, flexShrink: 0,
                }} />
                <div style={{ fontSize: 12, color: 'var(--text-muted)', width: 52, flexShrink: 0, fontFamily: 'var(--font-mono)' }}>
                  {formatTime(timestamp)}
                </div>
                <div style={{
                  fontSize: 12, fontWeight: 500,
                  color: 'var(--accent-blue)',
                  width: 100, flexShrink: 0,
                }}>
                  {agentName}
                </div>
                <div style={{ fontSize: 12, color: 'var(--text-secondary)', fontFamily: 'var(--font-mono)' }}>
                  {actionText}
                </div>
                <div style={{
                  fontSize: 12, color: 'var(--text-muted)',
                  flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                }}>
                  {outcome}
                </div>
              </div>
            );
          })}
        </div>
      </section>
    </main>
  );
}
