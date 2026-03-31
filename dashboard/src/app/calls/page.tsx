'use client';

import { useEffect, useState, useCallback } from 'react';
import { supabase } from '../../lib/supabase';

// ─── Types ───────────────────────────────────────────────────────────────────

interface CallLog {
  id: string;
  project_id: string;
  contact_id: string | null;
  contact_name: string | null;
  contact_phone: string | null;
  call_type: string;
  status: string;
  duration_seconds: number;
  outcome: string | null;
  transcript: string | null;
  recording_url: string | null;
  notes: string | null;
  retell_call_id: string | null;
  created_at: string;
  completed_at: string | null;
}

interface Contact {
  id: string;
  first_name: string | null;
  last_name: string | null;
  company: string | null;
  phone: string | null;
  status: string;
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

function formatDuration(seconds: number): string {
  if (seconds === 0) return '--';
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}

function callStatusClass(status: string): string {
  const map: Record<string, string> = {
    queued: 'call-status-queued',
    ringing: 'call-status-ringing',
    connected: 'call-status-connected',
    completed: 'call-status-completed',
    voicemail: 'call-status-voicemail',
    no_answer: 'call-status-no_answer',
    failed: 'call-status-failed',
  };
  return map[status] || 'call-status-completed';
}

function outcomeLabel(outcome: string | null): string {
  if (!outcome) return '--';
  const map: Record<string, string> = {
    meeting_booked: 'Meeting Booked',
    callback_requested: 'Callback Requested',
    interested: 'Interested',
    not_interested: 'Not Interested',
    wrong_number: 'Wrong Number',
    no_answer: 'No Answer',
  };
  return map[outcome] || outcome;
}

// ─── Main Component ──────────────────────────────────────────────────────────

export default function CallCenterPage() {
  const [callLogs, setCallLogs] = useState<CallLog[]>([]);
  const [callQueue, setCallQueue] = useState<Contact[]>([]);
  const [lastSynced, setLastSynced] = useState<string | null>(null);
  const [showConfig, setShowConfig] = useState(false);

  // Config state (local only, not persisted)
  const [retellApiKey, setRetellApiKey] = useState('');
  const [retellAgentId, setRetellAgentId] = useState('');
  const [retellPhone, setRetellPhone] = useState('');

  const fetchCallLogs = useCallback(async () => {
    const { data } = await supabase
      .from('call_logs')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(50);
    if (data) {
      setCallLogs(data);
      setLastSynced(new Date().toISOString());
    }
  }, []);

  const fetchCallQueue = useCallback(async () => {
    // Contacts that need to be called
    const { data } = await supabase
      .from('contacts')
      .select('id, first_name, last_name, company, phone, status')
      .or('status.eq.call,status.eq.callback')
      .limit(20);
    if (data) setCallQueue(data);
  }, []);

  useEffect(() => {
    fetchCallLogs();
    fetchCallQueue();

    const callSub = supabase
      .channel('call-logs-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'call_logs' }, () => fetchCallLogs())
      .subscribe();

    const contactSub = supabase
      .channel('call-contacts-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'contacts' }, () => fetchCallQueue())
      .subscribe();

    return () => {
      supabase.removeChannel(callSub);
      supabase.removeChannel(contactSub);
    };
  }, [fetchCallLogs, fetchCallQueue]);

  // ── Derived stats ──────────────────────────────────────────────────────────

  const today = new Date().toDateString();
  const todayCalls = callLogs.filter(c => new Date(c.created_at).toDateString() === today);
  const callsMadeToday = todayCalls.filter(c => c.call_type === 'outbound').length;
  const voicemailsToday = todayCalls.filter(c => c.call_type === 'voicemail_drop' || c.status === 'voicemail').length;
  const callbacksToday = todayCalls.filter(c => c.call_type === 'callback').length;
  const meetingsFromCalls = todayCalls.filter(c => c.outcome === 'meeting_booked').length;

  const activeCalls = callLogs.filter(c => c.status === 'ringing' || c.status === 'connected');
  const queuedCalls = callLogs.filter(c => c.status === 'queued');

  // ── Start calling handler ──────────────────────────────────────────────────

  const handleStartCalling = async () => {
    await supabase.from('agent_messages').insert({
      project_id: 'ai-integrators-gtm',
      from_agent: 'user',
      to_agent: 'orchestrator',
      message_type: 'instruction',
      payload: {
        text: 'Start outbound calling session via Retell AI',
        action: 'start_calling',
        config: {
          agent_id: retellAgentId,
          phone: retellPhone,
        },
      },
      status: 'unread',
      priority: 'high',
    });
  };

  return (
    <main style={{ padding: '24px', maxWidth: 1400, margin: '0 auto' }}>

      {/* ── Page Header ──────────────────────────────────────────────────── */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div>
            <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-0.02em' }}>Call Center</div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Retell AI outbound calling + voicemail drops</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <div className={`status-dot ${activeCalls.length > 0 ? 'status-dot-green' : 'status-dot-yellow'}`} />
            <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
              {activeCalls.length > 0 ? `${activeCalls.length} Active` : 'Idle'}
            </span>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span className="last-synced">Synced {timeAgo(lastSynced)}</span>
          <button className="btn-secondary" onClick={() => setShowConfig(!showConfig)}>
            {showConfig ? 'Hide Config' : 'Configure'}
          </button>
          <button className="btn-primary" onClick={handleStartCalling}>
            Start Calling
          </button>
        </div>
      </div>

      {/* ── Stats Row ────────────────────────────────────────────────────── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16, marginBottom: 24 }}>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-blue)' }}>{callsMadeToday}</div>
          <div className="kpi-label">Calls Made Today</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-purple)' }}>{voicemailsToday}</div>
          <div className="kpi-label">Voicemails Dropped</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-orange)' }}>{callbacksToday}</div>
          <div className="kpi-label">Callbacks Received</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-value" style={{ color: 'var(--accent-green)' }}>{meetingsFromCalls}</div>
          <div className="kpi-label">Meetings Booked (Calls)</div>
        </div>
      </div>

      {/* ── Config Panel ─────────────────────────────────────────────────── */}
      {showConfig && (
        <section style={{
          background: 'var(--bg-card)',
          border: '1px solid var(--accent-blue-dim)',
          borderLeft: '3px solid var(--accent-blue)',
          borderRadius: 'var(--radius-lg)',
          padding: 20,
          marginBottom: 24,
          animation: 'fadeIn 0.3s ease',
        }}>
          <div className="section-title" style={{ marginBottom: 16 }}>Retell AI Configuration</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 16 }}>
            <div className="config-field">
              <label className="config-label">Retell API Key</label>
              <input
                type="password"
                className="config-input"
                value={retellApiKey}
                onChange={e => setRetellApiKey(e.target.value)}
                placeholder="ret_..."
              />
            </div>
            <div className="config-field">
              <label className="config-label">Agent ID</label>
              <input
                className="config-input"
                value={retellAgentId}
                onChange={e => setRetellAgentId(e.target.value)}
                placeholder="agent_..."
              />
            </div>
            <div className="config-field">
              <label className="config-label">Phone Number</label>
              <input
                className="config-input"
                value={retellPhone}
                onChange={e => setRetellPhone(e.target.value)}
                placeholder="+1..."
              />
            </div>
          </div>
          <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 12 }}>
            Configuration is stored locally in this session. In V2, this will be saved to Supabase config.
          </div>
        </section>
      )}

      {/* ── Two Column: Queue + Active Calls ─────────────────────────────── */}
      <div className="middle-grid" style={{ display: 'grid', gap: 16, marginBottom: 24 }}>

        {/* Call Queue */}
        <section style={{
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: 'var(--radius-lg)',
          padding: 20,
        }}>
          <div className="section-header">
            <div className="section-title">Call Queue ({callQueue.length + queuedCalls.length})</div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {queuedCalls.map(call => (
              <div key={call.id} className="call-queue-item">
                <div style={{
                  width: 32, height: 32, borderRadius: 6,
                  background: 'var(--accent-yellow-dim)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 12, fontWeight: 600, color: 'var(--accent-yellow)',
                }}>Q</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 13, fontWeight: 500 }}>{call.contact_name || 'Unknown'}</div>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{call.contact_phone || 'No phone'}</div>
                </div>
                <span className={`call-status-badge ${callStatusClass(call.status)}`}>{call.status}</span>
              </div>
            ))}
            {callQueue.map(contact => (
              <div key={contact.id} className="call-queue-item">
                <div style={{
                  width: 32, height: 32, borderRadius: 6,
                  background: 'var(--bg-input)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)',
                }}>C</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 13, fontWeight: 500 }}>
                    {[contact.first_name, contact.last_name].filter(Boolean).join(' ') || 'Unknown'}
                  </div>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                    {contact.company || 'No company'} -- {contact.phone || 'No phone'}
                  </div>
                </div>
                <span style={{
                  padding: '2px 8px', borderRadius: 20, fontSize: 11, fontWeight: 500,
                  color: 'var(--text-muted)', background: 'rgba(85,85,85,0.12)',
                }}>
                  Pending
                </span>
              </div>
            ))}
            {queuedCalls.length === 0 && callQueue.length === 0 && (
              <div style={{ padding: '24px 0', textAlign: 'center', color: 'var(--text-muted)', fontSize: 13 }}>
                No contacts in queue. Contacts with status &quot;call&quot; or &quot;callback&quot; will appear here.
              </div>
            )}
          </div>
        </section>

        {/* Active Calls */}
        <section style={{
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: 'var(--radius-lg)',
          padding: 20,
        }}>
          <div className="section-header">
            <div className="section-title">Active Calls ({activeCalls.length})</div>
            <span className="last-synced">Real-time</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {activeCalls.map(call => (
              <div key={call.id} className="call-queue-item" style={{ borderColor: 'var(--accent-green)' }}>
                <div style={{
                  width: 32, height: 32, borderRadius: 6,
                  background: 'var(--accent-green-dim)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 14, fontWeight: 600, color: 'var(--accent-green)',
                }}>
                  <span style={{ animation: 'pulse 1.5s infinite' }}>*</span>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 13, fontWeight: 500 }}>{call.contact_name || 'Unknown'}</div>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{call.contact_phone}</div>
                </div>
                <span className={`call-status-badge ${callStatusClass(call.status)}`}>{call.status}</span>
              </div>
            ))}
            {activeCalls.length === 0 && (
              <div style={{
                padding: '40px 0', textAlign: 'center',
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
              }}>
                <div style={{ fontSize: 24, color: 'var(--text-muted)', opacity: 0.3 }}>--</div>
                <div style={{ color: 'var(--text-muted)', fontSize: 13 }}>
                  No active calls. Click &quot;Start Calling&quot; to begin a session.
                </div>
              </div>
            )}
          </div>

          {/* Call Script Area */}
          <div style={{
            marginTop: 16, paddingTop: 16, borderTop: '1px solid var(--border)',
          }}>
            <div className="section-title" style={{ marginBottom: 8 }}>Call Script</div>
            <div style={{
              background: 'var(--bg-input)', borderRadius: 'var(--radius)',
              padding: 12, fontSize: 12, color: 'var(--text-muted)',
              lineHeight: 1.6, minHeight: 80,
              border: '1px solid var(--border)',
            }}>
              Call script will be loaded from Retell AI agent configuration.
              The AI agent handles the conversation autonomously.
            </div>
          </div>
        </section>
      </div>

      {/* ── Call History ──────────────────────────────────────────────────── */}
      <section style={{
        background: 'var(--bg-card)',
        border: '1px solid var(--border)',
        borderRadius: 'var(--radius-lg)',
        padding: 20,
        marginBottom: 24,
      }}>
        <div className="section-header">
          <div className="section-title">Call History</div>
          <span className="last-synced">Synced {timeAgo(lastSynced)}</span>
        </div>
        <div style={{ overflowX: 'auto' }}>
          <table className="campaign-table">
            <thead>
              <tr>
                <th>Contact</th>
                <th>Phone</th>
                <th>Type</th>
                <th>Status</th>
                <th>Duration</th>
                <th>Outcome</th>
                <th>Time</th>
              </tr>
            </thead>
            <tbody>
              {callLogs.filter(c => c.status !== 'queued' && c.status !== 'ringing' && c.status !== 'connected').slice(0, 20).map(call => (
                <tr key={call.id}>
                  <td style={{ color: 'var(--text-primary)', fontWeight: 500 }}>
                    {call.contact_name || 'Unknown'}
                  </td>
                  <td className="mono">{call.contact_phone || '--'}</td>
                  <td>
                    <span style={{
                      padding: '2px 6px', borderRadius: 4, fontSize: 10, fontWeight: 500,
                      background: call.call_type === 'outbound' ? 'var(--accent-blue-dim)' : call.call_type === 'callback' ? 'var(--accent-green-dim)' : 'var(--accent-purple-dim)',
                      color: call.call_type === 'outbound' ? 'var(--accent-blue)' : call.call_type === 'callback' ? 'var(--accent-green)' : 'var(--accent-purple)',
                      textTransform: 'capitalize',
                    }}>
                      {call.call_type?.replace('_', ' ') || '--'}
                    </span>
                  </td>
                  <td>
                    <span className={`call-status-badge ${callStatusClass(call.status)}`}>
                      {call.status}
                    </span>
                  </td>
                  <td className="mono">{formatDuration(call.duration_seconds)}</td>
                  <td style={{
                    color: call.outcome === 'meeting_booked' ? 'var(--accent-green)' :
                           call.outcome === 'interested' ? 'var(--accent-yellow)' :
                           call.outcome === 'not_interested' ? 'var(--accent-red)' :
                           'var(--text-secondary)',
                    fontWeight: call.outcome === 'meeting_booked' ? 600 : 400,
                  }}>
                    {outcomeLabel(call.outcome)}
                  </td>
                  <td style={{ color: 'var(--text-muted)', fontSize: 11 }}>{timeAgo(call.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {callLogs.length === 0 && (
            <div style={{ padding: '32px 0', textAlign: 'center', color: 'var(--text-muted)', fontSize: 13 }}>
              No call history yet. Calls will appear here once the first session begins.
            </div>
          )}
        </div>
      </section>

      {/* ── Voicemail Queue ──────────────────────────────────────────────── */}
      <section style={{
        background: 'var(--bg-card)',
        border: '1px solid var(--border)',
        borderRadius: 'var(--radius-lg)',
        padding: 20,
      }}>
        <div className="section-header">
          <div className="section-title">Voicemail Drop Queue</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {callLogs.filter(c => c.call_type === 'voicemail_drop' && c.status === 'queued').map(call => (
            <div key={call.id} className="call-queue-item">
              <div style={{
                width: 32, height: 32, borderRadius: 6,
                background: 'var(--accent-purple-dim)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: 12, fontWeight: 600, color: 'var(--accent-purple)',
              }}>VM</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 500 }}>{call.contact_name || 'Unknown'}</div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{call.contact_phone || 'No phone'}</div>
              </div>
              <span className="call-status-badge call-status-queued">Queued</span>
            </div>
          ))}
          {callLogs.filter(c => c.call_type === 'voicemail_drop' && c.status === 'queued').length === 0 && (
            <div style={{ padding: '24px 0', textAlign: 'center', color: 'var(--text-muted)', fontSize: 13 }}>
              No voicemails queued. Voicemail drops will be added here by the orchestrator.
            </div>
          )}
        </div>
      </section>
    </main>
  );
}
