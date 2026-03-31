'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { DOMAIN, STAGE_LABELS } from '@/lib/domain'

interface Props {
  entityId: string
  currentStage: string
}

export default function AdvanceButton({ entityId, currentStage }: Props) {
  const router = useRouter()
  const [loading, setLoading] = useState(false)

  const stages = DOMAIN.stages.map(s => s.key)
  const currentIndex = stages.indexOf(currentStage as any)
  const nextStage = currentIndex >= 0 && currentIndex < stages.length - 1
    ? stages[currentIndex + 1]
    : null

  if (!nextStage || currentStage === 'active' || currentStage === 'closed_lost') return null

  const handleAdvance = async () => {
    setLoading(true)
    try {
      const res = await fetch(`/api/${DOMAIN.entityNamePlural.toLowerCase()}/${entityId}/advance`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ stage: nextStage }),
      })
      if (res.ok) {
        router.refresh()
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <button
      onClick={handleAdvance}
      disabled={loading}
      className="text-xs bg-white text-zinc-900 px-3 py-1.5 rounded font-medium hover:bg-zinc-100 transition-colors disabled:opacity-50"
    >
      {loading ? 'Moving…' : `Move to ${STAGE_LABELS[nextStage] ?? nextStage}`}
    </button>
  )
}
