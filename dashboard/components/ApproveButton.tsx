'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { DOMAIN } from '@/lib/domain'

interface Props {
  entityId: string
  outputId: string
  outputType: string
}

export default function ApproveButton({ entityId, outputId, outputType }: Props) {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [done, setDone] = useState(false)

  const handleApprove = async () => {
    setLoading(true)
    try {
      const res = await fetch(`/api/${DOMAIN.entityNamePlural.toLowerCase()}/${entityId}/approve-output`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ outputId }),
      })
      if (res.ok) {
        setDone(true)
        router.refresh()
      }
    } finally {
      setLoading(false)
    }
  }

  if (done) {
    return (
      <span className="text-xs text-green-400 font-medium">Approved</span>
    )
  }

  return (
    <button
      onClick={handleApprove}
      disabled={loading}
      className="text-xs text-green-400 border border-green-800 px-2 py-1 rounded hover:bg-green-900/20 transition-colors disabled:opacity-50"
    >
      {loading ? 'Saving…' : 'Approve'}
    </button>
  )
}
