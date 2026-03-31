"""
main.py — Agent entrypoint

Start the persistent agent:
    python main.py

Or with a custom identity:
    IDENTITY_FILE=identities/coo-template.json python main.py

Environment variables required:
    ANTHROPIC_API_KEY         — Anthropic API key
    SLACK_BOT_TOKEN           — xoxb-... Slack bot token
    SLACK_APP_TOKEN           — xapp-... for Socket Mode
    SUPABASE_URL              — Supabase project URL
    SUPABASE_SERVICE_ROLE_KEY — Supabase service role key

Optional:
    IDENTITY_FILE             — Path to identity JSON (default: identities/head-of-operations.json)
    TOOLS_FILE                — Path to tools JSON (default: config/tools.json)
    AGENT_MODEL               — Claude model (default: claude-sonnet-4-5)
    PIPELINE_RUNNER_URL       — DigitalOcean runner URL (if running agents remotely)
    PIPELINE_API_SECRET       — Shared secret for pipeline runner
    JUSTIN_SLACK_USER_ID      — Justin's Slack user ID for DMs and channel invites
    AI_INTEGRATERZ_REPO       — Path to ai-integraterz repo (default: ~/Desktop/ai-integraterz)
"""

import os
import sys
import logging

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, log_level, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger(__name__)


def check_env():
    """Verify required environment variables are set."""
    required = [
        "ANTHROPIC_API_KEY",
        "SLACK_BOT_TOKEN",
        # SLACK_APP_TOKEN is the xapp-... App-Level Token required for Socket Mode.
        # Without it the agent cannot receive Slack events (no public URL needed).
        # Get it at: api.slack.com → Your App → Basic Information → App-Level Tokens
        # The token must have the connections:write scope.
        "SLACK_APP_TOKEN",
        "SUPABASE_URL",
        "SUPABASE_SERVICE_ROLE_KEY"
    ]
    missing = [v for v in required if not os.environ.get(v)]
    if missing:
        logger.error(f"Missing required environment variables: {', '.join(missing)}")
        if "SLACK_APP_TOKEN" in missing:
            logger.error(
                "SLACK_APP_TOKEN (xapp-...) is needed for Slack Socket Mode. "
                "Get it at api.slack.com → Your App → Basic Information → App-Level Tokens "
                "(requires connections:write scope). It is separate from SLACK_BOT_TOKEN."
            )
        logger.error("Copy .env.example to .env and fill in the values.")
        sys.exit(1)


def main():
    check_env()

    identity_path = os.environ.get("IDENTITY_FILE", "identities/head-of-operations.json")
    tools_path = os.environ.get("TOOLS_FILE", "config/tools.json")

    logger.info(f"Loading identity: {identity_path}")
    logger.info(f"Loading tools: {tools_path}")

    # Import here so env check runs first
    from agent import PersistentAgent, start_slack_listener

    agent = PersistentAgent(
        identity_path=identity_path,
        tools_path=tools_path
    )

    # Start Slack listener in background thread
    start_slack_listener(agent)

    # Start agent (heartbeat loop + blocks)
    agent.start()


if __name__ == "__main__":
    main()
