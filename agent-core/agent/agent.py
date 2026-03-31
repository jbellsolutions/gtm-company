"""
agent.py — PersistentAgent core class

The main agentic loop. Runs continuously on a server, listens to Slack,
executes a heartbeat cycle, and processes messages with full tool use.

This class is identity-agnostic — swap the identity file to instantiate
a different agent (Head of Operations, COO, GTM Agent, etc.).
"""

import os
import json
import time
import threading
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

import anthropic

from .identity import Identity
from .memory import Memory
from .tools import ToolRegistry

logger = logging.getLogger(__name__)

ET = ZoneInfo("America/New_York")


class PersistentAgent:
    """
    A living, persistent Claude agent with:
    - Continuous heartbeat on a configurable interval
    - Two-way Slack integration (listens + responds)
    - Full conversational memory via Supabase
    - Tool use: any function the agent can call autonomously
    - Identity: name, voice, system prompt loaded from config file

    Usage:
        agent = PersistentAgent(
            identity_path="identities/head-of-operations.json",
            tools_path="config/tools.json"
        )
        agent.start()  # blocks — runs forever
    """

    def __init__(self, identity_path: str, tools_path: str):
        self.client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
        self.model = os.environ.get("AGENT_MODEL", "claude-sonnet-4-5")

        self.identity = Identity(identity_path)
        self.memory = Memory()
        self.tool_registry = ToolRegistry(tools_path)

        self._heartbeat_thread = None
        self._running = False

        logger.info(f"[{self.identity.name}] Initialized — {self.identity.title} at {self.identity.company}")

    # ─────────────────────────────────────────────
    # Startup
    # ─────────────────────────────────────────────

    def start(self):
        """Start the agent. Launches heartbeat in background, blocks on Slack listener."""
        self._running = True
        logger.info(f"[{self.identity.name}] Starting up...")

        # Start heartbeat in background thread
        self._heartbeat_thread = threading.Thread(target=self._heartbeat_loop, daemon=True)
        self._heartbeat_thread.start()
        logger.info(f"[{self.identity.name}] Heartbeat started — every {self.identity.heartbeat_interval_minutes} minutes")

        # Announce startup to Slack
        self._post_startup_message()

        # Block on Slack listener (started by slack_listener.py, which calls agent methods)
        # The Slack app runs its own event loop — we just keep this thread alive
        try:
            while self._running:
                time.sleep(1)
        except KeyboardInterrupt:
            self.stop()

    def stop(self):
        self._running = False
        logger.info(f"[{self.identity.name}] Shutting down.")

    # ─────────────────────────────────────────────
    # Heartbeat
    # ─────────────────────────────────────────────

    def _heartbeat_loop(self):
        """Run heartbeat on the configured interval. Checks pipeline, fires actions."""
        while self._running:
            try:
                self._run_heartbeat_cycle()
            except Exception as e:
                logger.error(f"[{self.identity.name}] Heartbeat error: {e}", exc_info=True)

            time.sleep(self.identity.heartbeat_interval_minutes * 60)

    def _run_heartbeat_cycle(self):
        """One complete heartbeat: read state, decide actions, post if needed."""
        now = datetime.now(ET)
        logger.info(f"[{self.identity.name}] Heartbeat — {now.strftime('%H:%M ET')}")

        # Log heartbeat so the Operations tab can show "last seen X minutes ago"
        try:
            self.memory.log_action('heartbeat', details={'cycle_time': now.isoformat()})
        except Exception as e:
            logger.warning(f"[{self.identity.name}] Could not log heartbeat: {e}")

        # Load current pipeline context
        context = self.memory.get_pipeline_context()

        # Build the heartbeat prompt
        is_morning = now.hour == self.identity.morning_brief_hour
        is_evening = now.hour == self.identity.evening_brief_hour

        if is_morning:
            prompt = f"It's your morning briefing time ({now.strftime('%B %d, %Y %H:%M ET')}). Review the pipeline and send Justin the morning brief. Pipeline state: {json.dumps(context, indent=2)}"
        elif is_evening:
            prompt = f"It's your evening summary time ({now.strftime('%B %d, %Y %H:%M ET')}). Send Justin the evening summary. Pipeline state: {json.dumps(context, indent=2)}"
        else:
            prompt = f"Heartbeat check ({now.strftime('%H:%M ET')}). Review the pipeline state and take any necessary actions. Do NOT send a Slack message unless something requires attention. Pipeline state: {json.dumps(context, indent=2)}"

        messages = [{"role": "user", "content": prompt}]
        self._run_agentic_loop(messages, context_label="heartbeat")

    # ─────────────────────────────────────────────
    # Message Handling (called by Slack listener)
    # ─────────────────────────────────────────────

    def handle_message(self, user_id: str, text: str, channel: str, files: list = None) -> str:
        """
        Process an incoming Slack message. Returns the reply text.
        Called by slack_listener.py when a message arrives.
        """
        logger.info(f"[{self.identity.name}] Message from {user_id}: {text[:80]}...")

        # Build content — include file contents if any were shared
        content = text
        if files:
            for f in files:
                content += f"\n\n[Attached file: {f.get('name', 'file')}]\n{f.get('content', '[file content not extracted]')}"

        # Load conversation history for this user
        history = self.memory.get_conversation_history(user_id, limit=20)

        messages = history + [{"role": "user", "content": content}]

        # Run the full agentic loop
        reply = self._run_agentic_loop(messages, context_label=f"message:{user_id}")

        # Persist to memory
        self.memory.save_message(user_id, "user", text)
        self.memory.save_message(user_id, "assistant", reply)

        return reply

    # ─────────────────────────────────────────────
    # Agentic Loop (core)
    # ─────────────────────────────────────────────

    def _run_agentic_loop(self, messages: list, context_label: str = "") -> str:
        """
        The core agentic loop. Sends messages to Claude, executes tool calls,
        feeds results back, loops until no more tool calls. Returns final text.
        """
        max_iterations = 20  # safety cap
        iteration = 0

        while iteration < max_iterations:
            iteration += 1

            response = self.client.messages.create(
                model=self.model,
                max_tokens=8096,
                system=self.identity.system_prompt,
                tools=self.tool_registry.get_tool_schemas(),
                messages=messages
            )

            logger.debug(f"[{self.identity.name}] [{context_label}] iter={iteration} stop_reason={response.stop_reason}")

            # If no tool calls, we're done
            if response.stop_reason != "tool_use":
                text_blocks = [b.text for b in response.content if hasattr(b, "text")]
                return " ".join(text_blocks).strip()

            # Execute all tool calls in this response
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    logger.info(f"[{self.identity.name}] Tool call: {block.name}({json.dumps(block.input)[:100]})")
                    result = self.tool_registry.execute(block.name, block.input)
                    logger.info(f"[{self.identity.name}] Tool result: {str(result)[:100]}")
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": json.dumps(result) if isinstance(result, (dict, list)) else str(result)
                    })

            # Append assistant message + tool results and continue
            messages = messages + [
                {"role": "assistant", "content": response.content},
                {"role": "user", "content": tool_results}
            ]

        logger.warning(f"[{self.identity.name}] Hit max iterations ({max_iterations}) in agentic loop")
        return "I've been working on this — hit my iteration limit. Check the logs for details."

    # ─────────────────────────────────────────────
    # Startup announcement
    # ─────────────────────────────────────────────

    def _post_startup_message(self):
        """Post a brief startup message so Justin knows the agent is live."""
        try:
            slack_tool = self.tool_registry.get_tool("post_slack_message")
            if slack_tool:
                self.tool_registry.execute("post_slack_message", {
                    "channel": self.identity.ops_channel,
                    "text": f"✅ {self.identity.name} is online. Heartbeat active every {self.identity.heartbeat_interval_minutes} minutes."
                })
        except Exception as e:
            logger.warning(f"Could not post startup message: {e}")
