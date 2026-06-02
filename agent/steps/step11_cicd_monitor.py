"""
CI/CD apply monitor.
Triggers apply for each selected env, consumes CicdEvent objects from the webhook queue,
and invokes remediation when a module fails.
"""
from __future__ import annotations

import asyncio
import os
from typing import TYPE_CHECKING

import httpx
import structlog

from agent.cicd.error_classifier import classify
from agent.cicd.remediation import execute_remediation
from agent.models.run_state import CicdEventType

if TYPE_CHECKING:
    from agent.models.run_state import RunState, CicdEvent
    from agent.orchestrator import StepContext

log = structlog.get_logger()

APPLY_TIMEOUT_S = 60 * 60  # 1 h per env
RESUME_TIMEOUT_S = 7 * 24 * 3600
OBS_POLL_INTERVAL_S = 30


async def _dispatch_apply(run_id: str, env: str, tfvars_obs_key: str) -> None:
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
                "event_type": "lz-agent-apply",
                "client_payload": {"run_id": run_id, "env": env, "tfvars_obs_key": tfvars_obs_key},
            },
        )
        resp.raise_for_status()
    log.info("apply_dispatched", env=env)


async def _next_event(
    cicd_queue: asyncio.Queue,
    obs_poll_fn,
    run_id: str,
    last_obs_seq: int,
) -> tuple["CicdEvent", int]:
    """Return next event from webhook queue or OBS fallback poll."""
    while True:
        try:
            event = await asyncio.wait_for(cicd_queue.get(), timeout=OBS_POLL_INTERVAL_S)
            return event, last_obs_seq
        except asyncio.TimeoutError:
            # Poll OBS for runner-written events
            obs_events = obs_poll_fn(run_id, after_seq=last_obs_seq)
            for item in obs_events:
                from agent.models.run_state import CicdEvent as _CE, CicdEventType as _CET
                ev_data = item["event"]
                event = _CE(
                    event_type=_CET(ev_data.get("event_type", "STEP_ERROR")),
                    run_id=run_id,
                    module=ev_data.get("module"),
                    resource=ev_data.get("resource"),
                    error_code=ev_data.get("error_code"),
                    error_message=ev_data.get("error_message"),
                )
                last_obs_seq = item["seq"]
                await cicd_queue.put(event)


async def execute(state: "RunState", ctx: "StepContext") -> None:
    from agent.utils.obs_state import poll_cicd_events

    for env in state.deploy_envs:
        if env in state.envs_applied:
            log.info("env_already_applied_skipping", env=env)
            continue

        state.current_env = env
        tfvars_key = f"agent-runs/{state.run_id}/artifacts/{env}/terraform.tfvars"
        await _dispatch_apply(state.run_id, env, tfvars_key)
        log.info("apply_monitoring_start", env=env)

        last_obs_seq = 0
        env_done = False

        while not env_done:
            try:
                event, last_obs_seq = await asyncio.wait_for(
                    _next_event(ctx.cicd_queue, poll_cicd_events, state.run_id, last_obs_seq),
                    timeout=APPLY_TIMEOUT_S,
                )
            except asyncio.TimeoutError:
                raise RuntimeError(f"Apply timeout for env {env} after {APPLY_TIMEOUT_S}s")

            state.current_module = event.module

            if event.event_type == CicdEventType.STEP_SUCCESS:
                if event.module and event.module.startswith("apply_done:"):
                    log.info("env_apply_complete", env=env)
                    state.envs_applied.append(env)
                    env_done = True
                else:
                    log.info("module_apply_success", module=event.module)

            elif event.event_type == CicdEventType.STEP_ERROR:
                cls = classify(event.error_code, event.error_message or "")
                log.info("module_apply_error", module=event.module, category=cls.category)

                should_retry = await execute_remediation(event, state, ctx, cls)

                if not should_retry:
                    # Escalation email was sent; wait for RESUME or ABORT
                    try:
                        reply = await asyncio.wait_for(
                            ctx.reply_queue.get(), timeout=RESUME_TIMEOUT_S
                        )
                    except asyncio.TimeoutError:
                        raise RuntimeError(f"Escalation timeout for module {event.module}")

                    if "ABORT" in reply.upper():
                        raise RuntimeError(f"Deployment aborted by engineer at module {event.module}")
                    # RESUME → re-dispatch apply for remaining modules from current point
                    log.info("escalation_resumed", module=event.module)
                    await _dispatch_apply(state.run_id, env, tfvars_key)
