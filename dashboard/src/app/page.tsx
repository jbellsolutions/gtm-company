'use client';

import { useEffect, useState, useRef, useCallback } from 'react';
import { supabase } from '../lib/supabase';

// ─── Types ───────────────────────────────────────────────────────────────────

interface AgentStatus {
  id: string;
  agent_name: string;
  status: 'running' | 'idle' | 'error' | 'disabled';
  last_run_at: string | null;
  next_run_at: string | null;
  last_metric: string | null;
  last_error: string | null;
  updated_at: string;
}

interface AgentRun {
  id: string;
  agent_name: string;
  action: string;
  outcome: string | null;
  cost_usd: number | null;
  started_at: string;
  completed_at: string | null;
  status: string;
}

interface Episode {
  id: string;
  agent_name: string;
  event_type: string;
  summary: string;
  created_at: string;
}

interface PipelineStage {
  stage: string;
  count: number;
}

interface AgentMessage {
  id: string;
  from_agent: string;
  to_agent: string;
  message_type: string;
  content: string;
  created_at: string;
}

interface WeeklyKPIs {
  emails_drafted: number;
  replies_received: number;
  linkedin_posts: number;
  engagement: number;
  meetings_booked: number;
  cost_this_week: number;
  cost_per_lead: number;
}

// ─── Constants ───────────────────────────────────────────────────────────────

const AGENTS = [
  { name: 'orchestrator', label: 'Orchestrator', icon: '~' },
  { name: 'cold-outreach', label: 'Cold Outreach', icon: 'E' },
  { name: 'linkedin-engage', label: 'LinkedIn Engage', icon: 'L' },
  { name: 'lead-router', label: 'Lead Router', icon: 'R' },
  { name: 'content-strategist', label: 'Content Strategist', icon: 'C' },
  { name: 'weekly-strategist', label: 'Weekly Strategist', icon: 'W' },
];

const PIPELINE_STAGES = [
  { key: 'new', label: 'New' },
  { key: 'researched', label: 'Researched' },
  { key: 'contacted', label: 'Contacted' },
  { key: 'replied', label: 'Replied' },
  { key: 'qualified', label: 'Qualified' },
  { key: 'meeting_booked', label: 'Meeting Booked' },
  { key: 'customer', label: 'Customer' },
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

function formatCost(cost: number): string {
  if (cost < 0.01) return '<$0.01';
  return `$${cost.toFixed(2)}`;
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
    const diff = new Date(a.next_run_at).getTime() - Date.now();
    return diff < 0;
  });
  if (hasWarning) return 'yellow';
  return 'green';
}

// ─── Main Component ──────────────────────────────────────────────────────────

