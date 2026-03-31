"""
base_tools.py — Generic tools available to every agent in every project

These tools are domain-agnostic. They work regardless of what project
agent-core is deployed in. Do not put project-specific logic here.

Project-specific tools (create_client, run_agent, etc.) go in:
  tools/domain_tools.py  ← copy the template, fill it in per project

Generic tools included here:
  - web_fetch()       — fetch a URL and return the text
  - read_file()       — read a local file (transcripts, notes, configs)
  - get_current_time()— current timestamp in ET
  - search_memory()   — search conversation history for a term
"""

import os
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

logger = logging.getLogger(__name__)
ET = ZoneInfo("America/New_York")


def get_current_time() -> dict:
    """
    Returns current time in Eastern Time.
    Use when you need to know the current date/time for briefs,
    scheduling, or date calculations.
    """
    now = datetime.now(ET)
    return {
        "datetime": now.isoformat(),
        "date": now.strftime("%B %d, %Y"),
        "time": now.strftime("%I:%M %p ET"),
        "day_of_week": now.strftime("%A"),
        "hour_24": now.hour
    }


def read_file(file_path: str, max_chars: int = 50000) -> dict:
    """
    Read a local file and return its contents.
    Useful for reading transcripts, notes, or config files
    that Justin drops on the server or shares a path for.

    Args:
        file_path: Absolute or relative path to the file
        max_chars: Maximum characters to return (default 50k)
    """
    try:
        # Expand home directory
        path = os.path.expanduser(file_path)

        if not os.path.exists(path):
            return {"error": f"File not found: {file_path}"}

        # Safety check — don't read sensitive files
        blocked = [".env", "id_rsa", "id_ed25519", ".pem", ".key"]
        if any(b in os.path.basename(path) for b in blocked):
            return {"error": f"Reading this file type is not allowed for security reasons"}

        with open(path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read(max_chars)

        return {
            "path": file_path,
            "content": content,
            "truncated": len(content) == max_chars,
            "char_count": len(content)
        }
    except Exception as e:
        logger.error(f"read_file({file_path}) failed: {e}")
        return {"error": str(e)}


def web_fetch(url: str, max_chars: int = 20000) -> dict:
    """
    Fetch a URL and return the text content.
    Useful for checking a client's website before a call,
    or pulling public information.

    Args:
        url: URL to fetch
        max_chars: Maximum characters to return
    """
    try:
        import requests
        from html.parser import HTMLParser

        class TextExtractor(HTMLParser):
            def __init__(self):
                super().__init__()
                self.text = []
                self._skip = False

            def handle_starttag(self, tag, attrs):
                if tag in ("script", "style", "nav", "footer"):
                    self._skip = True

            def handle_endtag(self, tag):
                if tag in ("script", "style", "nav", "footer"):
                    self._skip = False

            def handle_data(self, data):
                if not self._skip and data.strip():
                    self.text.append(data.strip())

        response = requests.get(url, timeout=15, headers={"User-Agent": "Mozilla/5.0"})
        response.raise_for_status()

        content_type = response.headers.get("Content-Type", "")
        if "text/html" in content_type:
            extractor = TextExtractor()
            extractor.feed(response.text)
            text = " ".join(extractor.text)
        else:
            text = response.text

        return {
            "url": url,
            "content": text[:max_chars],
            "truncated": len(text) > max_chars
        }
    except Exception as e:
        logger.error(f"web_fetch({url}) failed: {e}")
        return {"error": str(e)}


def calculate_days_since(date_string: str) -> dict:
    """
    Calculate days between a past date and today.
    Used for checkpoint timing, upsell delay checks, etc.

    Args:
        date_string: ISO date string (e.g. "2026-03-01T00:00:00Z")
    """
    try:
        from datetime import timezone
        past = datetime.fromisoformat(date_string.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        delta = now - past
        return {
            "days": delta.days,
            "hours": int(delta.total_seconds() / 3600),
            "from_date": date_string,
            "to_date": now.isoformat()
        }
    except Exception as e:
        return {"error": str(e)}
