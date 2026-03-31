"""
pipeline_tools.py — AI Integraterz pipeline tools

These are the functions the Head of Operations calls to manage the client pipeline.
Each function maps to an agent or a Supabase operation.

The agent calls these like a human picks up the phone:
  - "Run extraction for BlueSky Marketing" → run_agent("extraction", client_id)
  - "What's the pipeline status?" → get_pipeline_status()
  - "Create a new client" → create_client(...)
"""

import os
import json
import logging
import subprocess
import requests
from datetime import datetime, timezone

from supabase import create_client

logger = logging.getLogger(__name__)


def _get_supabase():
    return create_client(
        os.environ["SUPABASE_URL"],
        os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    )


def get_pipeline_status() -> dict:
    """
    Returns current status of all active clients in the pipeline.
    Used by the agent to answer "what's going on?" questions.
    """
    try:
        supabase = _get_supabase()
        result = (
            supabase.table("clients")
            .select("id, name, company, stage, tier, created_at, call_scheduled_at, call_completed_at")
            .not_.eq("stage", "closed_lost")
            .order("created_at", desc=True)
            .execute()
        )

        clients = result.data or []

        # Summarize by stage
        by_stage = {}
        for c in clients:
            stage = c["stage"]
            by_stage.setdefault(stage, []).append(f"{c['name']} ({c['company']})")

        return {
            "total_active": len(clients),
            "by_stage": by_stage,
            "clients": clients
        }
    except Exception as e:
        logger.error(f"get_pipeline_status failed: {e}")
        return {"error": str(e)}


def get_client_info(client_id: str = None, company_name: str = None) -> dict:
    """
    Get full info for a specific client by ID or company name.
    """
    try:
        supabase = _get_supabase()
        query = supabase.table("clients").select("*")

        if client_id:
            query = query.eq("id", client_id)
        elif company_name:
            query = query.ilike("company", f"%{company_name}%")
        else:
            return {"error": "Provide either client_id or company_name"}

        result = query.limit(1).execute()
        if not result.data:
            return {"error": f"Client not found: {client_id or company_name}"}

        return result.data[0]
    except Exception as e:
        logger.error(f"get_client_info failed: {e}")
        return {"error": str(e)}


def create_client(
    name: str,
    company: str,
    email: str,
    tier: str = "build_997",
    industry: str = None,
    team_size: int = None,
    notes: str = None
) -> dict:
    """
    Create a new client in the pipeline. Assigns to call_booked stage.
    """
    try:
        supabase = _get_supabase()
        result = supabase.table("clients").insert({
            "name": name,
            "company": company,
            "email": email,
            "tier": tier,
            "stage": "call_booked",
            "industry": industry,
            "team_size": team_size,
            "notes": notes,
            "created_at": datetime.now(timezone.utc).isoformat()
        }).select().single().execute()

        client = result.data
        logger.info(f"Created client: {company} ({client['id']})")
        return {"success": True, "client_id": client["id"], "client": client}
    except Exception as e:
        logger.error(f"create_client failed: {e}")
        return {"error": str(e)}


def update_client_stage(client_id: str, new_stage: str, notes: str = None) -> dict:
    """
    Advance a client to a new pipeline stage.
    """
    valid_stages = [
        "call_booked", "pre_call_ready", "call_complete", "building",
        "review", "proposal_ready", "proposal_sent", "active", "closed_lost"
    ]
    if new_stage not in valid_stages:
        return {"error": f"Invalid stage: {new_stage}. Valid: {valid_stages}"}

    try:
        supabase = _get_supabase()
        update = {"stage": new_stage}
        if notes:
            update["notes"] = notes

        supabase.table("clients").update(update).eq("id", client_id).execute()

        # Log pipeline event — table may not exist in standalone deployments
        try:
            supabase.table("pipeline_events").insert({
                "client_id": client_id,
                "to_stage": new_stage,
                "triggered_by": "head_of_operations",
                "created_at": datetime.now(timezone.utc).isoformat()
            }).execute()
        except Exception as log_err:
            logger.warning(f"pipeline_events log skipped (table may not exist): {log_err}")

        return {"success": True, "client_id": client_id, "new_stage": new_stage}
    except Exception as e:
        logger.error(f"update_client_stage failed: {e}")
        return {"error": str(e)}


def run_agent(agent_name: str, client_id: str, flags: str = "") -> dict:
    """
    Trigger an agent to run for a client.

    For local execution: calls run-agent.sh directly.
    For DigitalOcean runner: calls the pipeline runner API.

    Automatically selects the right execution method based on
    PIPELINE_RUNNER_URL environment variable.
    """
    runner_url = os.environ.get("PIPELINE_RUNNER_URL")

    if runner_url:
        return _run_agent_remote(agent_name, client_id, flags, runner_url)
    else:
        return _run_agent_local(agent_name, client_id, flags)


def _run_agent_remote(agent_name: str, client_id: str, flags: str, runner_url: str) -> dict:
    """Call the DigitalOcean pipeline runner API."""
    try:
        secret = os.environ.get("PIPELINE_API_SECRET", "")
        response = requests.post(
            f"{runner_url}/run-agent",
            json={"agent": agent_name, "client_id": client_id, "flags": flags},
            headers={"X-Pipeline-Secret": secret},
            timeout=30
        )
        response.raise_for_status()
        return {"success": True, "runner": "remote", "response": response.json()}
    except Exception as e:
        logger.error(f"Remote agent run failed: {e}")
        return {"error": str(e)}


def _run_agent_local(agent_name: str, client_id: str, flags: str) -> dict:
    """Run agent locally via run-agent.sh."""
    try:
        repo_path = os.environ.get("AI_INTEGRATERZ_REPO", os.path.expanduser("~/Desktop/ai-integraterz"))
        script = f"{repo_path}/lib/run-agent.sh"

        cmd = [script, agent_name, "--client", client_id]
        if flags:
            cmd.extend(flags.split())

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300
        )

        if result.returncode == 0:
            return {"success": True, "runner": "local", "output": result.stdout[-2000:]}
        else:
            return {"success": False, "runner": "local", "error": result.stderr[-1000:]}
    except subprocess.TimeoutExpired:
        return {"error": "Agent timed out after 5 minutes"}
    except Exception as e:
        logger.error(f"Local agent run failed: {e}")
        return {"error": str(e)}
