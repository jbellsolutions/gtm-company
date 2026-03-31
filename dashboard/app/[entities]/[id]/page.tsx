/**
 * Entity Detail Page
 *
 * Shows the full record for one entity (client, project, campaign, etc.)
 * - Stage badge + next action banner
 * - All field values
 * - Outputs/deliverables table with approve buttons
 * - Pipeline event history
 * - Advance stage button
 */

import { supabaseAdmin } from '@/lib/supabase'
import { DOMAIN, STAGE_LABELS, STAGE_COLORS, TIER_LABELS } from '@/lib/domain'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import NextActionBanner from '@/components/NextActionBanner'
import AdvanceButton from '@/components/AdvanceButton'
import ApproveButton from '@/components/ApproveButton'

function formatDate(dateStr: string | null): string {
  if (!dateStr) return '—'
  return new Date(dateStr).toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric'
  })
}

interface Props {
  params: { entities: string; id: string }
}

export default async function EntityDetailPage({ params }: Props) {
  const { id } = params

  // Fetch the entity
  const { data: entity, error } = await supabaseAdmin
    .from(DOMAIN.entityTable)
    .select('*')
    .eq('id', id)
    .single()

  if (error || !entity) notFound()

  // Fetch outputs/deliverables
  const { data: outputs } = await supabaseAdmin
    .from(DOMAIN.entityOutputsTable)
    .select('*')
    .eq('client_id', id)
    .order('created_at', { ascending: false })

  // Fetch pipeline events
  const { data: events } = await supabaseAdmin
    .from('campaign_events')
    .select('*')
    .eq('entity_id', id)
    .order('created_at', { ascending: false })
    .limit(20)

  const stageColor = STAGE_COLORS[entity.stage] ?? 'border-zinc-700 text-zinc-400'

  return (
    <div className="min-h-screen bg-zinc-950 text-white">
      {/* Header */}
      <header className="bg-zinc-900 border-b border-zinc-800 px-6 py-4 sticky top-0 z-10">
        <div className="max-w-5xl mx-auto flex items-center gap-4 flex-wrap">
          <Link href="/dashboard" className="text-zinc-500 hover:text-white text-sm transition-colors">
            ← Dashboard
          </Link>
          <h1 className="text-base font-bold">{entity.name}</h1>
          {entity.company && (
            <span className="text-zinc-500 text-sm">{entity.company}</span>
          )}
          <span className={`ml-auto text-xs border px-2 py-0.5 rounded-full ${stageColor}`}>
            {STAGE_LABELS[entity.stage] ?? entity.stage}
          </span>
          <AdvanceButton entityId={id} currentStage={entity.stage} />
        </div>
      </header>

      <div className="max-w-5xl mx-auto p-6 grid grid-cols-3 gap-6">

        {/* Left: next action + details */}
        <div className="col-span-2 space-y-6">

          {/* Next action banner */}
          <NextActionBanner stage={entity.stage} />

          {/* Details card */}
          <div className="bg-zinc-900 border border-zinc-800 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800">
              <h3 className="text-sm font-semibold text-zinc-200">{DOMAIN.entityName} Details</h3>
            </div>
            <div className="p-4 grid grid-cols-2 gap-x-8 gap-y-3">
              {entity.name && (
                <Detail label="Name" value={entity.name} />
              )}
              {entity.company && (
                <Detail label="Company" value={entity.company} />
              )}
              {entity.email && (
                <Detail label="Email" value={entity.email} />
              )}
              {entity.phone && (
                <Detail label="Phone" value={entity.phone} />
              )}
              {entity.tier && (
                <Detail label="Tier" value={TIER_LABELS[entity.tier] ?? entity.tier} />
              )}
              {entity.team_size && (
                <Detail label="Team Size" value={String(entity.team_size)} />
              )}
              {entity.industry && (
                <Detail label="Industry" value={entity.industry} />
              )}
              <Detail label="Created" value={formatDate(entity.created_at)} />
              {entity.notes && (
                <div className="col-span-2">
                  <p className="text-xs text-zinc-500 mb-1">Notes</p>
                  <p className="text-sm text-zinc-300 whitespace-pre-wrap">{entity.notes}</p>
                </div>
              )}
            </div>
          </div>

          {/* Outputs */}
          {(outputs ?? []).length > 0 && (
            <div className="bg-zinc-900 border border-zinc-800 rounded-lg overflow-hidden">
              <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
                <h3 className="text-sm font-semibold text-zinc-200">Deliverables</h3>
                <span className="text-xs text-zinc-600">{(outputs ?? []).length} items</span>
              </div>
              <div className="divide-y divide-zinc-800/50">
                {(outputs ?? []).map((output: any) => (
                  <div key={output.id} className="px-4 py-3 flex items-center gap-3">
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-zinc-200 truncate">{output.output_type}</p>
                      {output.file_path && (
                        <p className="text-xs text-zinc-600 font-mono truncate mt-0.5">{output.file_path}</p>
                      )}
                      <p className="text-xs text-zinc-600 mt-0.5">{formatDate(output.created_at)}</p>
                    </div>
                    {output.approved ? (
                      <span className="text-xs text-green-400">Approved</span>
                    ) : (
                      <ApproveButton
                        entityId={id}
                        outputId={output.id}
                        outputType={output.output_type}
                      />
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Right: pipeline history */}
        <div className="space-y-5">

          {/* Stage history */}
          <div className="bg-zinc-900 border border-zinc-800 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800">
              <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">Pipeline History</h3>
            </div>
            <div className="divide-y divide-zinc-800/50 max-h-80 overflow-y-auto">
              {(events ?? []).length === 0 ? (
                <div className="px-4 py-6 text-center">
                  <p className="text-xs text-zinc-600">No events yet</p>
                </div>
              ) : (
                (events ?? []).map((event: any) => (
                  <div key={event.id} className="px-4 py-2.5">
                    <p className="text-xs text-zinc-300">{event.event_type ?? event.to_stage}</p>
                    {event.note && (
                      <p className="text-xs text-zinc-600 mt-0.5">{event.note}</p>
                    )}
                    <p className="text-xs text-zinc-700 mt-0.5">{formatDate(event.created_at)}</p>
                  </div>
                ))
              )}
            </div>
          </div>

          {/* Quick links */}
          <div className="bg-zinc-900 border border-zinc-800 rounded-lg p-4">
            <h3 className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-3">Quick Links</h3>
            <div className="space-y-2">
              <Link
                href="/dashboard"
                className="block text-xs text-zinc-500 hover:text-white transition-colors"
              >
                ← Back to Dashboard
              </Link>
              <Link
                href="/operations"
                className="block text-xs text-zinc-500 hover:text-white transition-colors"
              >
                Operations Tab
              </Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function Detail({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-zinc-500">{label}</p>
      <p className="text-sm text-zinc-200 mt-0.5">{value}</p>
    </div>
  )
}
