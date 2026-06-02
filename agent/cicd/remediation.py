"""
Per-category remediation actions executed by the agent when a CI/CD step fails.
Returns True if remediation was applied (caller should retry), False if escalation needed.
"""
from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

import structlog

from agent.cicd.error_classifier import ErrorCategory, Classification, classify
from agent.models.run_state import ErrorEvent

if TYPE_CHECKING:
    from agent.models.run_state import RunState, CicdEvent
    from agent.orchestrator import StepContext

log = structlog.get_logger()


async def execute_remediation(
    event: "CicdEvent",
    state: "RunState",
    ctx: "StepContext",
    classification: Classification,
) -> bool:
    """
    Apply remediation for the given classification.
    Returns True if the runner should retry the failed step, False if escalation sent.
    """
    scope = f"{event.module or 'unknown'}"
    attempts = state.increment_attempt(scope)
    policy = classification.policy

    if attempts > policy.max_retries:
        await _escalate(event, state, ctx, classification, attempts)
        return False

    category = classification.category
    log.info("remediating", category=category, attempt=attempts, max=policy.max_retries)

    if category == ErrorCategory.QUOTA_EXCEEDED:
        wait = policy.wait_s * (2 ** (attempts - 1) if policy.backoff else 1)
        log.info("quota_wait", seconds=wait)
        await asyncio.sleep(wait)
        return True

    if category == ErrorCategory.DEPENDENCY_NOT_READY:
        log.info("dependency_wait", seconds=policy.wait_s)
        await asyncio.sleep(policy.wait_s)
        return True

    if category == ErrorCategory.SERVICE_UNAVAILABLE:
        wait = policy.wait_s * (2 ** (attempts - 1))
        log.info("service_unavailable_wait", seconds=wait)
        await asyncio.sleep(min(wait, 600))
        return True

    if category == ErrorCategory.RESOURCE_EXISTS and policy.action == "import":
        log.warning("resource_exists_needs_import", module=event.module, resource=event.resource)
        await _escalate(event, state, ctx, classification, attempts,
                        extra="Consider running 'terraform import' for the conflicting resource.")
        return False

    if category == ErrorCategory.INVALID_PARAM and policy.action == "regen":
        log.warning("invalid_param_regen_needed", module=event.module)
        await _escalate(event, state, ctx, classification, attempts,
                        extra="The generated tfvars contain an invalid value. Review the LLD fields for this module.")
        return False

    if category == ErrorCategory.ACCOUNT_NOT_FOUND:
        wait = policy.wait_s
        log.info("account_propagation_wait", seconds=wait)
        await asyncio.sleep(wait)
        return True

    # Default: escalate
    await _escalate(event, state, ctx, classification, attempts)
    return False


async def _escalate(
    event: "CicdEvent",
    state: "RunState",
    ctx: "StepContext",
    classification: Classification,
    attempts: int,
    extra: str = "",
) -> None:
    state.errors.append(ErrorEvent(
        step=state.step.value,
        module=event.module,
        error_code=event.error_code,
        error_message=event.error_message or "",
        category=classification.category.value,
        remediated=False,
    ))

    details = (
        f"Module: {event.module}\n"
        f"Error code: {event.error_code or 'n/a'}\n"
        f"Message: {event.error_message}\n"
        f"Category: {classification.category.value} (confidence={classification.confidence:.0%})\n"
        f"Attempts: {attempts}"
    )
    if extra:
        details += f"\n{extra}"

    body = ctx.email.templates.escalation_email(
        run_id=state.run_id,
        requester_name=state.requester_name or "Engineer",
        title=f"Apply failed: module {event.module} — {classification.category.value}",
        details=details,
        suggested_action=(
            "Fix the issue described above, then reply RESUME to continue from this module "
            "or ABORT to stop the deployment."
        ),
    )
    await ctx.gmail.send(
        to=state.requester_email,
        subject=f"[LZ-{state.run_id}] Apply escalation: {event.module}",
        body=body,
    )
    log.info("escalation_email_sent", module=event.module, category=classification.category)
