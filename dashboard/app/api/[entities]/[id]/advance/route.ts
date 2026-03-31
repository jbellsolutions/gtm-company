/**
 * POST /api/[entities]/[id]/advance
 * Advance entity to the next pipeline stage
 *
 * Body: { stage: string }
 */

import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase'
import { DOMAIN } from '@/lib/domain'

interface Params { params: { id: string } }

export async function POST(req: NextRequest, { params }: Params) {
  const { stage } = await req.json()

  if (!stage) return NextResponse.json({ error: 'stage is required' }, { status: 400 })

  const validStages = DOMAIN.stages.map(s => s.key as string)
  if (!validStages.includes(stage)) {
    return NextResponse.json({ error: `Invalid stage: ${stage}` }, { status: 400 })
  }

  // Fetch current stage for the event log
  const { data: current } = await supabaseAdmin
    .from(DOMAIN.entityTable)
    .select('stage')
    .eq('id', params.id)
    .single()

  // Update stage
  const { error } = await supabaseAdmin
    .from(DOMAIN.entityTable)
    .update({ stage })
    .eq('id', params.id)

  if (error) return NextResponse.json({ error: error.message }, { status: 400 })

  // Log pipeline event
  try {
    await supabaseAdmin.from('campaign_events').insert({
      entity_id: params.id,
      event_type: 'stage_change',
      from_stage: current?.stage ?? null,
      to_stage: stage,
      note: `Advanced to ${stage}`,
    })
  } catch { /* table may not exist */ }

  return NextResponse.json({ success: true, stage })
}
