"""
domain_tools.py — GTM-specific tools for Jordan (Head of Growth)

Tools for managing campaigns, checking stats across all GTM channels,
creating campaigns, and interacting with the cold email VPS.
"""

import os
import json
import logging
import urllib.request
import urllib.error
from datetime import datetime, timezone

from supabase import create_client

logger = logging.getLogger(__name__)

COLD_EMAIL_VPS = "http://134.122.17.43"
COLD_EMAIL_API_KEY = os.environ.get("COLD_EMAIL_API_KEY", "cold-email-dev-key")


def _get_supabase():
    return create_client(
        os.environ["SUPABASE_URL"],
        os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    )


# ─────────────────────────────────────────────────────────────────────────────
# Campaign Management
# ─────────────────────────────────────────────────────────────────────────────

def get_campaign_pipeline() -> dict:
    """Get all active campaigns grouped by stage with counts."""
    try:
        supabase = _get_supabase()
        result = (
            supabase.table("campaigns")
            .select("id,name,company,stage,tier,created_at,metadata")
            .neq("stage", "closed")
            .order("created_at", desc=True)
            .limit(100)
            .execute()
        )
        campaigns = result.data or []
        by_stage = {}
        for c in campaigns:
            stage = c.get("stage", "draft")
            by_stage.setdefault(stage, []).append(c)

        return {
            "total_active": len(campaigns),
            "by_stage": {k: {"count": len(v), "campaigns": v} for k, v in by_stage.items()},
            "campaigns": campaigns
        }
    except Exception as e:
        logger.error(f"get_campaign_pipeline failed: {e}")
        return {"error": str(e)}


def create_campaign(
    name: str,
    tier: str = "cold_email",
    company: str = None,
    email: str = None,
    notes: str = None,
    stage: str = "draft"
) -> dict:
    """Create a new campaign in the pipeline."""
    try:
        supabase = _get_supabase()
        data = {
            "name": name,
            "tier": tier,
            "stage": stage,
        }
        if company:
            data["company"] = company
        if email:
            data["email"] = email
        if notes:
            data["notes"] = notes

        result = (
            supabase.table("campaigns")
            .insert(data)
            .select()
            .single()
            .execute()
        )
        # Log the creation event
        supabase.table("campaign_events").insert({
            "entity_id": result.data["id"],
            "event_type": "stage_change",
            "to_stage": stage,
            "note": f"Campaign created: {name} ({tier})"
        }).execute()

        return {"success": True, "id": result.data["id"], "campaign": result.data}
    except Exception as e:
        logger.error(f"create_campaign failed: {e}")
        return {"error": str(e)}


def update_campaign_stage(campaign_id: str, new_stage: str, notes: str = None) -> dict:
    """Move a campaign to a new stage."""
    try:
        supabase = _get_supabase()
        # Get current stage
        current = (
            supabase.table("campaigns")
            .select("stage")
            .eq("id", campaign_id)
            .single()
            .execute()
        )
        old_stage = current.data.get("stage") if current.data else None

        # Update
        update = {"stage": new_stage}
        if notes:
            update["notes"] = notes
        supabase.table("campaigns").update(update).eq("id", campaign_id).execute()

        # Log event
        supabase.table("campaign_events").insert({
            "entity_id": campaign_id,
            "event_type": "stage_change",
            "from_stage": old_stage,
            "to_stage": new_stage,
            "note": notes or f"Stage changed: {old_stage} → {new_stage}"
        }).execute()

        return {"success": True, "id": campaign_id, "from": old_stage, "to": new_stage}
    except Exception as e:
        logger.error(f"update_campaign_stage failed: {e}")
        return {"error": str(e)}


# ─────────────────────────────────────────────────────────────────────────────
# Cold Email Stats (via cold email VPS API)
# ─────────────────────────────────────────────────────────────────────────────

def get_cold_email_stats() -> dict:
    """Pull live stats from the cold email VPS dashboard at 134.122.17.43."""
    try:
        url = f"{COLD_EMAIL_VPS}/api/smartlead/stats?key={COLD_EMAIL_API_KEY}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
        return {
            "source": "cold_email_vps",
            "total_sent": data.get("total_sent", 0),
            "total_replies": data.get("total_replies", 0),
            "total_bounces": data.get("total_bounces", 0),
            "total_leads": data.get("total_leads", 0),
            "campaigns": data.get("campaigns", []),
            "reply_rate": data.get("reply_rate", "0%"),
        }
    except Exception as e:
        logger.error(f"get_cold_email_stats failed: {e}")
        return {"error": str(e), "source": "cold_email_vps"}


# ─────────────────────────────────────────────────────────────────────────────
# Cross-Channel Overview
# ─────────────────────────────────────────────────────────────────────────────

def get_gtm_overview() -> dict:
    """Get a unified overview of all GTM channels — the big picture."""
    try:
        supabase = _get_supabase()

        # Campaign pipeline
        campaigns = (
            supabase.table("campaigns")
            .select("id,stage,tier")
            .neq("stage", "closed")
            .execute()
        ).data or []

        by_tier = {}
        for c in campaigns:
            tier = c.get("tier", "unknown")
            by_tier.setdefault(tier, 0)
            by_tier[tier] += 1

        # Recent agent activity
        activity = (
            supabase.table("agent_run_log")
            .select("agent_name,action,created_at")
            .order("created_at", desc=True)
            .limit(10)
            .execute()
        ).data or []

        # Campaign stats (from synced SmartLead data)
        stats = (
            supabase.table("campaign_stats")
            .select("campaign_name,sent,replies,bounces")
            .order("updated_at", desc=True)
            .limit(10)
            .execute()
        ).data or []

        total_sent = sum(s.get("sent", 0) for s in stats)
        total_replies = sum(s.get("replies", 0) for s in stats)

        return {
            "active_campaigns": len(campaigns),
            "campaigns_by_channel": by_tier,
            "email_stats": {
                "total_sent": total_sent,
                "total_replies": total_replies,
                "reply_rate": f"{(total_replies/total_sent*100):.1f}%" if total_sent > 0 else "0%"
            },
            "recent_activity": activity,
            "campaign_details": stats
        }
    except Exception as e:
        logger.error(f"get_gtm_overview failed: {e}")
        return {"error": str(e)}


def log_campaign_action(campaign_id: str, action: str, details: dict = None) -> dict:
    """Log an action taken on a campaign (for the operations activity feed)."""
    try:
        supabase = _get_supabase()
        supabase.table("agent_run_log").insert({
            "agent_name": "jordan",
            "action": action,
            "client_id": campaign_id,
            "details": details or {}
        }).execute()
        return {"success": True}
    except Exception as e:
        logger.error(f"log_campaign_action failed: {e}")
        return {"error": str(e)}


# ─────────────────────────────────────────────────────────────────────────────
# Tool Registration
# ─────────────────────────────────────────────────────────────────────────────
# Add to agent/tools.py → _register_implementations():
#
# from tools.domain_tools import (
#     get_campaign_pipeline, create_campaign, update_campaign_stage,
#     get_cold_email_stats, get_gtm_overview, log_campaign_action
# )
# self._implementations.update({
#     "get_campaign_pipeline": get_campaign_pipeline,
#     "create_campaign": create_campaign,
#     "update_campaign_stage": update_campaign_stage,
#     "get_cold_email_stats": get_cold_email_stats,
#     "get_gtm_overview": get_gtm_overview,
#     "log_campaign_action": log_campaign_action,
# })
