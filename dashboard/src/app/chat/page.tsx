'use client';

import { useEffect, useState, useRef, useCallback } from 'react';
import { supabase } from '../../lib/supabase';

// ─── Types ───────────────────────────────────────────────────────────────────

interface AgentMessage {
  id: string;
  project_id: string;
  from_agent: string;
  to_agent: string;
  message_type: string;
  payload: Record<string, any> | null;
  status: string;
  priority: string;
  created_at: string;
  processed_at: string | null;
  processed_by: string | null;
}

// ─── Constants ──────────────────────────────────────────────────────────────

const AGENTS = [
  { name: 'orchestrator', label: 'Orchestrator', icon: '~', color: 'linear-gradient(135deg, var(--accent-blue), var(--accent-purple))' },
  { name: 'cold-outreach', label: 'Cold Outreach', icon: 'E', color: 'var(--accent-blue)' },
  { name: 'linkedin-engage', label: 'LinkedIn Engage', icon: 'L', color: 'var(--accent-purple)' },
  { name: 'lead-router', label: 'Lead Router', icon: 'R', color: 'var(--accent-green)' },
  { name: 'content-strategist', label: 'Content Strategist', icon: 'C', color: 'var(--accent-yellow)' },
  { name: 'weekly-strategist', label: 'Weekly Strategist', icon: 'W', color: 'var(--accent-red)' },
];

// ─── Helpers ────────────────────────────────────────────────────────────────

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

function formatTimestamp(dateStr: string): string {
  const d = new Date(dateStr);
  const now = new Date();
  const isToday = d.toDateString() === now.toDateString();
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday = d.toDateString() === yesterday.toDateString();

  const time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
  if (isToday) return time;
  if (isYesterday) return `Yesterday ${time}`;
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) + ' ' + time;
}

function getMessageText(msg: AgentMessage): string {
  if (msg.payload?.text) return msg.payload.text;
  if (msg.payload?.summary) return msg.payload.summary;
  if (msg.payload?.content) return msg.payload.content;
  if (typeof msg.payload === 'object' && msg.payload !== null) {
    // For structured payloads (task_complete, etc.), create a readable summary
    const keys = Object.keys(msg.payload);
    if (keys.length === 0) return '[empty message]';
    return JSON.stringify(msg.payload, null, 2);
  }
  return '[no content]';
}

function getAgentDef(name: string) {
  return AGENTS.find(a => a.name === name) || { name, label: name, icon: name[0]?.toUpperCase() || '?', color: 'var(--text-muted)' };
}

// ─── Main Component ─────────────────────────────────────────────────────────

