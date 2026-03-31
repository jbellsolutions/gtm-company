"""
domain_tools_template.py — Project-specific tools template

INSTRUCTIONS FOR A NEW PROJECT:
1. Copy this file to tools/domain_tools.py in your project
2. Replace every <PLACEHOLDER> with your project's specifics
3. Register your tools in agent/tools.py → _register_implementations()
4. Add schemas to config/tools.json

This template shows the pattern. Delete what you don't need.
Add what your project requires.

Examples of what goes here:
  - AI Integraterz: create_client(), run_agent(), get_pipeline_status()
  - COO project:    get_revenue_snapshot(), get_team_metrics(), flag_risk()
  - GTM project:    create_content_brief(), get_campaign_status(), log_lead()
  - Speaker project: book_speaking_slot(), get_calendar(), log_inquiry()
"""

import os
import logging
from datetime import datetime, timezone

from supabase import create_client

logger = logging.getLogger(__name__)


def _get_supabase():
    return create_client(
        os.environ["SUPABASE_URL"],
        os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    )


# ─────────────────────────────────────────────────────────────────────────────
# REPLACE THESE WITH YOUR PROJECT'S ACTUAL TOOLS
# ─────────────────────────────────────────────────────────────────────────────

def get_<domain>_status() -> dict:
    """
    Get the current status of <your domain's primary entity>.
    Replace <domain> with your domain name (e.g. get_pipeline_status, get_campaign_status).

    Returns a summary the agent can use to answer "what's going on?"
    """
    try:
        supabase = _get_supabase()
        result = (
            supabase.table("<your_main_table>")       # ← replace
            .select("<columns>")                       # ← replace
            .order("created_at", desc=True)
            .limit(50)
            .execute()
        )
        return {
            "count": len(result.data or []),
            "items": result.data or []
        }
    except Exception as e:
        logger.error(f"get_<domain>_status failed: {e}")
        return {"error": str(e)}


def create_<entity>(
    name: str,
    # Add your entity's fields here
    **kwargs
) -> dict:
    """
    Create a new <entity> in the database.
    Replace <entity> with your domain noun (e.g. create_client, create_project, create_campaign).
    """
    try:
        supabase = _get_supabase()
        result = (
            supabase.table("<your_main_table>")       # ← replace
            .insert({
                "name": name,
                "created_at": datetime.now(timezone.utc).isoformat(),
                **kwargs
            })
            .select()
            .single()
            .execute()
        )
        return {"success": True, "id": result.data["id"], "entity": result.data}
    except Exception as e:
        logger.error(f"create_<entity> failed: {e}")
        return {"error": str(e)}


def update_<entity>_status(entity_id: str, new_status: str, notes: str = None) -> dict:
    """
    Update the status/stage of an entity.
    Replace <entity> with your domain noun.
    """
    try:
        supabase = _get_supabase()
        update = {"status": new_status}
        if notes:
            update["notes"] = notes

        supabase.table("<your_main_table>").update(update).eq("id", entity_id).execute()

        # Log the event if you have an events table
        # supabase.table("<your_events_table>").insert({...}).execute()

        return {"success": True, "id": entity_id, "new_status": new_status}
    except Exception as e:
        logger.error(f"update_<entity>_status failed: {e}")
        return {"error": str(e)}


# ─────────────────────────────────────────────────────────────────────────────
# REGISTRATION (add to agent/tools.py → _register_implementations)
# ─────────────────────────────────────────────────────────────────────────────
#
# from tools.domain_tools import get_<domain>_status, create_<entity>, update_<entity>_status
# self._implementations.update({
#     "get_<domain>_status": get_<domain>_status,
#     "create_<entity>": create_<entity>,
#     "update_<entity>_status": update_<entity>_status,
# })
#
# ─────────────────────────────────────────────────────────────────────────────
# TOOL SCHEMA (add to config/tools.json)
# ─────────────────────────────────────────────────────────────────────────────
#
# {
#   "name": "get_<domain>_status",
#   "description": "Get the current status of all active <entities>.",
#   "input_schema": { "type": "object", "properties": {}, "required": [] }
# },
# {
#   "name": "create_<entity>",
#   "description": "Create a new <entity>.",
#   "input_schema": {
#     "type": "object",
#     "properties": {
#       "name": { "type": "string", "description": "Name of the <entity>" }
#     },
#     "required": ["name"]
#   }
# }
