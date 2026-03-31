"""
identity.py — Identity loader

Loads an agent's identity from a JSON config file.
The identity defines: who the agent is, how they speak, when they run,
and what system prompt they operate under.

Swap the identity file to create an entirely different agent persona
with no code changes.
"""

import json
from pathlib import Path


class Identity:
    """
    Represents a single agent's complete identity.

    Fields loaded from identity JSON:
      name                   — The agent's first name (e.g. "Morgan")
      title                  — Job title (e.g. "Head of Operations")
      company                — Company name (e.g. "AI Integraterz")
      voice                  — Voice/tone description for the system prompt
      system_prompt          — Full Claude system prompt (can reference {name}, {title}, etc.)
      heartbeat_interval_minutes — How often the heartbeat fires
      morning_brief_hour     — ET hour for morning brief (24h, e.g. 8)
      evening_brief_hour     — ET hour for evening brief (24h, e.g. 20)
      ops_channel            — Primary Slack channel for ops updates
      dm_user_env_var        — Environment variable name holding Justin's Slack user ID
    """

    def __init__(self, identity_path: str):
        path = Path(identity_path)
        if not path.exists():
            raise FileNotFoundError(f"Identity file not found: {identity_path}")

        with open(path) as f:
            data = json.load(f)

        self.name = data["name"]
        self.title = data["title"]
        self.company = data["company"]
        self.voice = data.get("voice", "")

        # Format the system prompt — substitute identity fields.
        # Uses format_map with a default-returning mapping so that any
        # literal {braces} in the prompt that are NOT substitution variables
        # are left as-is instead of raising KeyError (which would crash startup).
        raw_prompt = data["system_prompt"]
        substitutions = {
            "name": self.name,
            "title": self.title,
            "company": self.company,
            "voice": self.voice,
        }

        class _SafeMap(dict):
            def __missing__(self, key):
                # Return the original placeholder so unknown {vars} survive
                return "{" + key + "}"

        self.system_prompt = raw_prompt.format_map(_SafeMap(substitutions))

        self.heartbeat_interval_minutes = data.get("heartbeat_interval_minutes", 30)
        self.morning_brief_hour = data.get("morning_brief_hour_et", 8)
        self.evening_brief_hour = data.get("evening_brief_hour_et", 20)
        self.ops_channel = data.get("ops_channel", "general")
        self.dm_user_env_var = data.get("dm_user_env_var", "AGENT_DM_USER_ID")

        # Raw config stored for any custom use
        self._raw = data

    def get(self, key: str, default=None):
        return self._raw.get(key, default)
