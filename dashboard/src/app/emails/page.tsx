'use client';

import { useEffect, useState, useCallback } from 'react';
import { supabase } from '../../lib/supabase';

// ─── Types ───────────────────────────────────────────────────────────────────

interface CampaignStat {
  id: string;
  campaign_name: string;
  campaign_type: string;
  status: string;
  sent: number;
  opens: number;
  replies: number;
  bounces: number;
  unsubscribed: number;
  leads_total: number;
  leads_contacted: number;
  reply_rate: number;
  updated_at: string;
}

interface Episode {
  id: string;
  agent_id: string;
  event_type: string;
  description: string;
  data: Record<string, any> | null;
  created_at: string;
}

interface PipelineStage {
  stage: string;
  count: number;
  label: string;
}

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

function replyRateColor(rate: number): string {
  if (rate >= 2) return 'campaign-card-green';
  if (rate >= 1) return 'campaign-card-yellow';
  return 'campaign-card-red';
}

const PIPELINE_STAGES = [
  { key: 'new', label: 'New' },
  { key: 'contacted', label: 'Contacted' },
  { key: 'replied', label: 'Replied' },
  { key: 'meeting_booked', label: 'Meeting Booked' },
];

const GRADIENT_COLORS = [
  'var(--accent-blue)',
  'var(--accent-purple)',
  'var(--accent-green)',
  'var(--accent-yellow)',
];

// ─── Main Component ──────────────────────────────────────────────────────────

