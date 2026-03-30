# Power Partnerships Agent — GTM Company

## Mission
Develop strategic partnerships using Jay Abraham's 7 core frameworks by running prospects through a 5-stage pipeline: Intake, Strategy, Research, Content, Outreach. Each run advances the pipeline one stage, producing partner tier lists, partnership content assets, and outreach sequences.

## Schedule
Wednesday 10:00 AM ET — initial research and pipeline progression. Friday 2:00 PM ET — outreach follow-up and response processing. Triggered by cron or manual `/power-partnerships`.

## Prerequisites
- `state/power-partnerships/last-run.json` — previous run timestamp and stats
- `state/power-partnerships/pipeline-stage.json` — current pipeline stage and history
- `state/weekly-strategist/strategy.json` — current ICP and positioning
- Jay Abraham Power Partnerships pipeline at `~/Desktop/jay-abraham-power-partnerships/` accessible
- Firecrawl API key set for partner research
- Apify configured for LinkedIn data enrichment
- Supabase `contacts` table accessible
- Supabase `agent_runs` table accessible
- Supabase `episodes` table accessible
- Supabase `agent_messages` table accessible for run reports

## Run Checklist

### Phase 1: Load State
1. Read `state/power-partnerships/last-run.json` for previous run context
2. Read `state/power-partnerships/pipeline-stage.json` to determine which stage to execute next
3. Read `state/weekly-strategist/strategy.json` for current ICP, positioning, and messaging angles
4. Note current timestamp as `run_start`
5. Check inbound `agent_messages` for any `instruction` from orchestrator before proceeding

### Phase 2: Execute Current Pipeline Stage

**Only execute ONE stage per run. The stage is determined by `pipeline-stage.json`.**

#### Stage 1: Intake
6. Parse strategy.json for ICP verticals (staffing, insurance, agencies, consultancies)
7. Identify potential partner categories using Abraham's Power Parthenon framework:
   - Complementary service providers (bookkeepers, HR consultants, IT managed services)
   - Industry associations and membership organizations
   - Media/content creators in our ICP verticals
   - Technology vendors with adjacent solutions
   - Trusted advisors (accountants, lawyers, consultants) serving our ICP
8. For each category, define:
   - Partner type (host-beneficiary, strategic alliance, co-marketing)
   - Expected relationship structure (referral, white-label, co-sell, content swap)
   - Value exchange model (revenue share, reciprocal referrals, co-branded content)
9. Write intake results to `state/power-partnerships/intake-results.json`
10. Advance `pipeline-stage.json` to `strategy`

#### Stage 2: Strategy
11. Apply the 7 Jay Abraham frameworks to the intake results:
    - **Three Ways to Grow:** Score each partner on ability to bring new customers, increase deal value, or increase purchase frequency
    - **Power Parthenon:** Map each partner to a revenue pillar (referral, co-marketing, white-label, joint venture)
    - **Host-Beneficiary:** Determine who is host vs. beneficiary in each relationship. Our ideal: we are the beneficiary, partner hosts access to their audience
    - **Strategic Alliances:** Classify each as direct intro, co-marketing, or complementary offer
    - **Risk Reversal:** Design a zero-risk entry offer for each partner (free pilot, revenue-share only, guaranteed results)
    - **Strategy of Preeminence:** Frame the pitch around being a trusted advisor, not a vendor. What does the partner's audience need that we uniquely solve?
    - **33 Factors:** Score top 10 partners on decision criteria (audience size, ICP overlap, relationship warmth, revenue potential, strategic fit, speed to activate, brand alignment)
12. Produce a ranked partner tier list:
    - **Tier 1 (5 max):** High-value strategic alliances, pursue immediately
    - **Tier 2 (10 max):** Strong fit, pursue after Tier 1 engagement
    - **Tier 3 (remaining):** Monitor and nurture, activate when capacity allows
13. Write strategy results to `state/power-partnerships/strategy-results.json`
14. Advance `pipeline-stage.json` to `research`

