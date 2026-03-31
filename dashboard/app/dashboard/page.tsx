import { supabaseAdmin } from '@/lib/supabase'
import { DOMAIN, STAGE_LABELS, STAGE_COLORS, TIER_LABELS } from '@/lib/domain'
import Link from 'next/link'
import DashboardRefreshButton from '@/components/DashboardRefreshButton'

// ── Revenue helpers ────────────────────────────────────────────────────────────

function calcRevenue(entities: any[]) {
  const active = entities.filter(e => e.stage === 'active')
  const mrr = active.reduce((sum, e) => {
    if (e.tier === DOMAIN.recurringTierKey) {
      return sum + (e.team_size ?? 1) * DOMAIN.recurringPricePerSeat
    }
    return sum
  }, 0)

  const pipelineValue = entities
    .filter(e => !['active', 'closed_lost'].includes(e.stage))
    .reduce((sum, e) => {
      const tier = DOMAIN.tiers.find(t => t.key === e.tier)
      if (!tier) return sum
      const price = parseInt(tier.price.replace(/[^0-9]/g, '') || '0')
      return sum + price
    }, 0)

  const newThisMonth = entities.filter(e => {
    const d = new Date(e.created_at)
    const now = new Date()
    return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()
  }).length

  return { mrr, arr: mrr * 12, pipelineValue, newThisMonth, activeCount: active.length }
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default async function DashboardPage() {
  const { data: entities, error } = await supabaseAdmin
    .from(DOMAIN.entityTable)
    .select('*')
    .order('created_at', { ascending: false })

  if (error) {
    return (
      <div className="min-h-screen bg-zinc-950 text-white flex items-center justify-center">
        <div className="bg-red-900/30 border border-red-800 rounded-lg p-6 max-w-md text-center">
          <p className="text-red-400 font-semibold">Database error</p>
          <p className="text-zinc-400 text-sm mt-1">{error.message}</p>
        </div>
      </div>
    )
  }

  const all = entities ?? []
  const { mrr, arr, pipelineValue, newThisMonth, activeCount } = calcRevenue(all)

  // Group by stage for kanban
  const byStage: Record<string, any[]> = {}
  DOMAIN.stages.forEach(s => { byStage[s.key] = [] })
  all.forEach(e => {
    if (byStage[e.stage]) byStage[e.stage].push(e)
    else byStage['active']?.push(e)  // fallback for unknown stages
  })

  const activeStages = DOMAIN.stages.filter(s => byStage[s.key]?.length > 0)

  return (
    <div className="min-h-screen bg-zinc-950 text-white">
      {/* Header */}
      <header className="bg-zinc-900 border-b border-zinc-800 px-6 py-4 sticky top-0 z-10">
        <div className="max-w-[1600px] mx-auto flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <h1 className="text-base font-bold">{DOMAIN.companyName}</h1>
            <span className="text-zinc-600 text-sm">Operations Hub</span>
          </div>
          <div className="flex items-center gap-3">
            <Link
              href="/operations"
              className="text-xs text-zinc-500 hover:text-white transition-colors px-3 py-1.5 rounded border border-zinc-800 hover:border-zinc-600"
            >
              Operations
            </Link>
            <Link
              href={`/${DOMAIN.entityNamePlural.toLowerCase()}/new`}
              className="text-xs bg-white text-zinc-900 px-3 py-1.5 rounded font-medium hover:bg-zinc-100 transition-colors"
            >
              + New {DOMAIN.entityName}
            </Link>
            <DashboardRefreshButton />
          </div>
        </div>
      </header>

      {/* Revenue bar */}
      <div className="border-b border-zinc-800 bg-zinc-900/50">
        <div className="max-w-[1600px] mx-auto px-6 py-3 flex items-center gap-8 text-sm overflow-x-auto">
          <div>
            <span className="text-zinc-500 text-xs">MRR</span>
            <span className="ml-2 font-mono font-semibold text-green-400">
              ${mrr.toLocaleString()}/mo
            </span>
          </div>
          <div>
            <span className="text-zinc-500 text-xs">ARR</span>
            <span className="ml-2 font-mono font-semibold text-emerald-400">
              ${arr.toLocaleString()}/yr
            </span>
          </div>
          <div>
            <span className="text-zinc-500 text-xs">Pipeline</span>
            <span className="ml-2 font-mono text-zinc-300">
              ${pipelineValue.toLocaleString()}
            </span>
          </div>
          <div>
            <span className="text-zinc-500 text-xs">Active</span>
            <span className="ml-2 font-mono text-zinc-300">{activeCount}</span>
          </div>
          <div>
            <span className="text-zinc-500 text-xs">New this month</span>
            <span className="ml-2 font-mono text-zinc-300">{newThisMonth}</span>
          </div>
        </div>
      </div>

      {/* Kanban */}
      <div className="max-w-[1600px] mx-auto p-6">
        {all.length === 0 ? (
          <div className="text-center py-20">
            <p className="text-zinc-500">No {DOMAIN.entityNamePlural.toLowerCase()} yet.</p>
            <Link
              href={`/${DOMAIN.entityNamePlural.toLowerCase()}/new`}
              className="mt-4 inline-block text-sm text-zinc-400 hover:text-white transition-colors"
            >
              Add your first {DOMAIN.entityName.toLowerCase()} →
            </Link>
          </div>
        ) : (
          <div className="flex gap-4 overflow-x-auto pb-4">
            {activeStages.map(stage => (
              <div key={stage.key} className="flex-shrink-0 w-72">
                {/* Column header */}
                <div className="flex items-center justify-between mb-3 px-1">
                  <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">
                    {stage.label}
                  </h3>
                  <span className="text-xs text-zinc-600 tabular-nums">
                    {byStage[stage.key].length}
                  </span>
                </div>

                {/* Cards */}
                <div className="space-y-2">
                  {byStage[stage.key].map((entity: any) => (
                    <Link
                      key={entity.id}
                      href={`/${DOMAIN.entityNamePlural.toLowerCase()}/${entity.id}`}
                      className="block bg-zinc-900 border border-zinc-800 rounded-lg p-3 hover:border-zinc-600 transition-colors"
                    >
                      <p className="text-sm font-medium text-zinc-200 truncate">
                        {entity.name}
                      </p>
                      {entity.company && (
                        <p className="text-xs text-zinc-500 truncate mt-0.5">
                          {entity.company}
                        </p>
                      )}
                      {entity.tier && (
                        <span className="inline-block mt-2 text-xs bg-zinc-800 text-zinc-400 px-1.5 py-0.5 rounded">
                          {TIER_LABELS[entity.tier] ?? entity.tier}
                        </span>
                      )}
                      {entity.team_size && (
                        <span className="ml-1 inline-block text-xs text-zinc-600">
                          {entity.team_size} people
                        </span>
                      )}
                    </Link>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