export default function Dashboard() {
  const [agents, setAgents] = useState<AgentStatus[]>([]);
  const [pipeline, setPipeline] = useState<PipelineStage[]>([]);
  const [kpis, setKpis] = useState<WeeklyKPIs>({
    emails_drafted: 0, replies_received: 0, linkedin_posts: 0,
    engagement: 0, meetings_booked: 0, cost_this_week: 0, cost_per_lead: 0,
  });
  const [activity, setActivity] = useState<(AgentRun | Episode)[]>([]);
  const [messages, setMessages] = useState<AgentMessage[]>([]);
  const [chatOpen, setChatOpen] = useState(false);
  const [chatInput, setChatInput] = useState('');
  const [sending, setSending] = useState(false);
  const [lastHeartbeat, setLastHeartbeat] = useState<string | null>(null);
  const chatEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // ── Data fetching ──────────────────────────────────────────────────────────

  const fetchAgents = useCallback(async () => {
    const { data } = await supabase
      .from('agent_status')
      .select('*')
      .order('agent_name');
    if (data) {
      setAgents(data);
      const orch = data.find(a => a.agent_name === 'orchestrator');
      if (orch) setLastHeartbeat(orch.updated_at);
    }
  }, []);

  const fetchPipeline = useCallback(async () => {
    const { data } = await supabase
      .from('contacts')
      .select('pipeline_stage');
    if (data) {
      const counts: Record<string, number> = {};
      PIPELINE_STAGES.forEach(s => counts[s.key] = 0);
      data.forEach((row: { pipeline_stage: string }) => {
        const stage = row.pipeline_stage?.toLowerCase().replace(/\s+/g, '_');
        if (stage && counts[stage] !== undefined) counts[stage]++;
      });
      setPipeline(PIPELINE_STAGES.map(s => ({ stage: s.key, count: counts[s.key] || 0 })));
    }
  }, []);

  const fetchKPIs = useCallback(async () => {
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

    const [runsRes, contactsRes] = await Promise.all([
      supabase.from('agent_runs').select('agent_name, action, cost_usd, status').gte('started_at', weekAgo),
      supabase.from('contacts').select('pipeline_stage, replied_at, meeting_booked_at').gte('updated_at', weekAgo),
    ]);

    const runs = runsRes.data || [];
    const contacts = contactsRes.data || [];

    const emailsDrafted = runs.filter(r => r.action?.includes('email') || r.action?.includes('draft')).length;
    const linkedinPosts = runs.filter(r => r.action?.includes('linkedin') || r.action?.includes('post')).length;
    const repliesReceived = contacts.filter(c => c.replied_at).length;
    const meetingsBooked = contacts.filter(c => c.meeting_booked_at).length;
    const totalCost = runs.reduce((sum, r) => sum + (r.cost_usd || 0), 0);
    const leads = contacts.filter(c => ['qualified', 'meeting_booked', 'customer'].includes(c.pipeline_stage?.toLowerCase().replace(/\s+/g, '_') || '')).length;

    setKpis({
      emails_drafted: emailsDrafted,
      replies_received: repliesReceived,
      linkedin_posts: linkedinPosts,
      engagement: 0,
      meetings_booked: meetingsBooked,
      cost_this_week: totalCost,
      cost_per_lead: leads > 0 ? totalCost / leads : 0,
    });
  }, []);

  const fetchActivity = useCallback(async () => {
    const [runsRes, episodesRes] = await Promise.all([
      supabase.from('agent_runs').select('*').order('started_at', { ascending: false }).limit(15),
      supabase.from('episodes').select('*').order('created_at', { ascending: false }).limit(15),
    ]);

    const runs = (runsRes.data || []).map(r => ({ ...r, _type: 'run' }));
    const episodes = (episodesRes.data || []).map(e => ({ ...e, _type: 'episode' }));
    const combined = [...runs, ...episodes]
      .sort((a, b) => {
        const aTime = ('started_at' in a ? a.started_at : a.created_at) || '';
        const bTime = ('started_at' in b ? b.started_at : b.created_at) || '';
        return new Date(bTime).getTime() - new Date(aTime).getTime();
      })
      .slice(0, 20);
    setActivity(combined);
  }, []);

  const fetchMessages = useCallback(async () => {
    const { data } = await supabase
      .from('agent_messages')
      .select('*')
      .or('from_agent.eq.orchestrator,to_agent.eq.orchestrator,from_agent.eq.user')
      .order('created_at', { ascending: true })
      .limit(50);
    if (data) setMessages(data);
  }, []);

  // ── Initial load + subscriptions ───────────────────────────────────────────

  useEffect(() => {
    fetchAgents();
    fetchPipeline();
    fetchKPIs();
    fetchActivity();
    fetchMessages();

    const agentSub = supabase
      .channel('agent-status-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'agent_status' }, () => {
        fetchAgents();
      })
      .subscribe();

    const runsSub = supabase
      .channel('agent-runs-changes')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'agent_runs' }, () => {
        fetchActivity();
        fetchKPIs();
      })
      .subscribe();

    const episodeSub = supabase
      .channel('episodes-changes')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'episodes' }, () => {
        fetchActivity();
      })
      .subscribe();

    const contactSub = supabase
      .channel('contacts-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'contacts' }, () => {
        fetchPipeline();
        fetchKPIs();
      })
      .subscribe();

    const msgSub = supabase
      .channel('messages-changes')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'agent_messages' }, () => {
        fetchMessages();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(agentSub);
      supabase.removeChannel(runsSub);
      supabase.removeChannel(episodeSub);
      supabase.removeChannel(contactSub);
      supabase.removeChannel(msgSub);
    };
  }, [fetchAgents, fetchPipeline, fetchKPIs, fetchActivity, fetchMessages]);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  // ── Send message ───────────────────────────────────────────────────────────

  const sendMessage = async () => {
    if (!chatInput.trim() || sending) return;
    setSending(true);
    await supabase.from('agent_messages').insert({
      from_agent: 'user',
      to_agent: 'orchestrator',
      message_type: 'instruction',
      content: chatInput.trim(),
    });
    setChatInput('');
    setSending(false);
    inputRef.current?.focus();
  };

  // ── Derived state ──────────────────────────────────────────────────────────

  const health = overallHealth(agents);
  const healthColors: Record<string, string> = {
    green: 'var(--accent-green)',
    yellow: 'var(--accent-yellow)',
    red: 'var(--accent-red)',
  };

  const totalContacts = pipeline.reduce((s, p) => s + p.count, 0);

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <div style={{ minHeight: '100vh', position: 'relative' }}>
      {/* ── Header ──────────────────────────────────────────────────────── */}
      <header style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '16px 24px',
        borderBottom: '1px solid var(--border)',
        background: 'var(--bg-primary)',
        position: 'sticky', top: 0, zIndex: 50,
        backdropFilter: 'blur(12px)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{
            width: 32, height: 32, borderRadius: 8,
            background: 'linear-gradient(135deg, var(--accent-blue), var(--accent-purple))',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontWeight: 700, fontSize: 14, color: 'white',
          }}>G</div>
          <div>
            <div style={{ fontSize: 15, fontWeight: 600, letterSpacing: '-0.01em' }}>
              GTM Company
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-secondary)', letterSpacing: '0.04em', textTransform: 'uppercase' }}>
              AI Integrators
            </div>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: 12, color: 'var(--text-secondary)' }}>
            <div style={{
              width: 8, height: 8, borderRadius: '50%',
              background: healthColors[health],
              boxShadow: `0 0 8px ${healthColors[health]}`,
            }} />
            {health === 'green' ? 'All Systems Operational' : health === 'yellow' ? 'Warning' : 'System Error'}
          </div>
          <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
            Heartbeat: {lastHeartbeat ? timeAgo(lastHeartbeat) : '--'}
          </div>
          <button
            onClick={() => setChatOpen(!chatOpen)}
            style={{
              background: chatOpen ? 'var(--accent-blue)' : 'var(--bg-card)',
              color: chatOpen ? 'white' : 'var(--text-primary)',
              border: chatOpen ? 'none' : '1px solid var(--border)',
              borderRadius: 'var(--radius)',
              padding: '6px 14px',
              fontSize: 12,
              fontWeight: 500,
              cursor: 'pointer',
              transition: 'all 0.15s ease',
            }}
          >
            Orchestrator Chat
          </button>
        </div>
      </header>

      {/* ── Main Grid ───────────────────────────────────────────────────── */}
      <main style={{ padding: '24px', maxWidth: 1400, margin: '0 auto' }}>

        {/* Agent Status Grid */}
        <section style={{ marginBottom: 24 }}>
          <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--text-muted)', marginBottom: 12 }}>
            Agent Status
          </div>
          <div style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
            gap: 12,
          }}>
            {AGENTS.map(agentDef => {
              const agent = agents.find(a => a.agent_name === agentDef.name);
              const status = agent?.status || 'idle';
              const isOrchestrator = agentDef.name === 'orchestrator';

              return (
                <div key={agentDef.name} style={{
                  background: 'var(--bg-card)',
                  border: `1px solid ${agent?.status === 'error' ? 'var(--accent-red)' : 'var(--border)'}`,
                  borderRadius: 'var(--radius-lg)',
                  padding: 16,
                  transition: 'border-color 0.2s ease, background 0.2s ease',
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
                      padding: '2px 8px',
                      borderRadius: 20,
                      fontSize: 11,
                      fontWeight: 500,
                      color: statusColor(status),
                      background: statusBg(status),
                      textTransform: 'capitalize',
                    }}>
                      {status === 'running' && (
                        <span style={{ display: 'inline-block', width: 6, height: 6, borderRadius: '50%', background: statusColor(status), marginRight: 4, animation: 'pulse 1.5s infinite' }} />
                      )}
                      {status}
                    </div>
                  </div>

                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11 }}>
                      <span style={{ color: 'var(--text-muted)' }}>Last run</span>
                      <span style={{ color: 'var(--text-secondary)' }}>{timeAgo(agent?.last_run_at || null)}</span>
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11 }}>
                      <span style={{ color: 'var(--text-muted)' }}>Next run</span>
                      <span style={{ color: 'var(--text-secondary)' }}>{agent?.next_run_at ? formatTime(agent.next_run_at) : '--'}</span>
                    </div>
                    {agent?.last_metric && (
                      <div style={{
                        marginTop: 4, padding: '4px 8px',
                        background: 'var(--bg-input)', borderRadius: 4,
                        fontSize: 11, color: 'var(--text-secondary)',
                        fontFamily: 'var(--font-mono)',
                        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                      }}>
                        {agent.last_metric}
                      </div>
                    )}
                    {agent?.last_error && (
                      <div style={{
                        marginTop: 4, padding: '4px 8px',
                        background: 'var(--accent-red-dim)', borderRadius: 4,
                        fontSize: 11, color: 'var(--accent-red)',
                        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                      }}>
                        {agent.last_error}
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </section>

        {/* ── Middle Section: Pipeline + KPIs ─────────────────────────────── */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 24 }}>

          {/* Pipeline Funnel */}
          <section style={{
            background: 'var(--bg-card)',
            border: '1px solid var(--border)',
            borderRadius: 'var(--radius-lg)',
            padding: 20,
          }}>
            <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--text-muted)', marginBottom: 16 }}>
              Pipeline Funnel
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {PIPELINE_STAGES.map((stage, i) => {
                const stageData = pipeline.find(p => p.stage === stage.key);
                const count = stageData?.count || 0;
                const maxCount = Math.max(...pipeline.map(p => p.count), 1);
                const pct = (count / maxCount) * 100;
                const prevCount = i > 0 ? (pipeline.find(p => p.stage === PIPELINE_STAGES[i - 1].key)?.count || 0) : 0;
                const convRate = i > 0 && prevCount > 0 ? Math.round((count / prevCount) * 100) : null;

                const gradientColors = [
                  'var(--accent-blue)',
                  '#6366f1',
                  'var(--accent-purple)',
                  '#ec4899',
                  'var(--accent-yellow)',
                  'var(--accent-green)',
                  '#14b8a6',
                ];

                return (
                  <div key={stage.key}>
                    {i > 0 && convRate !== null && (
                      <div style={{
                        fontSize: 10, color: 'var(--text-muted)',
                        textAlign: 'center', marginBottom: 2, marginTop: -2,
                        fontFamily: 'var(--font-mono)',
                      }}>
                        {convRate}%
                      </div>
                    )}
                    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                      <div style={{ width: 90, fontSize: 12, color: 'var(--text-secondary)', textAlign: 'right', flexShrink: 0 }}>
                        {stage.label}
                      </div>
                      <div style={{ flex: 1, height: 24, background: 'var(--bg-input)', borderRadius: 4, overflow: 'hidden', position: 'relative' }}>
                        <div style={{
                          width: `${pct}%`,
                          height: '100%',
                          background: gradientColors[i % gradientColors.length],
                          borderRadius: 4,
                          transition: 'width 0.6s ease',
                          minWidth: count > 0 ? 2 : 0,
                          opacity: 0.8,
                        }} />
                      </div>
                      <div style={{
                        width: 36, textAlign: 'right',
                        fontSize: 13, fontWeight: 600,
                        fontFamily: 'var(--font-mono)',
                        color: count > 0 ? 'var(--text-primary)' : 'var(--text-muted)',
                      }}>
                        {count}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
            <div style={{ marginTop: 12, paddingTop: 12, borderTop: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', fontSize: 11 }}>
              <span style={{ color: 'var(--text-muted)' }}>Total contacts</span>
              <span style={{ color: 'var(--text-primary)', fontWeight: 600, fontFamily: 'var(--font-mono)' }}>{totalContacts}</span>
            </div>
          </section>

          {/* Weekly KPIs */}
          <section style={{
            background: 'var(--bg-card)',
            border: '1px solid var(--border)',
            borderRadius: 'var(--radius-lg)',
            padding: 20,
          }}>
            <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--text-muted)', marginBottom: 16 }}>
              Weekly KPIs
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              {[
                { label: 'Emails Drafted', value: kpis.emails_drafted, color: 'var(--accent-blue)' },
                { label: 'Replies Received', value: kpis.replies_received, color: 'var(--accent-green)' },
                { label: 'LinkedIn Posts', value: kpis.linkedin_posts, color: 'var(--accent-purple)' },
                { label: 'Meetings Booked', value: kpis.meetings_booked, color: 'var(--accent-yellow)' },
                { label: 'Cost This Week', value: formatCost(kpis.cost_this_week), color: 'var(--text-secondary)', isMoney: true },
                { label: 'Cost Per Lead', value: formatCost(kpis.cost_per_lead), color: 'var(--text-secondary)', isMoney: true },
              ].map(kpi => (
                <div key={kpi.label} style={{
                  background: 'var(--bg-input)',
                  borderRadius: 'var(--radius)',
                  padding: '14px 16px',
                }}>
                  <div style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--text-muted)', marginBottom: 6 }}>
                    {kpi.label}
                  </div>
                  <div style={{
                    fontSize: 24, fontWeight: 700, letterSpacing: '-0.02em',
                    color: kpi.color,
                    fontFamily: 'var(--font-mono)',
                  }}>
                    {typeof kpi.value === 'number' ? kpi.value : kpi.value}
                  </div>
                </div>
              ))}
            </div>
          </section>
        </div>

        {/* ── Activity Feed ───────────────────────────────────────────────── */}
        <section style={{
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: 'var(--radius-lg)',
          padding: 20,
        }}>
          <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--text-muted)', marginBottom: 16 }}>
            Recent Activity
          </div>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {activity.length === 0 && (
              <div style={{ padding: '32px 0', textAlign: 'center', color: 'var(--text-muted)', fontSize: 13 }}>
                No activity yet. Agents will populate this feed as they run.
              </div>
            )}
            {activity.map((item, i) => {
              const isRun = '_type' in item && (item as any)._type === 'run';
              const timestamp = isRun ? (item as any).started_at : (item as any).created_at;
              const agentName = (item as any).agent_name || 'system';
              const actionText = isRun
                ? `${(item as any).action || 'run'}`
                : `${(item as any).event_type || 'event'}`;
              const outcome = isRun
                ? ((item as any).outcome || (item as any).status || '')
                : ((item as any).summary || '');

              return (
                <div key={`${i}-${(item as any).id}`} style={{
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

      {/* ── Chat Panel ──────────────────────────────────────────────────── */}
      {chatOpen && (
        <div style={{
          position: 'fixed', top: 0, right: 0,
          width: 400, height: '100vh',
          background: 'var(--bg-primary)',
          borderLeft: '1px solid var(--border)',
          display: 'flex', flexDirection: 'column',
          zIndex: 100,
          animation: 'slideIn 0.2s ease',
        }}>
          {/* Chat Header */}
          <div style={{
            padding: '16px 20px',
            borderBottom: '1px solid var(--border)',
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          }}>
            <div>
              <div style={{ fontSize: 14, fontWeight: 600 }}>Orchestrator Chat</div>
              <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                Send instructions to the orchestrator agent
              </div>
            </div>
            <button
              onClick={() => setChatOpen(false)}
              style={{
                background: 'none', border: 'none', color: 'var(--text-muted)',
                fontSize: 18, cursor: 'pointer', padding: '4px 8px',
                borderRadius: 4,
              }}
            >
              x
            </button>
          </div>

          {/* Messages */}
          <div style={{
            flex: 1, overflowY: 'auto', padding: 20,
            display: 'flex', flexDirection: 'column', gap: 12,
          }}>
            {messages.length === 0 && (
              <div style={{
                textAlign: 'center', color: 'var(--text-muted)', fontSize: 12,
                padding: '48px 20px',
              }}>
                No messages yet. Type an instruction below to communicate with the orchestrator.
              </div>
            )}
            {messages.map(msg => {
              const isUser = msg.from_agent === 'user';
              return (
                <div key={msg.id} style={{
                  alignSelf: isUser ? 'flex-end' : 'flex-start',
                  maxWidth: '85%',
                }}>
                  <div style={{
                    fontSize: 10, color: 'var(--text-muted)', marginBottom: 4,
                    textAlign: isUser ? 'right' : 'left',
                  }}>
                    {isUser ? 'You' : msg.from_agent} &middot; {timeAgo(msg.created_at)}
                  </div>
                  <div style={{
                    padding: '10px 14px',
                    borderRadius: 12,
                    fontSize: 13,
                    lineHeight: 1.5,
                    background: isUser ? 'var(--accent-blue)' : 'var(--bg-card)',
                    color: isUser ? 'white' : 'var(--text-primary)',
                    border: isUser ? 'none' : '1px solid var(--border)',
                  }}>
                    {msg.content}
                  </div>
                </div>
              );
            })}
            <div ref={chatEndRef} />
          </div>

          {/* Input */}
          <div style={{
            padding: '16px 20px',
            borderTop: '1px solid var(--border)',
            display: 'flex', gap: 8,
          }}>
            <input
              ref={inputRef}
              value={chatInput}
              onChange={e => setChatInput(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && sendMessage()}
              placeholder="Send an instruction..."
              style={{
                flex: 1,
                background: 'var(--bg-card)',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius)',
                padding: '10px 14px',
                color: 'var(--text-primary)',
                fontSize: 13,
                outline: 'none',
                fontFamily: 'var(--font-family)',
              }}
            />
            <button
              onClick={sendMessage}
              disabled={sending || !chatInput.trim()}
              style={{
                background: chatInput.trim() ? 'var(--accent-blue)' : 'var(--bg-card)',
                color: chatInput.trim() ? 'white' : 'var(--text-muted)',
                border: chatInput.trim() ? 'none' : '1px solid var(--border)',
                borderRadius: 'var(--radius)',
                padding: '10px 16px',
                fontSize: 13,
                fontWeight: 500,
                cursor: chatInput.trim() ? 'pointer' : 'default',
                transition: 'all 0.15s ease',
              }}
            >
              Send
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