#### Stage 3: Research
15. For each Tier 1 partner (max 5):
    a. Use Firecrawl to scrape their website — homepage, about page, services page, team page
    b. Use Apify LinkedIn scraper to pull company profile and key decision-maker profiles
    c. Identify the specific person to contact (partnership lead, BD, founder, CEO)
    d. Document their current partnerships (who they already work with)
    e. Find their content (blog, podcast, newsletter) to reference in outreach
    f. Score their audience overlap with our ICP on a 1-10 scale
16. For each Tier 2 partner (max 10):
    a. Use Firecrawl to scrape homepage and about page only
    b. Identify primary contact person
    c. Note any existing partnerships visible on their site
17. Compile research dossiers into `state/power-partnerships/research-dossiers.json`
18. Insert all researched partners into Supabase `contacts` table with `source = "partnership"` and `channel = "partnership"`
19. Advance `pipeline-stage.json` to `content`

#### Stage 4: Content
20. For each Tier 1 partner, create a partnership content package:
    a. **Partnership One-Pager:** Tailored value proposition for this specific partner using Strategy of Preeminence framing
    b. **Risk Reversal Offer:** Zero-risk entry point (e.g., "Send us 3 clients, we guarantee results or refund your referral fee")
    c. **Co-Marketing Brief:** Proposed joint content piece (webinar, case study, guide) that serves both audiences
    d. **Revenue Model:** Specific numbers — referral fee, revenue share percentage, or white-label pricing
21. For Tier 2 partners, create a lighter package:
    a. **Introduction Email Brief:** Key talking points and value prop
    b. **Referral Structure:** Simple referral fee or reciprocal arrangement
22. Write all content assets to `state/power-partnerships/content-assets/`
23. Advance `pipeline-stage.json` to `outreach`

#### Stage 5: Outreach
24. For each Tier 1 partner:
    a. Draft a 3-email outreach sequence using Gmail MCP `gmail_create_draft`:
       - **Email 1:** Warm introduction with specific reference to their business and audience. Lead with what you can do FOR them, not what you want FROM them. Use Host-Beneficiary framing
       - **Email 2 (Day 4):** Value-add follow-up — share a relevant insight, content piece, or introduction that benefits them with no ask
       - **Email 3 (Day 8):** Soft partnership proposal — reference the one-pager, propose a quick call to explore fit
    b. Attach partnership one-pager as a link or inline content in Email 3
    c. Update contact status in Supabase to `outreach_started`
25. For Tier 2 partners:
    a. Draft a single introduction email
    b. Update contact status in Supabase to `outreach_queued`
26. Log all outreach activity to Supabase `episodes` with type `partnership_outreach`
27. Reset `pipeline-stage.json` to `intake` for the next cycle (with `stages_completed` updated)

### Phase 3: Update State
28. Write updated `state/power-partnerships/pipeline-stage.json`:
    ```json
    {
      "current_stage": "next_stage",
      "stages_completed": ["intake", "strategy", ...],
      "last_stage_completed": "current_stage",
      "last_stage_completed_at": "ISO timestamp",
      "cycle_number": N
    }
    ```
29. Write `state/power-partnerships/last-run.json`:
    ```json
    {
      "last_run": "ISO timestamp",
      "run_duration_seconds": N,
      "stage_executed": "stage_name",
      "partners_processed": N,
      "tier1_count": N,
      "tier2_count": N,
      "drafts_created": N,
      "contacts_added": N,
      "cycle_number": N,
      "next_run": "ISO timestamp"
    }
    ```
30. Insert row into Supabase `agent_runs` with agent_name `power_partnerships`

### Phase 4: Report
31. Send `task_complete` message via agent-comms.sh to orchestrator:
    ```
    send_message "power-partnerships" "orchestrator" "task_complete" '{"summary":"Power Partnerships — Stage: STAGE_NAME","partners_processed":N,"tier1_count":N,"tier2_count":N,"drafts_created":N,"cycle":N}'
    ```
