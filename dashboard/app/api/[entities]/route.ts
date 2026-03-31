/**
 * POST /api/[entities]
 * Create a new entity record
 */

import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase'
import { DOMAIN } from '@/lib/domain'

export async function POST(req: NextRequest) {
  try {
    const body = await req.json()

    const { data, error } = await supabaseAdmin
      .from(DOMAIN.entityTable)
      .insert({
        ...body,
        stage: body.stage ?? DOMAIN.stages[0].key,
      })
      .select('id')
      .single()

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 })
    }

    // Log pipeline event
    try {
      await supabaseAdmin.from('campaign_events').insert({
        entity_id: data.id,
        event_type: 'created',
        to_stage: body.stage ?? DOMAIN.stages[0].key,
        note: 'Record created',
      })
    } catch { /* table may not exist in all installs */ }

    return NextResponse.json({ id: data.id }, { status: 201 })
  } catch (err) {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
