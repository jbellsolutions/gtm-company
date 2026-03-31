"""
slack_tools.py — Slack tools for the agent

The agent calls these to post messages, create channels, and send updates.
"""

import os
import logging
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

logger = logging.getLogger(__name__)


def _get_client() -> WebClient:
    return WebClient(token=os.environ["SLACK_BOT_TOKEN"])


def post_slack_message(channel: str, text: str, thread_ts: str = None) -> dict:
    """
    Post a message to a Slack channel.
    Use for sending updates, briefs, and alerts.
    """
    try:
        client = _get_client()
        kwargs = {"channel": channel, "text": text}
        if thread_ts:
            kwargs["thread_ts"] = thread_ts

        result = client.chat_postMessage(**kwargs)
        return {"success": True, "ts": result["ts"], "channel": result["channel"]}
    except SlackApiError as e:
        logger.error(f"Slack post failed: {e.response['error']}")
        return {"error": e.response["error"]}


def post_to_channel(channel: str, text: str) -> dict:
    """Alias for post_slack_message — post to a named channel."""
    return post_slack_message(channel=channel, text=text)


def create_slack_channel(company_name: str) -> dict:
    """
    Create a private Slack channel for a client engagement.
    Returns channel ID and name.
    Convention: client-[slugified-company-name]
    """
    import re

    # Slugify: lowercase, replace non-alphanumeric with hyphens, max 21 chars
    slug = re.sub(r"[^a-z0-9]", "-", company_name.lower())
    slug = re.sub(r"-+", "-", slug).strip("-")
    channel_name = f"client-{slug}"[:21]

    try:
        client = _get_client()
        result = client.conversations_create(name=channel_name, is_private=True)
        channel_id = result["channel"]["id"]

        # Invite the agent's operator user
        justin_user_id = os.environ.get("JUSTIN_SLACK_USER_ID")
        if justin_user_id:
            client.conversations_invite(channel=channel_id, users=justin_user_id)

        return {
            "success": True,
            "channel_id": channel_id,
            "channel_name": channel_name
        }

    except SlackApiError as e:
        error = e.response.get("error", "")
        if error == "name_taken":
            # Try appending -2
            try:
                channel_name_v2 = (channel_name[:19] + "-2")[:21]
                client = _get_client()
                result = client.conversations_create(name=channel_name_v2, is_private=True)
                return {
                    "success": True,
                    "channel_id": result["channel"]["id"],
                    "channel_name": channel_name_v2
                }
            except Exception as e2:
                return {"error": str(e2)}
        return {"error": error}


def dm_user(user_id: str, text: str) -> dict:
    """
    Send a direct message to a specific Slack user.
    Used for morning/evening briefs to Justin.
    """
    try:
        client = _get_client()
        # Open a DM channel
        im = client.conversations_open(users=user_id)
        channel = im["channel"]["id"]

        result = client.chat_postMessage(channel=channel, text=text)
        return {"success": True, "ts": result["ts"]}
    except SlackApiError as e:
        logger.error(f"Slack DM failed: {e.response['error']}")
        return {"error": e.response["error"]}