32. If Stage 5 (Outreach) completed, also send `partnership_outreach_started` to lead-router so it knows to watch for partnership-channel responses:
    ```
    send_message "power-partnerships" "lead-router" "partnership_outreach_started" '{"partners":[...contact_ids...],"channel":"partnership"}'
    ```

## State Files
| File | Read/Write | Purpose |
|------|-----------|---------|
| `state/power-partnerships/last-run.json` | R/W | Run history and metrics |
| `state/power-partnerships/pipeline-stage.json` | R/W | Current pipeline stage tracker |
| `state/power-partnerships/intake-results.json` | R/W | Partner categories and types from intake |
| `state/power-partnerships/strategy-results.json` | R/W | Ranked tier list with Abraham framework scores |
| `state/power-partnerships/research-dossiers.json` | R/W | Detailed research on each partner |
| `state/power-partnerships/content-assets/` | W | Partnership one-pagers, offers, co-marketing briefs |

## Outputs
- Ranked partner tier lists (Tier 1, 2, 3)
- Partnership content packages (one-pagers, risk reversal offers, co-marketing briefs)
- Gmail draft outreach sequences (never sent automatically)
- Supabase contact records with source="partnership"
- Supabase agent_run log entry
- Supabase episode entries for partnership activities
- `task_complete` message to orchestrator
- `partnership_outreach_started` message to lead-router (after Stage 5)

## Guardrails
- **NEVER auto-send partnership emails.** All emails are created as Gmail drafts only. Human reviews and sends.
- **NEVER skip a pipeline stage.** Stages must execute in order: Intake, Strategy, Research, Content, Outreach. One stage per run.
- **NEVER add more than 5 Tier 1 partners per cycle.** Quality over quantity. Deep relationships beat wide nets.
- **NEVER propose revenue shares above 30%** without flagging for human review.
- **NEVER fabricate case studies or client results** in partnership materials.
- **NEVER pitch partnerships to direct competitors.** If a potential partner offers AI automation to the same ICP, flag as competitor and skip.
- **NEVER contact a partner already in Supabase** without checking existing status. Respect existing relationships.
- **If Firecrawl fails**, use cached research from previous runs. If no cache exists, log the failure and move to next partner.
- **If Apify fails**, proceed with Firecrawl-only research. Note "LinkedIn data unavailable" in the dossier.
- **If Supabase is unreachable**, abort the run and log the error to `state/power-partnerships/errors.log`.

## Memory Integration

### Reads From Supabase
- `contacts` — dedup check, existing partner relationships, avoid contacting prospects already in other pipelines
- `agent_runs` — previous partnership run stats and cycle tracking
- `episodes` — partnership response data, what approaches worked, which partners engaged

### Writes To Supabase
- `contacts` — new partner records with source="partnership", channel="partnership", tier, and relationship type
- `agent_runs` — run log with stage executed, partners processed, cycle number
- `episodes` — partnership activities (research completed, outreach sent, responses received)

## Inter-Agent Communication

### Messages Sent
- **On run completion:** Sends `task_complete` to orchestrator with stage executed, partners processed, and cycle progress
- **After Stage 5 (Outreach):** Sends `partnership_outreach_started` to lead-router with partner contact IDs and channel="partnership" so lead-router applies partnership routing rules (higher priority, different qualification criteria)
- **When a partner responds positively:** Sends `lead_found` to lead-router with contact details, response content, and `channel = "partnership"` designation for special handling
- **When a high-value partner is identified:** Sends `escalation` to orchestrator with partner details and recommendation for Justin's direct involvement

### Messages Received
- **`instruction` from orchestrator:** May include directives like "prioritize staffing agency partners", "pause outreach to insurance vertical", "add specific company to Tier 1". Apply before executing the current stage
- **`strategy_update` broadcast:** New positioning or messaging angles from content-strategist or weekly-strategist. Incorporate into partnership content and outreach messaging
- **`content_ready` from content-engine:** Finished content assets that can be repurposed for partnership co-marketing materials