export default function EmailsPage() {
  const [campaigns, setCampaigns] = useState<CampaignStat[]>([]);
  const [replyFeed, setReplyFeed] = useState<Episode[]>([]);
  const [pipeline, setPipeline] = useState<PipelineStage[]>([]);
  const [lastSynced, setLastSynced] = useState<string | null>(null);

  const fetchCampaigns = useCallback(async () => {
    const { data } = await supabase
      .from('campaign_stats')
      .select('*')
      .order('updated_at', { ascending: false });
    if (data) {
      setCampaigns(data);
      setLastSynced(data[0]?.updated_at || new Date().toISOString());
    }
  }, []);

  const fetchReplies = useCallback(async () => {
    const { data } = await supabase
      .from('episodes')
      .select('id, agent_id, event_type, description, data, created_at')
      .or('event_type.ilike.%reply%,event_type.ilike.%email%')
      .order('created_at', { ascending: false })
      .limit(20);
    if (data) setReplyFeed(data);
  }, []);

  const fetchPipeline = useCallback(async () => {
    const { data } = await supabase
      .from('contacts')
      .select('status, source');
    if (data) {
      const counts: Record<string, number> = {};
      PIPELINE_STAGES.forEach(s => counts[s.key] = 0);
      data.forEach((row: { status: string; source: string }) => {
        const stage = row.status?.toLowerCase().replace(/\s+/g, '_');
        if (stage && counts[stage] !== undefined) counts[stage]++;
      });
      setPipeline(PIPELINE_STAGES.map(s => ({ stage: s.key, count: counts[s.key] || 0, label: s.label })));
    }
  }, []);

  useEffect(() => {
    fetchCampaigns();
    fetchReplies();
    fetchPipeline();

    const campaignSub = supabase
      .channel('emails-campaigns')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'campaign_stats' }, () => fetchCampaigns())
      .subscribe();

    const episodeSub = supabase
      .channel('emails-episodes')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'episodes' }, () => fetchReplies())
      .subscribe();

    const contactSub = supabase
      .channel('emails-contacts')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'contacts' }, () => fetchPipeline())
      .subscribe();

    return () => {
      supabase.removeChannel(campaignSub);
      supabase.removeChannel(episodeSub);
      supabase.removeChannel(contactSub);
    };
  }, [fetchCampaigns, fetchReplies, fetchPipeline]);

  // ── Derived ────────────────────────────────────────────────────────────────

  const totalSent = campaigns.reduce((s, c) => s + c.sent, 0);
  const totalReplies = campaigns.reduce((s, c) => s + c.replies, 0);
  const totalBounces = campaigns.reduce((s, c) => s + c.bounces, 0);
  const overallReplyRate = totalSent > 0 ? ((totalReplies / totalSent) * 100).toFixed(1) : '0.0';
  const bestCampaign = campaigns.reduce((best, c) => {
    const rate = c.sent > 0 ? (c.replies / c.sent) * 100 : 0;
    const bestRate = best && best.sent > 0 ? (best.replies / best.sent) * 100 : 0;
    return rate > bestRate ? c : best;
  }, campaigns[0] || null);
  const costPerReply = totalReplies > 0 ? (0 / totalReplies).toFixed(2) : '--';

  return (
    <main style={{ padding: '24px', maxWidth: 1400, margin: '0 auto' }}>

      {/* ── Page Header ──────────────────────────────────────────────────── */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div>
          <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-0.02em' }}>Cold Email</div>
          <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Campaign performance and reply pipeline</div>
        </div>
        <span className="last-synced">Data synced {timeAgo(lastSynced)}</span>
      </div>

      {/* ── Top Stats Row ────────────────────────────────────────────────── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16, marginBottom: 24 }}>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-blue)' }}>{totalSent.toLocaleString()}</div>
          <div className="kpi-label">Total Sent</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-green)' }}>{totalReplies}</div>
          <div className="kpi-label">Total Replies</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: parseFloat(overallReplyRate) >= 2 ? 'var(--accent-green)' : parseFloat(overallReplyRate) >= 1 ? 'var(--accent-yellow)' : 'var(--accent-red)' }}>
            {overallReplyRate}%
          </div>
          <div className="kpi-label">Overall Reply Rate</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-red)' }}>{totalBounces}</div>
          <div className="kpi-label">Total Bounces</div>
        </div>
      </div>

      {/* ── Campaign Cards ───────────────────────────────────────────────── */}
      <section style={{ marginBottom: 24 }}>
        <div className="section-header">
          <div className="section-title">Campaigns</div>
          <span className="last-synced">Synced {timeAgo(lastSynced)}</span>
        </div>
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))',
          gap: 12,
        }}>
          {campaigns.map(c => {
            const replyRate = c.sent > 0 ? (c.replies / c.sent) * 100 : 0;
            const openRate = c.sent > 0 ? ((c.opens / c.sent) * 100).toFixed(1) : '0.0';
            const isActive = c.status === 'active' || c.status === 'STARTED';

            return (
              <div key={c.id} className={`campaign-card ${replyRateColor(replyRate)}`}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                    <div style={{
                      width: 28, height: 28, borderRadius: 6,
                      background: 'var(--accent-blue-dim)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 12, fontWeight: 600, color: 'var(--accent-blue)',
                      fontFamily: 'var(--font-mono)', flexShrink: 0,
                    }}>E</div>
                    <span style={{
                      fontSize: 13, fontWeight: 500,
                      overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                    }}>
                      {c.campaign_name}
                    </span>
                  </div>
                  <span style={{
                    padding: '2px 8px', borderRadius: 20, fontSize: 11, fontWeight: 500,
                    color: isActive ? 'var(--accent-green)' : 'var(--text-muted)',
                    background: isActive ? 'var(--accent-green-dim)' : 'rgba(85,85,85,0.12)',
                    textTransform: 'capitalize', flexShrink: 0,
                  }}>
                    {isActive && (
                      <span style={{ display: 'inline-block', width: 6, height: 6, borderRadius: '50%', background: 'var(--accent-green)', marginRight: 4 }} />
                    )}
                    {c.status}
                  </span>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
                  <div style={{ background: 'var(--bg-input)', borderRadius: 'var(--radius)', padding: '8px 10px' }}>
                    <div style={{ fontSize: 10, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Sent</div>
                    <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--accent-blue)', fontFamily: 'var(--font-mono)' }}>{c.sent.toLocaleString()}</div>
                  </div>
                  <div style={{ background: 'var(--bg-input)', borderRadius: 'var(--radius)', padding: '8px 10px' }}>
                    <div style={{ fontSize: 10, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Replies</div>
                    <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--accent-green)', fontFamily: 'var(--font-mono)' }}>{c.replies}</div>
                  </div>
                  <div style={{ background: 'var(--bg-input)', borderRadius: 'var(--radius)', padding: '8px 10px' }}>
                    <div style={{ fontSize: 10, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Reply Rate</div>
                    <div style={{ fontSize: 16, fontWeight: 700, color: replyRate >= 2 ? 'var(--accent-green)' : replyRate >= 1 ? 'var(--accent-yellow)' : 'var(--accent-red)', fontFamily: 'var(--font-mono)' }}>
                      {replyRate.toFixed(1)}%
                    </div>
                  </div>
                </div>

                <div style={{ marginTop: 8, display: 'flex', justifyContent: 'space-between', fontSize: 11 }}>
                  <span style={{ color: 'var(--text-muted)' }}>Opens: <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--text-secondary)' }}>{openRate}%</span></span>
                  <span style={{ color: 'var(--text-muted)' }}>Bounces: <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--accent-red)' }}>{c.bounces}</span></span>
                  <span style={{ color: 'var(--text-muted)' }}>Updated {timeAgo(c.updated_at)}</span>
                </div>
              </div>
            );
          })}
        </div>
        {campaigns.length === 0 && (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)', fontSize: 13, background: 'var(--bg-card)', borderRadius: 'var(--radius-lg)', border: '1px solid var(--border)' }}>
            No campaign data yet. Campaigns will appear here once SmartLead syncs.
          </div>
        )}
      </section>

      {/* ── Two Column: Reply Feed + Pipeline ────────────────────────────── */}
      <div className="middle-grid" style={{ display: 'grid', gap: 16, marginBottom: 24 }}>

        {/* Reply Feed */}
        <section style={{
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: 'var(--radius-lg)',
          padding: 20,
        }}>
          <div className="section-header">
            <div className="section-title">Reply Feed</div>
            <span className="last-synced">Real-time</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {replyFeed.length === 0 && (
              <div style={{ padding: '32px 0', textAlign: 'center', color: 'var(--text-muted)', fontSize: 13 }}>
                No replies yet. They will appear here in real-time.
              </div>
            )}
            {replyFeed.map((ep, i) => (
              <div key={ep.id} style={{
                padding: '10px 0',
                borderBottom: i < replyFeed.length - 1 ? '1px solid var(--border)' : 'none',
                display: 'flex', alignItems: 'flex-start', gap: 10,
              }}>
                <div style={{
                  width: 6, height: 6, borderRadius: '50%',
                  background: 'var(--accent-green)',
                  marginTop: 6, flexShrink: 0,
                }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 12, color: 'var(--text-primary)', marginBottom: 2 }}>
                    {ep.description || ep.event_type}
                  </div>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                    {ep.agent_id} -- {timeAgo(ep.created_at)}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Lead Pipeline */}
        <section style={{
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: 'var(--radius-lg)',
          padding: 20,
        }}>
          <div className="section-header">
            <div className="section-title">Lead Pipeline (Email)</div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {pipeline.map((stage, i) => {
              const maxCount = Math.max(...pipeline.map(p => p.count), 1);
              const pct = (stage.count / maxCount) * 100;
              return (
                <div key={stage.stage} className="funnel-stage">
                  <div className="funnel-label">{stage.label}</div>
                  <div className="funnel-bar">
                    <div className="funnel-bar-fill" style={{
                      width: `${pct}%`,
                      background: GRADIENT_COLORS[i % GRADIENT_COLORS.length],
                      minWidth: stage.count > 0 ? 2 : 0,
                    }} />
                  </div>
                  <div className="funnel-count" style={{
                    color: stage.count > 0 ? 'var(--text-primary)' : 'var(--text-muted)',
                  }}>
                    {stage.count}
                  </div>
                </div>
              );
            })}
          </div>
          <div style={{ marginTop: 16, paddingTop: 12, borderTop: '1px solid var(--border)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12 }}>
              <span style={{ color: 'var(--text-muted)' }}>Best campaign</span>
              <span style={{ color: 'var(--text-primary)', fontWeight: 500 }}>
                {bestCampaign ? bestCampaign.campaign_name : '--'}
              </span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, marginTop: 4 }}>
              <span style={{ color: 'var(--text-muted)' }}>Cost per reply</span>
              <span style={{ color: 'var(--text-secondary)', fontFamily: 'var(--font-mono)' }}>
                {costPerReply === '--' ? '--' : `$${costPerReply}`}
              </span>
            </div>
          </div>
        </section>
      </div>

      {/* ── Stats Placeholders ────────────────────────────────────────────── */}
      <div className="middle-grid" style={{ display: 'grid', gap: 16 }}>
        <div style={{
          background: 'var(--bg-card)', border: '1px solid var(--border)',
          borderRadius: 'var(--radius-lg)', padding: 20,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          minHeight: 160, color: 'var(--text-muted)', fontSize: 13,
        }}>
          Daily send volume chart (coming soon)
        </div>
        <div style={{
          background: 'var(--bg-card)', border: '1px solid var(--border)',
          borderRadius: 'var(--radius-lg)', padding: 20,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          minHeight: 160, color: 'var(--text-muted)', fontSize: 13,
        }}>
          Reply rate trend chart (coming soon)
        </div>
      </div>
    </main>
  );
}