export default function ChatPage() {
  const [messages, setMessages] = useState<AgentMessage[]>([]);
  const [briefing, setBriefing] = useState<AgentMessage | null>(null);
  const [filter, setFilter] = useState<string>('orchestrator');
  const [targetAgent, setTargetAgent] = useState<string>('orchestrator');
  const [chatInput, setChatInput] = useState('');
  const [sending, setSending] = useState(false);
  const [agentLastSeen, setAgentLastSeen] = useState<Record<string, string>>({});
  const chatEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // ── Data fetching ─────────────────────────────────────────────────────────

  const fetchMessages = useCallback(async () => {
    let query = supabase
      .from('agent_messages')
      .select('*')
      .order('created_at', { ascending: true });

    if (filter === 'all') {
      // Show everything
    } else {
      // Show messages involving the selected agent and user
      query = query.or(
        `and(from_agent.eq.${filter},to_agent.eq.user),and(from_agent.eq.user,to_agent.eq.${filter}),and(from_agent.eq.${filter},to_agent.eq.orchestrator),and(from_agent.eq.orchestrator,to_agent.eq.${filter})`
      );
    }

    const { data } = await query.limit(200);
    if (data) setMessages(data);
  }, [filter]);

  const fetchBriefing = useCallback(async () => {
    const { data } = await supabase
      .from('agent_messages')
      .select('*')
      .eq('message_type', 'daily_briefing')
      .order('created_at', { ascending: false })
      .limit(1);
    if (data && data.length > 0) setBriefing(data[0]);
  }, []);

  const fetchAgentActivity = useCallback(async () => {
    const lastSeen: Record<string, string> = {};
    for (const agent of AGENTS) {
      const { data } = await supabase
        .from('agent_messages')
        .select('created_at')
        .eq('from_agent', agent.name)
        .order('created_at', { ascending: false })
        .limit(1);
      if (data && data.length > 0) {
        lastSeen[agent.name] = data[0].created_at;
      }
    }
    setAgentLastSeen(lastSeen);
  }, []);

  // ── Initial load + subscriptions ──────────────────────────────────────────

  useEffect(() => {
    fetchMessages();
    fetchBriefing();
    fetchAgentActivity();

    const msgSub = supabase
      .channel('chat-messages')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'agent_messages' }, () => {
        fetchMessages();
        fetchBriefing();
        fetchAgentActivity();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(msgSub);
    };
  }, [fetchMessages, fetchBriefing, fetchAgentActivity]);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  // ── Send message ──────────────────────────────────────────────────────────

  const sendMessage = async () => {
    if (!chatInput.trim() || sending) return;
    setSending(true);
    await supabase.from('agent_messages').insert({
      project_id: 'ai-integrators-gtm',
      from_agent: 'user',
      to_agent: targetAgent,
      message_type: 'instruction',
      payload: { text: chatInput.trim() },
      status: 'unread',
      priority: 'normal',
    });
    setChatInput('');
    setSending(false);
    inputRef.current?.focus();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div style={{ display: 'flex', height: '100vh', background: 'var(--bg-primary)' }}>
      {/* ── Left Sidebar: Agent List ─────────────────────────────────────── */}
      <aside style={{
        width: 240,
        borderRight: '1px solid var(--border)',
        display: 'flex',
        flexDirection: 'column',
        background: 'var(--bg-primary)',
        flexShrink: 0,
      }}>
        {/* Sidebar Header */}
        <div style={{
          padding: '16px 16px 12px',
          borderBottom: '1px solid var(--border)',
        }}>
          <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--text-muted)' }}>
            Agents
          </div>
        </div>

        {/* All filter */}
        <button
          onClick={() => setFilter('all')}
          style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '10px 16px',
            background: filter === 'all' ? 'var(--bg-card-hover)' : 'transparent',
            border: 'none',
            borderLeft: filter === 'all' ? '2px solid var(--accent-blue)' : '2px solid transparent',
            color: filter === 'all' ? 'var(--text-primary)' : 'var(--text-secondary)',
            cursor: 'pointer',
            fontSize: 13,
            textAlign: 'left',
            transition: 'all 0.15s ease',
            width: '100%',
          }}
        >
          <div style={{
            width: 28, height: 28, borderRadius: 6,
            background: 'var(--bg-input)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)',
            fontFamily: 'var(--font-mono)',
          }}>*</div>
          <div>
            <div style={{ fontWeight: 500 }}>All Messages</div>
            <div style={{ fontSize: 10, color: 'var(--text-muted)' }}>Everything</div>
          </div>
        </button>

        {/* Agent list */}
        <div style={{ flex: 1, overflowY: 'auto' }}>
          {AGENTS.map(agent => {
            const isSelected = filter === agent.name;
            const lastMsg = agentLastSeen[agent.name];
            const isOrchestrator = agent.name === 'orchestrator';

            return (
              <button
                key={agent.name}
                onClick={() => setFilter(agent.name)}
                style={{
                  display: 'flex', alignItems: 'center', gap: 10,
                  padding: '10px 16px',
                  background: isSelected ? 'var(--bg-card-hover)' : 'transparent',
                  border: 'none',
                  borderLeft: isSelected ? '2px solid var(--accent-blue)' : '2px solid transparent',
                  color: isSelected ? 'var(--text-primary)' : 'var(--text-secondary)',
                  cursor: 'pointer',
                  fontSize: 13,
                  textAlign: 'left',
                  transition: 'all 0.15s ease',
                  width: '100%',
                }}
              >
                <div style={{
                  width: 28, height: 28, borderRadius: 6,
                  background: isOrchestrator ? agent.color : 'var(--bg-input)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 12, fontWeight: 600,
                  color: isOrchestrator ? 'white' : 'var(--text-secondary)',
                  fontFamily: 'var(--font-mono)',
                  flexShrink: 0,
                }}>
                  {agent.icon}
                </div>
                <div style={{ minWidth: 0, flex: 1 }}>
                  <div style={{ fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {agent.label}
                  </div>
                  <div style={{ fontSize: 10, color: 'var(--text-muted)' }}>
                    {lastMsg ? timeAgo(lastMsg) : 'No messages'}
                  </div>
                </div>
                {/* Status dot */}
                <div style={{
                  width: 6, height: 6, borderRadius: '50%',
                  background: lastMsg && (Date.now() - new Date(lastMsg).getTime() < 3600000)
                    ? 'var(--accent-green)'
                    : 'var(--text-muted)',
                  flexShrink: 0,
                }} />
              </button>
            );
          })}
        </div>
      </aside>

      {/* ── Main Chat Area ───────────────────────────────────────────────── */}
      <main style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        {/* Chat Header */}
        <header style={{
          padding: '14px 24px',
          borderBottom: '1px solid var(--border)',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          background: 'var(--bg-primary)',
          flexShrink: 0,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            {(() => {
              const agent = filter === 'all'
                ? { label: 'All Messages', icon: '*', color: 'var(--bg-input)' }
                : getAgentDef(filter);
              return (
                <>
                  <div style={{
                    width: 32, height: 32, borderRadius: 8,
                    background: agent.color,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    fontSize: 14, fontWeight: 600, color: 'white',
                    fontFamily: 'var(--font-mono)',
                  }}>{agent.icon}</div>
                  <div>
                    <div style={{ fontSize: 15, fontWeight: 600 }}>{agent.label}</div>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                      {filter === 'all' ? 'All agent communications' : `Direct channel with ${agent.label}`}
                    </div>
                  </div>
                </>
              );
            })()}
          </div>
          <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
            {messages.length} messages
          </div>
        </header>

        {/* ── Daily Briefing (pinned) ─────────────────────────────────────── */}
        {briefing && (
          <div style={{
            margin: '16px 24px 0',
            padding: 16,
            background: 'var(--bg-card)',
            border: '1px solid var(--accent-blue-dim)',
            borderLeft: '3px solid var(--accent-blue)',
            borderRadius: 'var(--radius)',
            animation: 'fadeIn 0.3s ease',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <div style={{
                  padding: '2px 8px', borderRadius: 4,
                  background: 'var(--accent-blue-dim)', color: 'var(--accent-blue)',
                  fontSize: 10, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.04em',
                }}>Daily Briefing</div>
                <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                  from {briefing.from_agent}
                </span>
              </div>
              <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                {formatTimestamp(briefing.created_at)}
              </span>
            </div>
            <div style={{
              fontSize: 13, lineHeight: 1.6, color: 'var(--text-primary)',
              whiteSpace: 'pre-wrap', fontFamily: 'var(--font-family)',
            }}>
              {getMessageText(briefing)}
            </div>
          </div>
        )}

        {/* ── Messages ────────────────────────────────────────────────────── */}
        <div style={{
          flex: 1, overflowY: 'auto', padding: '16px 24px',
          display: 'flex', flexDirection: 'column', gap: 4,
        }}>
          {messages.length === 0 && (
            <div style={{
              textAlign: 'center', color: 'var(--text-muted)', fontSize: 13,
              padding: '80px 20px',
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12,
            }}>
              <div style={{
                width: 48, height: 48, borderRadius: 12,
                background: 'var(--bg-card)', border: '1px solid var(--border)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: 20,
              }}>~</div>
              <div>No messages yet.</div>
              <div style={{ fontSize: 12, maxWidth: 320 }}>
                Send an instruction to the orchestrator to get started.
                Messages from agents will appear here in real-time.
              </div>
            </div>
          )}

          {messages.map((msg, i) => {
            const isUser = msg.from_agent === 'user';
            const agent = getAgentDef(isUser ? 'user' : msg.from_agent);
            const showDateSep = i === 0 || new Date(msg.created_at).toDateString() !== new Date(messages[i - 1].created_at).toDateString();
            const showAvatar = i === 0 || messages[i - 1].from_agent !== msg.from_agent || showDateSep;

            return (
              <div key={msg.id}>
                {/* Date separator */}
                {showDateSep && (
                  <div style={{
                    textAlign: 'center', margin: '16px 0 12px',
                    fontSize: 11, color: 'var(--text-muted)',
                    display: 'flex', alignItems: 'center', gap: 12,
                  }}>
                    <div style={{ flex: 1, height: 1, background: 'var(--border)' }} />
                    {new Date(msg.created_at).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' })}
                    <div style={{ flex: 1, height: 1, background: 'var(--border)' }} />
                  </div>
                )}

                {/* Message */}
                <div style={{
                  display: 'flex',
                  flexDirection: isUser ? 'row-reverse' : 'row',
                  alignItems: 'flex-start',
                  gap: 8,
                  marginTop: showAvatar ? 12 : 2,
                  paddingLeft: isUser ? 60 : 0,
                  paddingRight: isUser ? 0 : 60,
                }}>
                  {/* Avatar */}
                  {!isUser && showAvatar ? (
                    <div style={{
                      width: 28, height: 28, borderRadius: 6,
                      background: agent.color || 'var(--bg-input)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 11, fontWeight: 600,
                      color: msg.from_agent === 'orchestrator' ? 'white' : 'var(--text-secondary)',
                      fontFamily: 'var(--font-mono)',
                      flexShrink: 0,
                    }}>
                      {agent.icon}
                    </div>
                  ) : !isUser ? (
                    <div style={{ width: 28, flexShrink: 0 }} />
                  ) : null}

                  {/* Bubble */}
                  <div style={{ maxWidth: '75%', minWidth: 0 }}>
                    {/* Sender name + time */}
                    {showAvatar && (
                      <div style={{
                        fontSize: 11, marginBottom: 3,
                        display: 'flex', alignItems: 'center', gap: 8,
                        flexDirection: isUser ? 'row-reverse' : 'row',
                      }}>
                        <span style={{ fontWeight: 600, color: isUser ? 'var(--accent-blue)' : 'var(--text-secondary)' }}>
                          {isUser ? 'You' : agent.label}
                        </span>
                        <span style={{ color: 'var(--text-muted)', fontSize: 10 }}>
                          {formatTimestamp(msg.created_at)}
                        </span>
                        {msg.message_type !== 'instruction' && (
                          <span style={{
                            padding: '1px 6px', borderRadius: 3,
                            background: 'var(--bg-input)', color: 'var(--text-muted)',
                            fontSize: 9, fontFamily: 'var(--font-mono)',
                          }}>
                            {msg.message_type}
                          </span>
                        )}
                      </div>
                    )}

                    <div style={{
                      padding: '10px 14px',
                      borderRadius: isUser
                        ? (showAvatar ? '16px 16px 4px 16px' : '16px 4px 4px 16px')
                        : (showAvatar ? '16px 16px 16px 4px' : '4px 16px 16px 4px'),
                      fontSize: 13,
                      lineHeight: 1.55,
                      background: isUser ? 'var(--accent-blue)' : 'var(--bg-card)',
                      color: isUser ? 'white' : 'var(--text-primary)',
                      border: isUser ? 'none' : '1px solid var(--border)',
                      whiteSpace: 'pre-wrap',
                      wordBreak: 'break-word',
                    }}>
                      {getMessageText(msg)}
                    </div>

                    {/* Status indicator for user messages */}
                    {isUser && (
                      <div style={{
                        fontSize: 10, color: 'var(--text-muted)', textAlign: 'right',
                        marginTop: 2,
                      }}>
                        {msg.status === 'processed' ? 'Processed' : msg.status === 'read' ? 'Read' : 'Sent'}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
          <div ref={chatEndRef} />
        </div>

        {/* ── Input Area ──────────────────────────────────────────────────── */}
        <div style={{
          padding: '12px 24px 16px',
          borderTop: '1px solid var(--border)',
          background: 'var(--bg-primary)',
          flexShrink: 0,
        }}>
          {/* Target agent selector */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>To:</span>
            <select
              value={targetAgent}
              onChange={e => setTargetAgent(e.target.value)}
              style={{
                background: 'var(--bg-card)',
                border: '1px solid var(--border)',
                borderRadius: 6,
                padding: '4px 8px',
                color: 'var(--text-primary)',
                fontSize: 12,
                outline: 'none',
                fontFamily: 'var(--font-family)',
                cursor: 'pointer',
              }}
            >
              {AGENTS.map(a => (
                <option key={a.name} value={a.name}>{a.label}</option>
              ))}
            </select>
          </div>

          {/* Input + send */}
          <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end' }}>
            <textarea
              ref={inputRef}
              value={chatInput}
              onChange={e => setChatInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder={`Message ${getAgentDef(targetAgent).label}...`}
              rows={1}
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
                resize: 'none',
                minHeight: 42,
                maxHeight: 120,
                lineHeight: 1.5,
              }}
              onInput={(e) => {
                const el = e.currentTarget;
                el.style.height = 'auto';
                el.style.height = Math.min(el.scrollHeight, 120) + 'px';
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
                padding: '10px 20px',
                fontSize: 13,
                fontWeight: 500,
                cursor: chatInput.trim() ? 'pointer' : 'default',
                transition: 'all 0.15s ease',
                height: 42,
                flexShrink: 0,
              }}
            >
              {sending ? '...' : 'Send'}
            </button>
          </div>
          <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 4 }}>
            Press Enter to send, Shift+Enter for new line
          </div>
        </div>
      </main>
    </div>
  );
}
