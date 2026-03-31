/**
 * New Entity Form
 *
 * Creates a new record in DOMAIN.entityTable.
 * Submits to the API route, then redirects to the detail page.
 */

'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { DOMAIN, TIER_LABELS } from '@/lib/domain'
import Link from 'next/link'

export default function NewEntityPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    const form = e.currentTarget
    const data = Object.fromEntries(new FormData(form))

    // Strip empty strings
    const payload = Object.fromEntries(
      Object.entries(data).filter(([, v]) => v !== '')
    )

    try {
      const res = await fetch(`/api/${DOMAIN.entityNamePlural.toLowerCase()}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      })

      if (!res.ok) {
        const body = await res.json()
        setError(body.error ?? 'Failed to create record')
        return
      }

      const { id } = await res.json()
      router.push(`/${DOMAIN.entityNamePlural.toLowerCase()}/${id}`)
    } catch (err) {
      setError('Network error — please try again')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-zinc-950 text-white">
      {/* Header */}
      <header className="bg-zinc-900 border-b border-zinc-800 px-6 py-4 sticky top-0 z-10">
        <div className="max-w-2xl mx-auto flex items-center gap-4">
          <Link href="/dashboard" className="text-zinc-500 hover:text-white text-sm transition-colors">
            ← Dashboard
          </Link>
          <h1 className="text-base font-bold">New {DOMAIN.entityName}</h1>
        </div>
      </header>

      <div className="max-w-2xl mx-auto p-6">
        <form onSubmit={handleSubmit} className="bg-zinc-900 border border-zinc-800 rounded-lg p-6 space-y-5">

          {/* Core identity fields */}
          <Field label="Full Name" name="name" required placeholder="Jane Smith" />
          <Field label="Company" name="company" placeholder="Acme Corp" />
          <Field label="Email" name="email" type="email" placeholder="jane@acmecorp.com" />
          <Field label="Phone" name="phone" placeholder="+1 555 000 0000" />

          {/* Tier */}
          <div>
            <label className="block text-xs text-zinc-400 mb-1.5">Tier</label>
            <select
              name="tier"
              className="w-full bg-zinc-800 border border-zinc-700 rounded px-3 py-2 text-sm text-zinc-200 focus:outline-none focus:border-zinc-500"
            >
              <option value="">— Select tier —</option>
              {DOMAIN.tiers.map(t => (
                <option key={t.key} value={t.key}>{t.label}</option>
              ))}
            </select>
          </div>

          {/* Team size */}
          <Field label="Team Size" name="team_size" type="number" placeholder="5" />

          {/* Industry */}
          <Field label="Industry" name="industry" placeholder="Real Estate" />

          {/* Initial stage */}
          <div>
            <label className="block text-xs text-zinc-400 mb-1.5">Starting Stage</label>
            <select
              name="stage"
              defaultValue={DOMAIN.stages[0].key}
              className="w-full bg-zinc-800 border border-zinc-700 rounded px-3 py-2 text-sm text-zinc-200 focus:outline-none focus:border-zinc-500"
            >
              {DOMAIN.stages.map(s => (
                <option key={s.key} value={s.key}>{s.label}</option>
              ))}
            </select>
          </div>

          {/* Notes */}
          <div>
            <label className="block text-xs text-zinc-400 mb-1.5">Notes</label>
            <textarea
              name="notes"
              rows={3}
              placeholder="Any context from the initial conversation..."
              className="w-full bg-zinc-800 border border-zinc-700 rounded px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:outline-none focus:border-zinc-500 resize-none"
            />
          </div>

          {error && (
            <p className="text-sm text-red-400">{error}</p>
          )}

          <div className="flex items-center justify-end gap-3 pt-2">
            <Link
              href="/dashboard"
              className="text-xs text-zinc-500 hover:text-white transition-colors"
            >
              Cancel
            </Link>
            <button
              type="submit"
              disabled={loading}
              className="text-xs bg-white text-zinc-900 px-4 py-2 rounded font-medium hover:bg-zinc-100 transition-colors disabled:opacity-50"
            >
              {loading ? 'Creating…' : `Add ${DOMAIN.entityName}`}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function Field({
  label, name, required, placeholder, type = 'text'
}: {
  label: string
  name: string
  required?: boolean
  placeholder?: string
  type?: string
}) {
  return (
    <div>
      <label className="block text-xs text-zinc-400 mb-1.5">
        {label}{required && <span className="text-red-500 ml-0.5">*</span>}
      </label>
      <input
        name={name}
        type={type}
        required={required}
        placeholder={placeholder}
        className="w-full bg-zinc-800 border border-zinc-700 rounded px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:outline-none focus:border-zinc-500"
      />
    </div>
  )
}
