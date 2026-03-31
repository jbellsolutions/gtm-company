'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

export default function DashboardRefreshButton() {
  const router = useRouter()
  const [refreshing, setRefreshing] = useState(false)

  const handleRefresh = () => {
    setRefreshing(true)
    router.refresh()
    setTimeout(() => setRefreshing(false), 800)
  }

  return (
    <button
      onClick={handleRefresh}
      className="text-xs text-zinc-500 hover:text-white transition-colors px-3 py-1.5 rounded border border-zinc-800 hover:border-zinc-600"
    >
      {refreshing ? 'Refreshing…' : 'Refresh'}
    </button>
  )
}
