"""
memory.py — Supabase memory interface

Handles all persistent memory for the agent:
  - Conversation history per user (what Justin said, what the agent replied)
  - Pipeline context (client states, agent runs, upsell signals)
  - Agent run log (what the agent did and when)

This is what separates a real agent from a stateless script.
Every conversation continues where it left off.
Every heartbeat knows what happened in the last heartbeat.
"""

import os
import json
import logging
from datetime import datetime, timezone
from typing import Optional

from supabase import create_client, Client

logger = logging.getLogger(__name__)


class Memory:
    """
    Supabase-backed persistent memory.

    Required Supabase tables (see deployment/supabase-schema.sql):
      agent_conversations  — conversation history per user
      agent_run_log        — log of every agent action
      client_pipeline      — pipeline state (read-only from here; agents write it)
    """

    def __init__(self):
        url = os.environ.get("SUPABASE_URL")
        key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

        if not url or not key:
            raise EnvironmentError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")

        self.supabase: Client = create_client(url, key)
        self.agent_name = os.environ.get("AGENT_NAME", "agent")

    # ─────────────────────────────────────────────
    # Conversation Memory
    # ─────────────────────────────────────────────

    def get_conversation_history(self, user_id: str, limit: int = 20) -> list:
        """
        Returns the last N messages for a user as Claude-format messages.
        [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}, ...]
        """
        try:
            result = (
                self.supabase.table("agent_conversations")
                .select("role, content, created_at")
                .eq("user_id", user_id)
                .eq("agent_name", self.agent_name)
                .order("created_at", desc=True)
                .limit(limit)
                .execute()
            )

            # Reverse so oldest first (Claude expects chronological order)
            messages = list(reversed(result.data or []))
            return [{"role": m["role"], "content": m["content"]} for m in messages]

        except Exception as e:
            logger.error(f"Failed to load conversation history for {user_id}: {e}")
            return []

    def save_message(self, user_id: str, role: str, content: str):
        """Persist a single message to conversation history."""
        try:
            self.supabase.table("agent_conversations").insert({
                "agent_name": self.agent_name,
                "user_id": user_id,
                "role": role,
                "content": content,
                "created_at": datetime.now(timezone.utc).isoformat()
            }).execute()
        except Exception as e:
            logger.error(f"Failed to save message: {e}")

    def clear_conversation(self, user_id: str):
        """Clear conversation history for a user (fresh start)."""
        try:
            self.supabase.table("agent_conversations") \
                .delete() \
                .eq("user_id", user_id) \
                .eq("agent_name", self.agent_name) \
                .execute()
        except Exception as e:
            logger.error(f"Failed to clear conversation for {user_id}: {e}")

    # ─────────────────────────────────────────────
    # Pipeline Context
    # ─────────────────────────────────────────────

    def get_pipeline_context(self) -> dict:
        """
        Returns current pipeline state for use in heartbeat prompts.
        Reads from Supabase clients table (same DB the hub uses).

        Each table is queried independently so a missing table (e.g. agent_upsell_log
        not yet created for a new project) does not suppress the clients data.
        """
        context: dict = {"retrieved_at": datetime.now(timezone.utc).isoformat()}

        # Active clients — core pipeline state
        try:
            clients_result = (
                self.supabase.table("clients")
                .select("id, name, company, stage, tier, created_at")
                .not_.eq("stage", "closed_lost")
                .order("created_at", desc=True)
                .execute()
            )
            context["active_clients"] = clients_result.data or []
        except Exception as e:
            logger.error(f"Failed to load clients for pipeline context: {e}")
            context["active_clients"] = []
            context["clients_error"] = str(e)

        # Upsell signals — optional table, may not exist in all projects
        try:
            upsell_result = (
                self.supabase.table("agent_upsell_log")
                .select("*")
                .eq("actioned", False)
                .execute()
            )
            context["pending_upsell_signals"] = upsell_result.data or []
        except Exception as e:
            logger.warning(f"agent_upsell_log not available (table may not exist): {e}")
            context["pending_upsell_signals"] = []

        return context

    # ─────────────────────────────────────────────
    # Agent Run Log
    # ─────────────────────────────────────────────

    def log_action(self, action: str, details: dict = None, client_id: str = None):
        """Log an agent action for the Operations tab in the hub."""
        try:
            self.supabase.table("agent_run_log").insert({
                "agent_name": self.agent_name,
                "action": action,
                "details": json.dumps(details or {}),
                "client_id": client_id,
                "created_at": datetime.now(timezone.utc).isoformat()
            }).execute()
        except Exception as e:
            logger.error(f"Failed to log action: {e}")

    def get_recent_runs(self, limit: int = 50) -> list:
        """Returns recent agent actions for the Operations tab."""
        try:
            result = (
                self.supabase.table("agent_run_log")
                .select("*")
                .eq("agent_name", self.agent_name)
                .order("created_at", desc=True)
                .limit(limit)
                .execute()
            )
            return result.data or []
        except Exception as e:
            logger.error(f"Failed to get recent runs: {e}")
            return []
