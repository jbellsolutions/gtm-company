import { DOMAIN } from '@/lib/domain'

interface Props {
  stage: string
}

export default function NextActionBanner({ stage }: Props) {
  const action = DOMAIN.nextActions[stage as keyof typeof DOMAIN.nextActions]

  if (!action) return null

  return (
    <div className="bg-zinc-900 border border-zinc-700 rounded-lg p-4">
      <div className="flex items-start gap-3">
        <div className="w-2 h-2 rounded-full bg-blue-500 mt-1.5 flex-shrink-0" />
        <div>
          <p className="text-sm font-semibold text-zinc-200">{action.label}</p>
          <p className="text-xs text-zinc-500 mt-1">{action.detail}</p>
        </div>
      </div>
    </div>
  )
}
