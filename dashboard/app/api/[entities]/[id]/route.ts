/**
 * GET    /api/[entities]/[id]  — Fetch one entity
 * PATCH  /api/[entities]/[id]  — Update fields
 * DELETE /api/[entities]/[id]  — Delete entity
 */

import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase'
import { DOMAIN } from '@/lib/domain'

interface Params { params: { id: string } }

export async function GET(_req: NextRequest, { params }: Params) {
  const { data, error } = await supabaseAdmin
    .from(DOMAIN.entityTable)
    .select('*')
    .eq('id', params.id)
    .single()

  if (error || !data) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json(data)
}

export async function PATCH(req: NextRequest, { params }: Params) {
  const body = await req.json()

  const { data, error } = await supabaseAdmin
    .from(DOMAIN.entityTable)
    .update(body)
    .eq('id', params.id)
    .select()
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 400 })
  return NextResponse.json(data)
}

export async function DELETE(_req: NextRequest, { params }: Params) {
  const { error } = await supabaseAdmin
    .from(DOMAIN.entityTable)
    .delete()
    .eq('id', params.id)

  if (error) return NextResponse.json({ error: error.message }, { status: 400 })
  return NextResponse.json({ success: true })
}
