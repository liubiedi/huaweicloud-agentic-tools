"""
FastAPI webhook receiver for CI/CD runner events.
HMAC-SHA256 authenticated. Puts CicdEvent onto per-run asyncio queues.
"""
from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any

import structlog
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse

from agent.models.run_state import CicdEvent, CicdEventType

if TYPE_CHECKING:
    pass

log = structlog.get_logger()


def create_webhook_app(orchestrator) -> FastAPI:
    app = FastAPI(title="LZ Agent Webhook")

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok"}

    @app.post("/webhook/{run_id}")
    async def receive_event(run_id: str, request: Request) -> JSONResponse:
        body = await request.body()
        payload = json.loads(body)

        # Verify HMAC signature
        run_state = await orchestrator.get_run(run_id)
        if run_state is None:
            raise HTTPException(status_code=404, detail=f"Unknown run_id: {run_id}")

        expected_sig = hmac.new(
            run_state.hmac_token.encode(),
            body,
            hashlib.sha256,
        ).hexdigest()
        received_sig = request.headers.get("X-Agent-Signature", "")
        if not hmac.compare_digest(expected_sig, received_sig):
            log.warning("webhook_signature_mismatch", run_id=run_id)
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid signature")

        event = CicdEvent(
            event_type=CicdEventType(payload.get("event_type", "STEP_ERROR")),
            run_id=run_id,
            module=payload.get("module"),
            resource=payload.get("resource"),
            error_code=payload.get("error_code"),
            error_message=payload.get("error_message"),
            timestamp=datetime.now(timezone.utc),
        )

        queue = orchestrator.get_cicd_queue(run_id)
        await queue.put(event)
        log.info("webhook_event_received", run_id=run_id, event_type=event.event_type, module=event.module)

        return JSONResponse({"accepted": True})

    return app
