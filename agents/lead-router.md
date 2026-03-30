# Lead Router Agent — GTM Company

## Mission
Deduplicate contacts across cold email and LinkedIn channels, then route each lead to the optimal channel based on warmth signals and engagement history.

## Schedule
Every 2 hours, offset 30 minutes after cold-outreach (e.g., 8:30, 10:30, 12:30...). This ensures it processes freshly updated data from both outreach agents. Triggered by cron or manual `/lead-router`.

## Prerequisites
- `state/cold-outreach/pipeline.json` — cold email prospect data
- `state/linkedin-engage/leads-detected.json` — LinkedIn warm leads
- `state/linkedin-engage/engagement-log.json` — LinkedIn engagement history
- `state/lead-router/routing-decisions.json` — previous routing decisions
- Supabase `contacts` table accessible
- Supabase `episodes` table accessible
- Supabase `agent_runs` table accessible
- Slack #gtm-ops channel ID known

## Run Checklist

### Phase 1: Load State
1. Read `state/cold-outreach/pipeline.json` for all cold email prospects
2. Read `state/linkedin-engage/leads-detected.json` for LinkedIn warm leads
3. Read `state/linkedin-engage/engagement-log.json` for engagement context
4. Read `state/lead-router/routing-decisions.json` for previous routing history
5. Note current timestamp as `run_start`

### Phase 2: Collect Contacts
6. Query Supabase `contacts` table for all contacts where `updated_at` is within the last 48 hours
7. Merge the Supabase results with state file data to build a complete picture of each contact:
   - Name, company, email, LinkedIn profile URL
   - Source channel (cold_email, linkedin, or both)
   - Current status per channel
   - Engagement history (comments, replies, opens)
   - Touch count and last touch date

### Phase 3: Deduplicate
8. Group contacts by company domain and name to find cross-channel duplicates
9. For each duplicate set:
   a. Compare warmth signals:
      - LinkedIn engagement (comments, likes, profile views) = warm signals
      - Email replies (positive, questions) = warm signals
      - No response on either = cold
   b. Determine the **warmer** relationship:
      - If LinkedIn has engagement but email has no reply → LinkedIn is warmer
      - If email has a positive reply but LinkedIn has no engagement → email is warmer
      - If both have signals → keep both but coordinate timing (mark as `dual_channel`)
   c. Update the Supabase `contacts` record:
      - Set `primary_channel` to the warmer channel
      - Set `channel` to `both` if dual_channel
      - Merge any missing data (email found via LinkedIn, LinkedIn found via email)
10. Log each dedup decision with reasoning

### Phase 4: Route New Contacts
11. For contacts not yet routed (no `primary_channel` set), apply routing logic:
    - **Has LinkedIn profile + any engagement signal** → route to `linkedin`
    - **Has email only, no LinkedIn found** → route to `cold_email`
    - **Has both but zero prior contact on either** → route to `test_both`:
      - Start with LinkedIn engagement first
      - If no response in 48 hours, add to cold email queue
      - Never contact on both channels within the same 48-hour window
    - **Has been contacted on one channel with no response for 14+ days** → try the other channel
12. For each routing decision, write to routing-decisions.json:
    ```json
    {
      "contact_id": "uuid",
      "name": "...",
      "company": "...",
      "decision": "linkedin|cold_email|test_both|dual_channel|hold",
      "reasoning": "short explanation",
      "previous_channel": "...",
      "timestamp": "ISO"
    }
    ```
13. Update contact status in Supabase with the routing decision

### Phase 5: Flag Escalations
14. Identify contacts that need human review:
    - **Conflicting signals:** Positive email reply but negative LinkedIn interaction (or vice versa)
    - **High-value prospects:** Company revenue >$5M or recognized brand in ICP verticals
    - **Stale leads:** Engaged 30+ days ago but no progression
    - **Dual-channel confusion:** Both channels active with different messaging
15. Write escalation flags to routing-decisions.json with `needs_human_review: true`
16. For high-priority escalations, post individual alerts to Slack #gtm-ops

