/**
 * domain.ts — GTM Command Center configuration
 *
 * Jordan (Head of Growth) owns the full go-to-market machine:
 * cold email, LinkedIn, phone calls, social SDR, power partners,
 * content engine, YouTube pipeline.
 */

export const DOMAIN = {
  // ── Company ──────────────────────────────────────────────────────────────
  companyName: 'AI Integraterz GTM',
  ceoName: 'Justin Bell',
  agentName: 'Jordan',
  agentTitle: 'Head of Growth',
  opsChannel: 'gtm-ops',

  // ── Entity naming ─────────────────────────────────────────────────────────
  entityName: 'Campaign',
  entityNamePlural: 'Campaigns',
  entityTable: 'campaigns',
  entityOutputsTable: 'campaign_outputs',

  // ── Pipeline stages (in order) ───────────────────────────────────────────
  stages: [
    { key: 'draft',     label: 'Draft',      color: 'zinc'    },
    { key: 'queued',    label: 'Queued',      color: 'blue'    },
    { key: 'running',   label: 'Running',     color: 'green'   },
    { key: 'paused',    label: 'Paused',      color: 'yellow'  },
    { key: 'replied',   label: 'Replied',     color: 'cyan'    },
    { key: 'converted', label: 'Converted',   color: 'emerald' },
    { key: 'closed',    label: 'Closed',      color: 'red'     },
  ] as const,

  // ── Tiers / channel types ─────────────────────────────────────────────────
  tiers: [
    { key: 'cold_email',     label: 'Cold Email',       price: '$0' },
    { key: 'linkedin',       label: 'LinkedIn',          price: '$0' },
    { key: 'phone',          label: 'Phone / Voicemail', price: '$0' },
    { key: 'social_sdr',     label: 'Social SDR (FB/IG)', price: '$0' },
    { key: 'partner',        label: 'Power Partnership',  price: '$0' },
    { key: 'content',        label: 'Content Drop',       price: '$0' },
    { key: 'youtube',        label: 'YouTube',             price: '$0' },
  ] as const,

  // ── Revenue config ────────────────────────────────────────────────────────
  recurringTierKey: 'partner',
  recurringPricePerSeat: 0,

  // ── Specialist agents (Jordan's team) ─────────────────────────────────────
  specialists: [
    { name: 'Email Sequencer',      runs: 'email-sequencer'      },
    { name: 'Reply Handler',        runs: 'reply-handler'        },
    { name: 'LinkedIn Bot',         runs: 'linkedin-autopilot'   },
    { name: 'LinkedIn Engager',     runs: 'linkedin-engage'      },
    { name: 'Titans Council',       runs: 'titans-council'       },
    { name: 'Content Multiplier',   runs: 'content-multiplier'   },
    { name: 'YouTube Editor',       runs: 'youtube-pipeline'     },
    { name: 'Call Center Agent',    runs: 'call-center'          },
    { name: 'Social SDR (FB/IG)',   runs: 'social-sdr'           },
    { name: 'Partner Recruiter',    runs: 'partner-recruiter'    },
    { name: 'Lead Router',          runs: 'lead-router'          },
    { name: 'Weekly Strategist',    runs: 'weekly-strategist'    },
  ] as const,

  // ── Next actions (shown in the banner per stage) ──────────────────────────
  nextActions: {
    draft:     { label: 'Finish campaign setup',                detail: 'Define sequence, targeting, channel, and send schedule.' },
    queued:    { label: 'Campaign queued — ready to launch',    detail: 'Review sequence one more time, then launch.' },
    running:   { label: 'Live — monitor replies and engagement', detail: 'Check reply inbox daily. Jordan handles follow-ups automatically.' },
    paused:    { label: 'Paused — review and resume',           detail: 'Diagnose why paused. Fix the issue and re-queue.' },
    replied:   { label: 'Reply received — respond',             detail: 'Jordan handles the reply. Escalates qualified leads to Justin.' },
    converted: { label: 'Converted — hand to ops',              detail: 'Pass to Morgan for client onboarding.' },
    closed:    { label: 'Closed — archive',                     detail: 'Document results and lessons learned.' },
  },
} as const

// ── Type helpers ───────────────────────────────────────────────────────────────

export type Stage = typeof DOMAIN.stages[number]['key']
export type Tier  = typeof DOMAIN.tiers[number]['key']

export const STAGE_LABELS: Record<string, string> = Object.fromEntries(
  DOMAIN.stages.map(s => [s.key, s.label])
)

export const TIER_LABELS: Record<string, string> = Object.fromEntries(
  DOMAIN.tiers.map(t => [t.key, t.label])
)

export const STAGE_COLORS: Record<string, string> = {
  draft:     'border-zinc-700 text-zinc-400',
  queued:    'border-blue-700 text-blue-400',
  running:   'border-green-700 text-green-400',
  paused:    'border-yellow-700 text-yellow-400',
  replied:   'border-cyan-700 text-cyan-400',
  converted: 'border-emerald-700 text-emerald-400',
  closed:    'border-red-800 text-red-500',
}
