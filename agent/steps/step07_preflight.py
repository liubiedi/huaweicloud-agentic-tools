"""
Pre-flight checks step.
Runs checks, emails a report, handles RECHECK / SKIP / ABORT replies.
"""
from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

import structlog

from agent.cloud.preflight_checks import run_checks
from agent.models.run_state import CheckResult

if TYPE_CHECKING:
    from agent.models.run_state import RunState
    from agent.orchestrator import StepContext

log = structlog.get_logger()

MAX_RECHECK = 5
REPLY_TIMEOUT_S = 7 * 24 * 3600


async def execute(state: "RunState", ctx: "StepContext") -> None:
    client = ctx.hwc
    results: list[CheckResult] = []

    for recheck_round in range(1, MAX_RECHECK + 2):
        state.recheck_rounds = recheck_round

        if recheck_round == 1:
            # First run: all MVP checks
            results = await run_checks(client, state.lld_json)
        else:
            # Re-run only previously failed checks
            results_map = {r.id: r for r in results}
            rerun = await run_checks(client, state.lld_json, check_ids=state.preflight_failed_ids)
            for r in rerun:
                results_map[r.id] = r
            results = list(results_map.values())

        failed = [r for r in results if r.status == "FAIL"]
        state.preflight_results = results
        state.preflight_failed_ids = [r.id for r in failed]

        passed = sum(1 for r in results if r.status == "PASS")
        log.info("preflight_round_complete",
                 round=recheck_round, passed=passed, failed=len(failed))

        if not failed:
            log.info("preflight_all_passed")
            return

        if recheck_round > MAX_RECHECK:
            # Exceeded max re-checks — escalate
            detail_lines = "\n".join(
                f"  [{r.id}] {r.name}: {r.details}\n  Fix: {r.fix}"
                for r in failed
            )
            body = ctx.email.templates.escalation_email(
                run_id=state.run_id,
                requester_name=state.requester_name or "Engineer",
                title=f"Pre-flight still failing after {MAX_RECHECK} RECHECK rounds",
                details=detail_lines,
                suggested_action=(
                    "Resolve the issues described, then reply RESUME to continue "
                    "or ABORT to cancel."
                ),
            )
            await ctx.gmail.send(
                to=state.requester_email,
                subject=f"[LZ-{state.run_id}] Pre-flight escalation",
                body=body,
            )
            # Wait for RESUME or ABORT
            reply = await asyncio.wait_for(ctx.reply_queue.get(), timeout=REPLY_TIMEOUT_S)
            if "ABORT" in reply.upper():
                raise RuntimeError("Deployment aborted by engineer during pre-flight escalation.")
            # RESUME → proceed despite failures
            log.info("preflight_escalation_resumed")
            return

        # Send RECHECK / SKIP / ABORT prompt
        body = ctx.email.templates.preflight_report_email(
            run_id=state.run_id,
            requester_name=state.requester_name or "Engineer",
            results=[r.model_dump() for r in results],
            recheck_round=recheck_round,
            max_recheck=MAX_RECHECK,
            failed_ids=state.preflight_failed_ids,
        )
        await ctx.gmail.send(
            to=state.requester_email,
            subject=f"[LZ-{state.run_id}] Pre-flight checks — round {recheck_round}/{MAX_RECHECK}",
            body=body,
        )

        try:
            reply = await asyncio.wait_for(ctx.reply_queue.get(), timeout=REPLY_TIMEOUT_S)
        except asyncio.TimeoutError:
            raise RuntimeError(f"Pre-flight RECHECK timeout (round {recheck_round})")

        upper = reply.upper()
        if "ABORT" in upper:
            raise RuntimeError("Deployment aborted by engineer at pre-flight stage.")
        if "SKIP" in upper:
            log.warning("preflight_failed_skipped_by_engineer", failed=state.preflight_failed_ids)
            return
        # RECHECK → loop
        log.info("preflight_recheck_requested", round=recheck_round)
