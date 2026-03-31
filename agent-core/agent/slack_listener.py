"""
slack_listener.py — Slack Bolt listener

Two-way Slack integration. The agent listens for:
  - Direct messages
  - @mentions in any channel it's in
  - Messages in its configured ops channel

Sends replies back in the same channel/thread.
Handles file uploads (transcripts, notes, PDFs).

Requires:
  SLACK_BOT_TOKEN  — xoxb-... (Bot User OAuth Token)
  SLACK_APP_TOKEN  — xapp-... (for Socket Mode / no public URL needed)
"""

import os
import logging
import requests
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

logger = logging.getLogger(__name__)


def create_slack_app(agent) -> App:
    """
    Creates and configures the Slack Bolt app.
    Pass in the PersistentAgent instance so handlers can call agent.handle_message().
    """
    app = App(token=os.environ["SLACK_BOT_TOKEN"])

    # ─────────────────────────────────────────────
    # Direct Messages
    # ─────────────────────────────────────────────

    @app.event("message")
    def handle_dm(event, say, client):
        """Handle all incoming messages — DMs and channel mentions."""
        # Skip bot messages (don't respond to yourself)
        if event.get("bot_id") or event.get("subtype") == "bot_message":
            return

        user_id = event.get("user")
        text = event.get("text", "")
        channel = event.get("channel")
        thread_ts = event.get("thread_ts") or event.get("ts")
        files = event.get("files", [])

        if not text and not files:
            return

        # Extract file contents if any files were shared
        extracted_files = []
        for f in files:
            content = _extract_file_content(f, client)
            if content:
                extracted_files.append({
                    "name": f.get("name", "file"),
                    "type": f.get("filetype", ""),
                    "content": content
                })

        # Post "typing" indicator
        try:
            client.reactions_add(channel=channel, name="thinking_face", timestamp=event.get("ts"))
        except Exception:
            pass

        # Get response from agent
        reply = agent.handle_message(
            user_id=user_id,
            text=text,
            channel=channel,
            files=extracted_files if extracted_files else None
        )

        # Remove typing indicator
        try:
            client.reactions_remove(channel=channel, name="thinking_face", timestamp=event.get("ts"))
        except Exception:
            pass

        # Reply in thread
        say(text=reply, thread_ts=thread_ts)

    # ─────────────────────────────────────────────
    # App Mentions (@ the bot in channels)
    # ─────────────────────────────────────────────

    @app.event("app_mention")
    def handle_mention(event, say):
        """Handle @mentions in channels."""
        user_id = event.get("user")
        text = event.get("text", "")
        channel = event.get("channel")
        thread_ts = event.get("thread_ts") or event.get("ts")

        # Strip the mention prefix (@BotName)
        import re
        text = re.sub(r"<@[A-Z0-9]+>", "", text).strip()

        if not text:
            say(text="What do you need?", thread_ts=thread_ts)
            return

        reply = agent.handle_message(user_id=user_id, text=text, channel=channel)
        say(text=reply, thread_ts=thread_ts)

    return app


def start_slack_listener(agent):
    """
    Start the Slack Socket Mode listener.
    Runs in its own thread — does not block the main process.
    """
    import threading

    def _run():
        app = create_slack_app(agent)
        handler = SocketModeHandler(app, os.environ["SLACK_APP_TOKEN"])
        logger.info(f"[{agent.identity.name}] Slack listener starting (Socket Mode)...")
        handler.start()

    thread = threading.Thread(target=_run, daemon=True)
    thread.start()
    logger.info(f"[{agent.identity.name}] Slack listener started")
    return thread


def _extract_file_content(file_info: dict, client) -> str:
    """
    Download and extract text content from a Slack file.
    Handles: plain text, markdown, PDF (text extraction), transcripts.
    """
    filetype = file_info.get("filetype", "")
    url = file_info.get("url_private_download") or file_info.get("url_private")

    if not url:
        return ""

    try:
        headers = {"Authorization": f"Bearer {os.environ['SLACK_BOT_TOKEN']}"}
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()

        if filetype in ("txt", "md", "text", "markdown"):
            return response.text[:50000]  # Cap at 50k chars

        elif filetype == "pdf":
            # Try to extract text from PDF
            try:
                import io
                from pypdf import PdfReader
                reader = PdfReader(io.BytesIO(response.content))
                text = "\n".join(page.extract_text() or "" for page in reader.pages)
                return text[:50000]
            except ImportError:
                return f"[PDF uploaded: {file_info.get('name')} — install pypdf to extract text]"

        elif filetype in ("docx",):
            try:
                import io
                import docx
                doc = docx.Document(io.BytesIO(response.content))
                text = "\n".join(p.text for p in doc.paragraphs)
                return text[:50000]
            except ImportError:
                return f"[DOCX uploaded: {file_info.get('name')} — install python-docx to extract text]"

        else:
            # Try to decode as text anyway
            try:
                return response.text[:50000]
            except Exception:
                return f"[File uploaded: {file_info.get('name')} ({filetype}) — type not supported for text extraction]"

    except Exception as e:
        logger.error(f"Failed to extract file content: {e}")
        return f"[Could not read file: {file_info.get('name')} — {e}]"
