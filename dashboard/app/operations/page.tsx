/**
 * Operations Tab — the "agent office"
 *
 * Shows the live state of the agent team:
 * - Org chart with real names and job titles
 * - Agent activity feed (what Morgan did and when)
 * - Heartbeat status (last seen)
 * - Pending upsell signals
 */

import { supabaseAdmin } from '@/lib/supabase'
import { DOMAIN } from '@/lib/domain'
import Link from 'next/link'

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  return `${Math.floor(hrs / 24)}d ago`
}

// All org data is driven by domain.ts — no hardcoding needed here
// DOMAIN.ceoName, DOMAIN.agentName, DOMAIN.agentTitle, DOMAIN.specialists

export default async function OperationsPage() {
  // Agent run log
  // Note: the join alias matches the actual Supabase table name (DOMAIN.entityTable).
  // If your table is "clients", PostgREST exposes it as "clients(...)".
  // If your table is "entities" (default schema), change the join alias below to "entities".
  const { data: runLog } = await supabaseAdmin
    .from('agent_run_log')
    .select(`*, ${DOMAIN.entityTable}(name, company)`)
    .order('created_at', { ascending: false })
    .limit(50)

  // Pending upsell signals
  const { data: signals } = await supabaseAdmin
    .from('agent_upsell_log')
    .select(`*, ${DOMAIN.entityTable}(name, company, tier)`)
    .eq('actioned', false)
    .order('posted_at', { ascending: false })

  // Last heartbeat (most recent agent_run_log entry with action = 'heartbeat')
  const lastHeartbeat = (runLog ?? []).find(r => r.action === 'heartbeat')

  return (
    <div className="min-h-screen bg-zinc-950 text-white">
      {/* Header */}
      <header className="bg-zinc-900 border-b border-zinc-800 px-6 py-4 sticky top-0 z-10">
        <div className="max-w-7xl mx-auto flex items-center gap-4">
          <Link href="/dashboard" className="text-zinc-500 hover:text-white text-sm transition-colors">
            ← Dashboard
          </Link>
          <h1 className="text-base font-bold">Operations</h1>
          <span className="text-xs text-zinc-600">Agent team status + activity</span>
        </div>
      </header>

      <div className="max-w-7xl mx-auto p-6 grid grid-cols-3 gap-6">

        {/* Left 2/3 — Org chart + Activity */}
        <div className="col-span-2 space-y-6">

          {/* Org chart */}
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800">
              <h3 className="text-sm font-semibold text-zinc-200">{DOMAIN.companyName} — Operations Org</h3>
            </div>
            <div className="p-4 space-y-4">
              {/* CEO */}
              <div className="flex items-center gap-3">
                <div className="w-2 h-2 rounded-full bg-green-500 flex-shrink-0" />
                <div>
                  <p className="text-sm font-medium text-zinc-200">{DOMAIN.ceoName}</p>
                  <p className="text-xs text-zinc-500">CEO — Human</p>
                </div>
                <span className="ml-auto text-xs bg-green-900/30 text-green-400 px-2 py-0.5 rounded-full">online</span>
              </div>

              {/* Head of Operations */}
              <div className="ml-6 flex items-start gap-3">
                <div className="flex flex-col items-center">
                  <div className="w-px h-4 bg-zinc-700" />
                  <div className="w-2 h-2 rounded-full bg-blue-500 flex-shrink-0" />
                </div>
                <div className="flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <p className="text-sm font-medium text-zinc-200">{DOMAIN.agentName}</p>
                    <span className="text-xs text-zinc-500">{DOMAIN.agentTitle} — AI Agent</span>
                    {lastHeartbeat ? (
                      <span className="ml-auto text-xs bg-blue-900/30 text-blue-400 px-2 py-0.5 rounded-full">
                        last heartbeat {timeAgo(lastHeartbeat.created_at)}
                      </span>
                    ) : (
                      <span className="ml-auto text-xs bg-zinc-800 text-zinc-500 px-2 py-0.5 rounded-full">
                        not yet running
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-zinc-600 mt-0.5">
                    Manages the full client pipeline · Slack: #{DOMAIN.opsChannel}
                  </p>

                  {/* Specialists */}
                  <div className="mt-3 grid grid-cols-2 gap-1.5">
                    {DOMAIN.specialists.map(s => (
                      <div key={s.runs} className="flex items-center gap-2 bg-zinc-800/50 rounded px-2 py-1.5">
                        <div className="w-1.5 h-1.5 rounded-full bg-zinc-600 flex-shrink-0" />
                        <div className="min-w-0">
                          <p className="text-xs text-zinc-300 truncate">{s.name}</p>
                          <p className="text-xs text-zinc-600 font-mono truncate">{s.runs}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Activity feed */}
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-zinc-200">Activity Feed</h3>
              <span className="text-xs text-zinc-600">{(runLog ?? []).length} recent actions</span>
            </div>
            <div className="divide-y divide-zinc-800/50 max-h-[500px] overflow-y-auto">
              {(runLog ?? []).length === 0 ? (
                <div className="px-4 py-8 text-center">
                  <p className="text-xs text-zinc-600">No activity yet. Agent will log actions here once running.</p>
                </div>
              ) : (
                (runLog ?? []).map((entry: any) => {
                  // PostgREST returns the join keyed by the actual table name
                  const entityJoin = entry[DOMAIN.entityTable]
                  return (
                  <div key={entry.id} className="px-4 py-3 flex items-start gap-3">
                    <div className="w-1.5 h-1.5 rounded-full bg-zinc-600 mt-1.5 flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-zinc-300">{entry.action}</p>
                      {entityJoin && (
                        <p className="text-xs text-zinc-500 mt-0.5">
                          {entityJoin.name} · {entityJoin.company}
                        </p>
                      )}
                    </div>
                    <span className="text-xs text-zinc-600 flex-shrink-0">{timeAgo(entry.created_at)}</span>
                  </div>
                  )
                })
              )}
            </div>
          </div>
        </div>

        {/* Right 1/3 — Signals + Status */}
        <div className="space-y-5">

          {/* Heartbeat status */}
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 p-4">
            <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">Agent Status</h3>
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs text-zinc-500">Name</span>
                <span className="text-xs text-zinc-200">{DOMAIN.agentName}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-xs text-zinc-500">Role</span>
                <span className="text-xs text-zinc-200">{DOMAIN.agentTitle}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-xs text-zinc-500">Last heartbeat</span>
                <span className="text-xs text-zinc-200">
                  {lastHeartbeat ? timeAgo(lastHeartbeat.created_at) : 'Not started'}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-xs text-zinc-500">Slack channel</span>
                <span className="text-xs text-zinc-400 font-mono">#{DOMAIN.opsChannel}</span>
              </div>
            </div>
          </div>

          {/* Pending upsell signals */}
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
              <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">Upsell Signals</h3>
              {(signals ?? []).length > 0 && (
                <span className="text-xs bg-yellow-900/30 text-yellow-400 px-2 py-0.5 rounded-full">
                  {(signals ?? []).length} pending
                </span>
              )}
            </div>
            <div className="divide-y divide-zinc-800 max-h-80 overflow-y-auto">
              {(signals ?? []).length === 0 ? (
                <div className="px-4 py-6 text-center">
                  <p className="text-xs text-zinc-600">No pending signals</p>
                </div>
              ) : (
                (signals ?? []).map((signal: any) => {
                  // PostgREST returns the join keyed by the actual table name
                  const entityJoin = signal[DOMAIN.entityTable]
                  return (
                  <div key={signal.id} className="px-4 py-3">
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-medium text-zinc-200 truncate">
                          {entityJoin?.company ?? 'Unknown'}
                        </p>
                        <p className="text-xs text-zinc-500 mt-0.5">{signal.signal_type}</p>
                        <p className="text-xs text-zinc-700 mt-0.5">{timeAgo(signal.posted_at)}</p>
                      </div>
                    </div>
                  </div>
                  )
                })
              )}
            </div>
          </div>

          {/* Setup instructions (shown when agent not running) */}
          {!lastHeartbeat && (
            <div className="bg-zinc-900 rounded-lg border border-zinc-700 p-4">
              <h3 className="text-xs font-semibold text-yellow-400 mb-2">Agent Not Running</h3>
              <p className="text-xs text-zinc-400 leading-relaxed">
                {DOMAIN.agentName} is not active yet. To start:
              </p>
              <pre className="text-xs text-zinc-500 mt-2 bg-zinc-800 rounded p-2 overflow-x-auto">
{`cd agent-core
python main.py`}
              </pre>
              <p className="text-xs text-zinc-600 mt-2">
                See the README for full setup instructions.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
