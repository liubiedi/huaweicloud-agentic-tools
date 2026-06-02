"""
Plan gate: trigger the CI validate job for each selected env,
wait for the plan output via CI/CD events, self-correct up to MAX_SELF_CORRECT times.
"""
from __future__ import annotations

import asyncio
import os
from typing import TYPE_CHECKING

import httpx
import structlog

from agent.models.run_state import CicdEventType

if TYPE_CHECKING:
    from agent.models.run_state import RunState, CicdEvent
    from agent.orchestrator import StepContext

log = structlog.get_logger()

MAX_SELF_CORRECT = 3
GATE_TIMEOUT_S = 30 * 60  # 30 min per env


async def _dispatch_workflow(run_id: str, env: str, tfvars_obs_key: str) -> None:
    """Trigger GitHub Actions validate workflow via repository_dispatch."""
    token = os.environ["GITHUB_TOKEN"]
    repo = os.environ.get("GITHUB_REPOSITORY", "liubiedi/huaweicloud-agentic-tools")
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"https://api.github.com/repos/{repo}/dispatches",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
            json={
                "event_type": "lz-agent-validate",
                "client_payload": {
                    "run_id": run_id,
                    "env": env,
                    "tfvars_obs_key": tfvars_obs_key,
                },
            },
        )
        resp.raise_for_status()
    log.info("validate_workflow_dispatched", env=env, run_id=run_id)


async def _wait_for_gate_event(
    cicd_queue: asyncio.Queue,
    run_id: str,
    env: str,
) -> "CicdEvent":
    """Wait for STEP_SUCCESS or STEP_ERROR event from the validate job."""
    while True:
        try:
            event = await asyncio.wait_for(cicd_queue.get(), timeout=GATE_TIMEOUT_S)
        except asyncio.TimeoutError:
            raise RuntimeError(f"Plan gate timeout for env {env} (run {run_id})")
        if event.module == f"validate:{env}":
            return event


async def execute(state: "RunState", ctx: "StepContext") -> None:
    for env in state.deploy_envs:
        tfvars_key = f"agent-runs/{state.run_id}/artifacts/{env}/terraform.tfvars"
        cicd_queue = ctx.cicd_queue

        for attempt in range(1, MAX_SELF_CORRECT + 2):
            log.info("plan_gate_attempt", env=env, attempt=attempt)
            await _dispatch_workflow(state.run_id, env, tfvars_key)

            event = await _wait_for_gate_event(cicd_queue, state.run_id, env)

            if event.event_type == CicdEventType.STEP_SUCCESS:
                plan_text = event.error_message or ""  # CI repurposes this field for plan output
                state.plan_summary = (state.plan_summary or "") + f"\n\n### {env}\n{plan_text}"
                log.info("plan_gate_passed", env=env)
                break

            if attempt > MAX_SELF_CORRECT:
                raise RuntimeError(
                    f"Plan gate failed for env {env} after {MAX_SELF_CORRECT} self-correct attempts. "
                    f"Last error: {event.error_message}"
                )

            log.warning("plan_gate_failed_self_correcting", env=env, attempt=attempt,
                        error=event.error_message)
            # Self-correct: re-render tfvars with any LLD corrections applied by previous step
            # For MVP: just retry; Phase 2 will add LLM-driven tfvars correction
            await asyncio.sleep(10)
