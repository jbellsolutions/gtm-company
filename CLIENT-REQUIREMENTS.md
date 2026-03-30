# GTM Company -- Client Requirements Checklist

Everything you need to prepare before installation. Complete this checklist, then follow [SETUP.md](SETUP.md) to install.

---

## Accounts to Create

Create these accounts before your onboarding session.

- [ ] **Anthropic API** -- https://console.anthropic.com -- Create account, add billing, generate API key
- [ ] **Supabase** -- https://supabase.com -- Sign up (free tier), create a new project
- [ ] **VPS provider** -- https://cloud.digitalocean.com (recommended) or Hetzner or any Linux VPS
- [ ] **Gmail** -- https://accounts.google.com -- Create a dedicated outreach email (separate from personal)
- [ ] **Calendar booking tool** -- https://cal.com (recommended) or https://calendly.com -- Create booking page
- [ ] **LinkedIn** -- https://linkedin.com -- Active account (Premium helpful for InMail and analytics, not required)

### Optional Accounts

- [ ] **SmartLead** ($39/mo) -- https://smartlead.ai -- For scaled email sending with inbox warmup
- [ ] **Firecrawl** (free tier) -- https://firecrawl.dev/app/api-keys -- For prospect research and web scraping

---

## Business Information to Prepare

Have this information ready in a document or notes. The system uses it to configure agent behavior, write emails, generate content, and qualify leads.

### Core Business Details

- [ ] Company name
- [ ] Company website URL
- [ ] One-sentence company mission / what you do

### Target Customer (ICP)

- [ ] Description of your ideal customer (who they are, company size, revenue range)
- [ ] Target industries or verticals (at least 3, e.g., "staffing agencies, insurance agencies, marketing agencies")
- [ ] Top 3-5 pain points your customers face
- [ ] Decision-maker title(s) (e.g., "Owner", "CEO", "VP Operations")

### Your Offer

- [ ] Main service or product name
- [ ] One-line description of the offer
- [ ] Pricing (or pricing range)
- [ ] Key differentiator -- why you instead of competitors

### Proof Points

- [ ] At least 1-2 results, case studies, or testimonials
- [ ] Specific numbers are best (e.g., "Increased revenue 40% in 90 days")

### Outreach Details

- [ ] Calendar booking URL (Cal.com or Calendly link)
- [ ] Email domain for outreach (ideally a dedicated domain, not your main one)
- [ ] Brand voice guidelines (optional -- formal vs. casual, specific phrases to use or avoid)
- [ ] Existing content to seed the system (optional -- blog posts, LinkedIn posts, email templates)

---

## Technical Requirements

These are verified during installation but good to confirm ahead of time.

### VPS Specifications

| Requirement | Minimum |
|------------|---------|
| RAM | 2 GB |
| CPU | 1 vCPU |
| Storage | 20 GB SSD |
| OS | Ubuntu 22.04+ (24.04 LTS recommended) |
| Network | Public IPv4 address |

### Software (installed during setup)

| Software | Version |
|----------|---------|
| Node.js | 22+ |
| npm | 10+ |
| Bash | 4+ |
| jq | 1.6+ |
| git | 2.30+ |
| Claude Code CLI | Latest |

### Access Requirements

- [ ] SSH access to your VPS (key-based recommended, password OK)
- [ ] Ability to set cron jobs on the VPS
- [ ] Outbound HTTPS access from the VPS (port 443)

---

## Budget Summary

| Component | Monthly Cost | Required? |
|-----------|-------------|-----------|
| Anthropic API (Claude) | $50-200 | Yes |
| VPS (DigitalOcean 2GB) | $12 | Yes |
| SmartLead | $39 | No (recommended) |
| Firecrawl | $0 (free tier) | No |
| Gmail | $0 | Yes |
| Cal.com / Calendly | $0 (free tier) | Yes |
| LinkedIn | $0-60 (Premium optional) | Yes (free works) |
| **Minimum total** | **~$62/mo** | |
| **Recommended total** | **~$100/mo** | |
| **Full setup** | **~$200-400/mo** | |

---

## Ready to Install?

Once every checkbox above is checked, proceed to [SETUP.md](SETUP.md) for step-by-step installation.
