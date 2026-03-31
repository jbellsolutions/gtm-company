/**
 * POST /api/[entities]/[id]/approve-output
 * Mark a deliverable as approved
 *
 * Body: { outputId: string }
 */

import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase'
import { DOMAIN } from '@/lib/domain'

interface Params { params: { id: string } }

export async function POST(req: NextRequest, { params }: Params) {
  const { outputId } = await req.json()

  if (!outputId) return NextResponse.json({ error: 'outputId is required' }, { status: 400 })

  const { error } = await supabaseAdmin
    .from(DOMAIN.entityOutputsTable)
    .update({ approved: true, approved_at: new Date().toISOString() })
    .eq('id', outputId)
    .eq('client_id', params.id) // safety: only approve outputs for this entity

  if (error) return NextResponse.json({ error: error.message }, { status: 400 })

  return NextResponse.json({ success: true })
}
