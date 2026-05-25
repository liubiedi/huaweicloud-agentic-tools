"""
State machine orchestrator.
advance_run() dispatches to the correct step function and saves state to OBS
after every transition.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from typing import Any

import structlog

from agent.models.run_state import RunState, Step, TERMINAL_STEPS
from agent.utils.obs_state import save_state, load_state
from agent.utils import logger as _logger_mod

log = structlog.get_logger()


@dataclass
class StepContext:
    gmail: Any          # GmailClient
    hwc: Any            # HuaweiCloudClient
    email: Any          # module with templates attribute
    reply_queue: asyncio.Queue
    cicd_queue: asyncio.Queue


class Orchestrator:
    def __init__(self, state_store, gmail, hwc) -> None:
        self._state_store = state_store
        self._gmail = gmail
        self._hwc = hwc
        # run_id → asyncio.Queue for email replies
        self._reply_queues: dict[str, asyncio.Queue] = {}
        # run_id → asyncio.Queue for CI/CD events
        self._cicd_queues: dict[str, asyncio.Queue] = {}
        # Active RunState objects
        self._runs: dict[str, RunState] = {}

    def get_cicd_queue(self, run_id: str) -> asyncio.Queue:
        if run_id not in self._cicd_queues:
            self._cicd_queues[run_id] = asyncio.Queue()
        return self._cicd_queues[run_id]

    async def get_run(self, run_id: str) -> RunState | None:
        if run_id in self._runs:
            return self._runs[run_id]
        state = load_state(run_id)
        if state:
            self._runs[run_id] = state
        return state

    async def start_run(self, state: RunState) -> None:
        """Register a new run and begin executing from its current step."""
        self._runs[state.run_id] = state
        self._reply_queues[state.run_id] = self._gmail.get_reply_queue(state.run_id)
        self._cicd_queues[state.run_id] = asyncio.Queue()
        save_state(state)
        asyncio.create_task(self._run_loop(state.run_id))

    async def _run_loop(self, run_id: str) -> None:
        state = self._runs[run_id]
        _logger_mod.bind_run(run_id, state.step.value)
        log.info("run_started", step=state.step)

        ctx = StepContext(
            gmail=self._gmail,
            hwc=self._hwc,
            email=_email_module(),
            reply_queue=self._reply_queues[run_id],
            cicd_queue=self._cicd_queues[run_id],
        )

        while state.step not in TERMINAL_STEPS:
            _logger_mod.bind_run(run_id, state.step.value)
            step_fn = _STEP_MAP.get(state.step)
            if step_fn is None:
                log.warning("no_step_function_advancing", step=state.step)
                state.step = state.next_step()
                state.touch()
                save_state(state)
                continue

            try:
                log.info("step_start", step=state.step)
                await step_fn(state, ctx)
                state.step = state.next_step()
                state.touch()
                save_state(state)
                log.info("step_complete", next_step=state.step)

            except Exception as exc:
                log.error("step_failed", step=state.step, error=str(exc))
                state.step = Step.FAILED
                state.touch()
                save_state(state)
                # Send failure notification
                try:
                    body = ctx.email.templates.escalation_email(
                        run_id=run_id,
                        requester_name=state.requester_name or "Engineer",
                        title=f"Deployment failed at step: {state.step.value}",
                        details=str(exc),
                        suggested_action="Contact the platform team to investigate.",
                    )
                    await ctx.gmail.send(
                        to=state.requester_email,
                        subject=f"[LZ-{run_id}] Deployment FAILED",
                        body=body,
                    )
                except Exception:
                    log.error("failure_notification_send_error", run_id=run_id)
                break

        log.info("run_finished", step=state.step)

    async def handle_incoming_email(self, parsed: dict) -> None:
        """Process a newly arriving email with an LLD attachment."""
        import uuid, os, boto3 as _boto3, pathlib as _pl
        from agent.models.run_state import RunState as _RS, Step as _Step

        attachments = parsed.get("attachments", [])
        if not attachments:
            log.warning("incoming_email_no_attachment", sender=parsed.get("sender"))
            return

        run_id = parsed.get("run_id") or uuid.uuid4().hex[:12]
        att = attachments[0]
        obs_key = f"agent-runs/{run_id}/input/{att['filename']}"

        # Upload attachment to OBS
        region = os.environ["TF_STATE_REGION"]
        bucket = os.environ["TF_STATE_BUCKET"]
        client = _boto3.client(
            "s3",
            endpoint_url=f"https://obs.{region}.myhuaweicloud.com",
            aws_access_key_id=os.environ["HWC_ACCESS_KEY"],
            aws_secret_access_key=os.environ["HWC_SECRET_KEY"],
            region_name=region,
        )
        client.put_object(Bucket=bucket, Key=obs_key, Body=att["data"])
        log.info("lld_uploaded", obs_key=obs_key, run_id=run_id)

        sender = parsed.get("sender", "")
        name = sender.split("<")[0].strip() or "Engineer"

        state = _RS(
            run_id=run_id,
            step=_Step.LLD_READ,
            lld_source_key=obs_key,
            requester_email=sender,
            requester_name=name,
        )
        await self.start_run(state)

    async def watch_incoming(self) -> None:
        """Background task: process new LLD emails from the incoming queue."""
        while True:
            parsed = await self._gmail.incoming.get()
            try:
                await self.handle_incoming_email(parsed)
            except Exception as exc:
                log.error("incoming_email_error", error=str(exc))


def _email_module():
    from agent import email as _em_pkg
    import agent.email.templates as _tpl
    class _Shim:
        templates = _tpl
    return _Shim()


# ── Step dispatch table ───────────────────────────────────────────────────────

def _load_step_map():
    from agent.steps import (
        step01_lld_reader,
        step02_module_selection,
        step03_gap_fill,
        step05_validation,
        step07_preflight,
        step08_artifacts,
        step09_plan_gate,
        step10_approval,
        step11_cicd_monitor,
        step12_post_apply,
    )
    return {
        Step.LLD_READ: step01_lld_reader.execute,
        Step.MODULE_SELECTION: step02_module_selection.execute,
        Step.GAP_FILL: step03_gap_fill.execute,
        Step.VALIDATION: step05_validation.execute,
        Step.CAF_CHECK: None,  # Phase 2
        Step.PREFLIGHT: step07_preflight.execute,
        Step.ARTIFACTS: step08_artifacts.execute,
        Step.PLAN_GATE: step09_plan_gate.execute,
        Step.APPROVAL: step10_approval.execute,
        Step.CICD_EXECUTE: step11_cicd_monitor.execute,
        Step.POST_APPLY: step12_post_apply.execute,
    }


_STEP_MAP = _load_step_map()
