"""
Post-apply verification and completion email.
Queries live Huawei Cloud APIs to confirm key resources were created.
"""
from __future__ import annotations

import time
from datetime import datetime, timezone
from typing import TYPE_CHECKING

import structlog

if TYPE_CHECKING:
    from agent.models.run_state import RunState
    from agent.orchestrator import StepContext

log = structlog.get_logger()


async def execute(state: "RunState", ctx: "StepContext") -> None:
    client = ctx.hwc
    checks: list[str] = []
    partial = bool(state.errors)

    # Verify organization was created (if D1 was deployed)
    if "D1" in state.deploy_domains:
        org = await client.get_organization()
        if org:
            checks.append(f"✓ Organization '{org.get('alias', '?')}' confirmed via Organizations API")
        else:
            checks.append("✗ Organization not found via Organizations API — check RGC apply logs")
            partial = True

    # Verify landing zone status
    if "D1" in state.deploy_domains:
        lz = await client.get_rgc_landing_zone()
        if lz:
            lz_status = lz.get("status", "?")
            checks.append(f"✓ RGC Landing Zone status: {lz_status}")
        else:
            checks.append("⚠ RGC Landing Zone endpoint not reachable (may take a few minutes to propagate)")

    # Summarise errors
    if state.errors:
        checks.append(f"\n⚠ {len(state.errors)} error event(s) occurred during apply (auto-remediated or escalated):")
        for err in state.errors[-5:]:
            checks.append(f"  • [{err.module}] {err.error_code}: {err.error_message[:80]}")

    post_apply_summary = "\n".join(checks) if checks else "No verifications configured for selected domains."

    duration = (datetime.now(timezone.utc) - state.created_at).total_seconds() / 60.0

    body = ctx.email.templates.completion_email(
        run_id=state.run_id,
        requester_name=state.requester_name or "Engineer",
        deployed_envs=state.envs_applied,
        post_apply_summary=post_apply_summary,
        duration_minutes=duration,
        partial=partial,
    )

    await ctx.gmail.send(
        to=state.requester_email,
        subject=f"[LZ-{state.run_id}] Landing Zone deployment {'PARTIAL' if partial else 'SUCCESS'}",
        body=body,
    )
    log.info("completion_email_sent", partial=partial, duration_minutes=round(duration, 1))