### Phase 6: Update State and Report
17. Calculate run metrics:
    - `contacts_processed` — total contacts evaluated
    - `duplicates_found` — cross-channel duplicates merged
    - `routing_decisions` — new routing assignments made
    - `escalations` — contacts flagged for human review
18. Write updated `state/lead-router/routing-decisions.json`
19. Insert row into Supabase `agent_runs` with agent_name `lead_router` and metrics
20. Log each routing decision as an episode in Supabase `episodes`
21. Post summary to Slack #gtm-ops:
    ```
    Lead Router Run Complete
    - Processed: {contacts_processed} contacts
    - Duplicates merged: {duplicates_found}
    - Routed: {routing_decisions} new decisions
    - Escalations: {escalations} need human review
    - Channel split: {linkedin_count} LinkedIn / {email_count} Email / {both_count} Both
    ```

## State Files
| File | Read/Write | Purpose |
|------|-----------|---------|
| `state/cold-outreach/pipeline.json` | R | Cold email prospect data |
| `state/linkedin-engage/leads-detected.json` | R | LinkedIn warm leads |
| `state/linkedin-engage/engagement-log.json` | R | LinkedIn engagement history |
| `state/lead-router/routing-decisions.json` | R/W | All routing decisions with reasoning |

## Outputs
- Deduplicated contact records in Supabase
- Routing decisions with reasoning for every contact
- Escalation flags for human-review contacts
- Supabase agent_run log entry
- Episode logs for each routing decision
- Slack summary and escalation alerts

## Guardrails
- **NEVER contact the same person on two channels within 48 hours.** If email was sent today, LinkedIn engagement waits 48h and vice versa.
- **NEVER auto-merge contacts unless company domain AND name match.** Same company but different people are separate contacts.
- **NEVER delete a contact.** Dedup means merging records, not removing them. Set status to `merged` on the duplicate.
- **NEVER override a human routing decision.** If a contact has `routed_by: human` in Supabase, skip it.
- **NEVER downgrade a warm lead.** If a contact is `warm_lead` status, routing can only maintain or upgrade, never set back to `cold`.
- **If Supabase is unreachable**, abort the run entirely. Routing without the source of truth creates dangerous conflicts. Post error to Slack.
- **If state files are missing or corrupted**, log the issue and process only Supabase data for that run.

## Memory Integration

### Reads From Supabase
- `contacts` — full contact records with channel, status, engagement history, routing
- `episodes` — recent engagement events to assess warmth
- `agent_runs` — previous router runs to detect patterns

### Writes To Supabase
- `contacts` — updated routing decisions, merged records, channel assignments
- `episodes` — routing decision events with full reasoning context
- `agent_runs` — run log with dedup and routing metrics

## Inter-Agent Communication

### Messages Sent
- **On run completion:** Sends `task_complete` to orchestrator with routing summary (contacts_processed, duplicates_found, routing_decisions, escalations, channel_split)
- **Routing instructions to outreach agents:** Sends `instruction` to cold-outreach with updated email routing decisions (new prospects to add, prospects to pause, channel reassignments). Sends `instruction` to linkedin-engage with updated LinkedIn routing decisions (new targets to engage, prospects to deprioritize)
- **When there's a conflict:** Sends `escalation` to orchestrator when conflicting signals are detected (e.g., positive email reply but negative LinkedIn interaction, dual-channel confusion, high-value prospect needing special handling). Include both sides of the conflict data and a recommended resolution

### Messages Received
- **`lead_found` from cold-outreach:** Hot lead detected via email reply. Immediately evaluate for dedup and routing
- **`lead_found` from linkedin-engage:** Warm lead detected via LinkedIn engagement. Immediately evaluate for dedup and routing
- **`instruction` from orchestrator:** May include directives like "hold routing for prospect X pending human review", "force-route prospect Y to email channel", "merge these two contact records"
- **`strategy_update` broadcast:** Updated channel weights from weekly-strategist. Adjust routing logic to favor the higher-weighted channel for new contacts
