"""
LZ Agent entry point.
Starts the FastAPI webhook server, GCP Pub/Sub polling, and the incoming-email watcher.
"""
from __future__ import annotations

import asyncio
import os

import structlog
import uvicorn

from agent.utils.logger import configure_logging
from agent.email.gmail_client import GmailClient
from agent.cloud.huaweicloud_client import HuaweiCloudClient
from agent.utils.obs_state import save_state, load_state
from agent.orchestrator import Orchestrator
from agent.cicd.webhook_server import create_webhook_app

log = structlog.get_logger()


async def _main() -> None:
    configure_logging(os.environ.get("LOG_LEVEL", "INFO"))
    log.info("lz_agent_starting")

    gmail = GmailClient()
    hwc = HuaweiCloudClient()
    orchestrator = Orchestrator(state_store=None, gmail=gmail, hwc=hwc)

    # Configure Gmail watch (idempotent — renews push subscription)
    await gmail.setup_gmail_watch()

    app = create_webhook_app(orchestrator=orchestrator)

    config = uvicorn.Config(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("WEBHOOK_PORT", "8080")),
        log_config=None,  # use structlog
    )
    server = uvicorn.Server(config)

    tasks = [
        asyncio.create_task(server.serve(), name="webhook-server"),
        asyncio.create_task(gmail.poll_pubsub_forever(), name="pubsub-poller"),
        asyncio.create_task(orchestrator.watch_incoming(), name="incoming-watcher"),
    ]
    log.info("lz_agent_ready", port=config.port)

    try:
        await asyncio.gather(*tasks)
    finally:
        await hwc.close()
        for t in tasks:
            t.cancel()


if __name__ == "__main__":
    asyncio.run(_main())
