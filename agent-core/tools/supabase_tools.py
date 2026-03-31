"""
supabase_tools.py — Generic Supabase read tools for the agent

These tools let the agent read from the database without needing
to know Supabase's SDK directly. Project-specific tools that write
to domain tables should live in a separate file (e.g. tools/domain_tools.py).

Generic reads that work for any project:
  - read_table() — flexible query against any table
  - get_recent_outputs() — latest outputs/deliverables for an entity
  - get_upsell_signals() — pending signals that need action
  - log_upsell_action() — mark a signal as actioned
"""

import os
import json
import logging
from datetime import datetime, timezone

from supabase import create_client

logger = logging.getLogger(__name__)


def _get_supabase():
    return create_client(
        os.environ["SUPABASE_URL"],
        os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    )


def read_table(
    table: str,
    filters: dict = None,
    columns: str = "*",
    order_by: str = "created_at",
    order_desc: bool = True,
    limit: int = 50
) -> dict:
    """
    Generic read from any Supabase table.
    Useful for the agent to inspect any part of the database.

    Args:
        table: Table name
        filters: Dict of column:value equality filters (optional)
        columns: Comma-separated columns to select (default: *)
        order_by: Column to sort by (default: created_at)
        order_desc: Sort descending (default: True)
        limit: Max rows to return (default: 50, max: 200)
    """
    try:
        supabase = _get_supabase()
        query = supabase.table(table).select(columns)

        if filters:
            for col, val in filters.items():
                query = query.eq(col, val)

        query = query.order(order_by, desc=order_desc).limit(min(limit, 200))
        result = query.execute()

        return {
            "table": table,
            "count": len(result.data or []),
            "rows": result.data or []
        }
    except Exception as e:
        logger.error(f"read_table({table}) failed: {e}")
        return {"error": str(e), "table": table}


def get_recent_outputs(entity_id: str, output_table: str = "client_outputs", limit: int = 20) -> dict:
    """
    Get the most recent outputs/deliverables for an entity.
    Default table is client_outputs (AI Integraterz pattern) but any table works.

    Args:
        entity_id: The entity's UUID (client_id, project_id, etc.)
        output_table: Table name containing outputs (default: client_outputs)
        limit: Max rows to return
    """
    try:
        supabase = _get_supabase()

        # Try common foreign key column names
        for fk_col in ("client_id", "project_id", "entity_id"):
            try:
                result = (
                    supabase.table(output_table)
                    .select("*")
                    .eq(fk_col, entity_id)
                    .order("created_at", desc=True)
                    .limit(limit)
                    .execute()
                )
                if result.data is not None:
                    return {
                        "entity_id": entity_id,
                        "table": output_table,
                        "count": len(result.data),
                        "outputs": result.data
                    }
            except Exception:
                continue

        return {"error": f"Could not find a matching foreign key in {output_table}"}
    except Exception as e:
        logger.error(f"get_recent_outputs failed: {e}")
        return {"error": str(e)}


def get_upsell_signals(actioned: bool = False) -> dict:
    """
    Get pending upsell signals from the agent_upsell_log table.

    Args:
        actioned: If True, return actioned signals. Default False (pending only).
    """
    try:
        supabase = _get_supabase()
        result = (
            supabase.table("agent_upsell_log")
            .select("*, clients(name, company, stage, tier)")
            .eq("actioned", actioned)
            .order("posted_at", desc=True)
            .limit(50)
            .execute()
        )
        return {
            "count": len(result.data or []),
            "signals": result.data or []
        }
    except Exception as e:
        logger.error(f"get_upsell_signals failed: {e}")
        return {"error": str(e)}


def log_upsell_action(signal_id: str, action_taken: str) -> dict:
    """
    Mark an upsell signal as actioned and record what Justin did.

    Args:
        signal_id: UUID of the signal in agent_upsell_log
        action_taken: Description of what was done (e.g. "Pitched Training Contracts on call")
    """
    try:
        supabase = _get_supabase()
        supabase.table("agent_upsell_log").update({
            "actioned": True,
            "action_taken": action_taken
        }).eq("id", signal_id).execute()
        return {"success": True, "signal_id": signal_id, "action_taken": action_taken}
    except Exception as e:
        logger.error(f"log_upsell_action failed: {e}")
        return {"error": str(e)}


def search_entity(table: str, search_term: str, search_columns: list = None) -> dict:
    """
    Search for an entity by name across one or more columns.
    Useful when Justin says "pull up BlueSky Marketing" and we need to find them.

    Args:
        table: Table to search
        search_term: Text to search for
        search_columns: List of columns to search (default: ['name', 'company'])
    """
    if not search_columns:
        search_columns = ["name", "company"]

    try:
        supabase = _get_supabase()
        results = []

        for col in search_columns:
            try:
                result = (
                    supabase.table(table)
                    .select("*")
                    .ilike(col, f"%{search_term}%")
                    .limit(5)
                    .execute()
                )
                results.extend(result.data or [])
            except Exception:
                continue

        # Deduplicate by id
        seen = set()
        unique = []
        for row in results:
            rid = row.get("id")
            if rid not in seen:
                seen.add(rid)
                unique.append(row)

        return {"count": len(unique), "results": unique}
    except Exception as e:
        logger.error(f"search_entity failed: {e}")
        return {"error": str(e)}
