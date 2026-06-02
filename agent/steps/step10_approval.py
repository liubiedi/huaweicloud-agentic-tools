"""
Approval gate: email the plan summary and wait for APPROVE / REJECT.
"""
from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

import structlog

if TYPE_CHECKING:
    from agent.models.run_state import RunState
    from agent.orchestrator import StepContext

log = structlog.get_logger()

APPROVAL_TIMEOUT_S = 48 * 3600  # 48 h


async def execute(state: "RunState", ctx: "StepContext") -> None:
    env_list = ", ".join(state.deploy_envs)
    plan_text = state.plan_summary or "(plan output not captured)"

    body = ctx.email.templates.approval_email(
        run_id=state.run_id,
        requester_name=state.requester_name or "Engineer",
        env=env_list,
        plan_summary=plan_text,
    )

    msg_id = await ctx.gmail.send(
        to=state.requester_email,
        subject=f"[LZ-{state.run_id}] Approval required — terraform apply",
        body=body,
    )
    state.approval_email_id = msg_id
    log.info("approval_email_sent", message_id=msg_id)

    try:
        reply = await asyncio.wait_for(ctx.reply_queue.get(), timeout=APPROVAL_TIMEOUT_S)
    except asyncio.TimeoutError:
        raise RuntimeError(f"Approval timeout: no reply within 48h for run {state.run_id}")

    upper = reply.upper()
    if "REJECT" in upper:
        raise RuntimeError("Deployment rejected by engineer at approval gate.")
    if "APPROVE" in upper:
        log.info("deployment_approved")
        return

    # Unrecognised reply — treat as APPROVE with warning
    log.warning("approval_reply_unrecognised_treating_as_approve", reply=reply[:80])
