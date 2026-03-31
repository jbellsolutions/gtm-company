"""
tools.py — Tool Registry

Manages all tools available to the agent. Tools are:
1. Defined in config/tools.json (schema + metadata)
2. Implemented in tools/*.py (actual Python functions)
3. Called by the agentic loop when Claude requests them

To add a new tool:
  1. Add the schema to config/tools.json
  2. Implement the function in tools/<category>_tools.py
  3. Register it here in TOOL_IMPLEMENTATIONS

The tool registry is identity-agnostic. Load a different tools.json
to give a different agent a different toolset.
"""

import json
import logging
from pathlib import Path
from typing import Any, Callable, Optional

logger = logging.getLogger(__name__)


class ToolRegistry:
    """
    Loads tool schemas from JSON and maps them to Python implementations.
    Handles execution with error catching — a tool failure never crashes the agent.
    """

    def __init__(self, tools_path: str):
        self._schemas: list = []
        self._implementations: dict[str, Callable] = {}

        self._load_schemas(tools_path)
        self._register_implementations()

    def _load_schemas(self, tools_path: str):
        """Load tool definitions from JSON file."""
        path = Path(tools_path)
        if not path.exists():
            raise FileNotFoundError(f"Tools config not found: {tools_path}")

        with open(path) as f:
            data = json.load(f)

        self._schemas = data.get("tools", [])
        logger.info(f"Loaded {len(self._schemas)} tool schemas from {tools_path}")

    def _register_implementations(self):
        """
        Map tool names to their Python implementations.

        Loading order:
          1. base_tools      — generic, domain-agnostic tools (always loaded)
          2. slack_tools     — Slack posting and channel management
          3. supabase_tools  — generic database reads
          4. pipeline_tools  — AI Integraterz-specific pipeline operations
          5. domain_tools    — project-specific overrides (optional, loaded if present)

        To add tools for a new project: create tools/domain_tools.py and
        add your implementations here.
        """
        # 1. Base tools — generic, always available
        try:
            from tools.base_tools import (
                get_current_time,
                read_file,
                web_fetch,
                calculate_days_since
            )
            self._implementations.update({
                "get_current_time": get_current_time,
                "read_file": read_file,
                "web_fetch": web_fetch,
                "calculate_days_since": calculate_days_since,
            })
        except ImportError as e:
            logger.warning(f"base_tools not available: {e}")

        # 2. Slack tools
        try:
            from tools.slack_tools import (
                post_slack_message,
                create_slack_channel,
                post_to_channel,
                dm_user
            )
            self._implementations.update({
                "post_slack_message": post_slack_message,
                "create_slack_channel": create_slack_channel,
                "post_to_channel": post_to_channel,
                "dm_user": dm_user,
            })
        except ImportError as e:
            logger.warning(f"slack_tools not available: {e}")

        # 3. Supabase generic read tools
        try:
            from tools.supabase_tools import (
                read_table,
                get_recent_outputs,
                get_upsell_signals,
                log_upsell_action,
                search_entity
            )
            self._implementations.update({
                "read_table": read_table,
                "get_recent_outputs": get_recent_outputs,
                "get_upsell_signals": get_upsell_signals,
                "log_upsell_action": log_upsell_action,
                "search_entity": search_entity,
            })
        except ImportError as e:
            logger.warning(f"supabase_tools not available: {e}")

        # 4. AI Integraterz pipeline tools (project-specific)
        try:
            from tools.pipeline_tools import (
                create_client,
                run_agent,
                get_pipeline_status,
                get_client_info,
                update_client_stage
            )
            self._implementations.update({
                "create_client": create_client,
                "run_agent": run_agent,
                "get_pipeline_status": get_pipeline_status,
                "get_client_info": get_client_info,
                "update_client_stage": update_client_stage,
            })
        except ImportError as e:
            logger.warning(f"pipeline_tools not available (expected for non-AI Integraterz projects): {e}")

        # 5. Project-specific domain tools (optional override)
        # Copy tools/domain_tools_template.py → tools/domain_tools.py for new projects
        try:
            import importlib
            domain = importlib.import_module("tools.domain_tools")
            domain_tools = {
                name: getattr(domain, name)
                for name in dir(domain)
                # Only register functions actually defined in this module —
                # not imported helpers, classes, or constants from other modules.
                if (
                    callable(getattr(domain, name))
                    and not name.startswith("_")
                    and getattr(getattr(domain, name), "__module__", None) == domain.__name__
                )
            }
            self._implementations.update(domain_tools)
            logger.info(f"Loaded {len(domain_tools)} domain tools from domain_tools.py")
        except ModuleNotFoundError:
            pass  # No domain_tools.py — that's fine
        except Exception as e:
            logger.warning(f"domain_tools failed to load: {e}")

        logger.info(f"Registered {len(self._implementations)} total tool implementations")

    def get_tool_schemas(self) -> list:
        """Returns tool schemas in Claude API format."""
        return self._schemas

    def get_tool(self, name: str) -> Optional[Callable]:
        """Returns a specific tool implementation by name, or None."""
        return self._implementations.get(name)

    def execute(self, name: str, inputs: dict) -> Any:
        """
        Execute a tool by name with the given inputs.
        Always returns something — never raises. Failures return error dict.
        """
        impl = self._implementations.get(name)

        if impl is None:
            logger.error(f"Tool not found: {name}")
            return {"error": f"Tool '{name}' is not implemented", "available": list(self._implementations.keys())}

        try:
            result = impl(**inputs)
            return result
        except TypeError as e:
            logger.error(f"Tool {name} called with wrong args: {e}")
            return {"error": f"Wrong arguments for '{name}': {e}"}
        except Exception as e:
            logger.error(f"Tool {name} failed: {e}", exc_info=True)
            return {"error": f"Tool '{name}' failed: {str(e)}"}
