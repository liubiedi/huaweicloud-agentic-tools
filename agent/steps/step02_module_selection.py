"""
Module selection step: email the engineer a list of filled domains and ask
which ones to deploy. Parses the reply and stores the selection in state.
If the LLD already contains a deploy_domains hint (from Metadata or JSON),
that is used directly without sending an email.
"""
from __future__ import annotations

import asyncio
import re
from typing import TYPE_CHECKING

import structlog

from agent.models.domain_map import (
    DOMAIN_MODULE_MAP,
    DOMAIN_DEPENDENCIES,
    domains_to_envs,
    resolve_dependencies,
)
from agent.steps.step01_lld_reader import detect_filled_domains

if TYPE_CHECKING:
    from agent.models.run_state import RunState
    from agent.orchestrator import StepContext

log = structlog.get_logger()

REPLY_TIMEOUT_S = 7 * 24 * 3600  # 7 days


def _parse_selection(reply_body: str, available: list[str]) -> list[str]:
    """
    Extract domain IDs from a free-text email reply.

    Accepts: "all", "D1, D2, D3", "d1 d2 d9", "D1-D3,D7" etc.
    Returns a validated, sorted list of domain IDs.
    """
    normalized = reply_body.upper()

    if re.search(r"\bALL\b", normalized):
        return list(available)

    found = re.findall(r"\bD[1-9]\b", normalized)
    valid = [d for d in dict.fromkeys(found) if d in available]
    return sorted(valid, key=lambda d: int(d[1:]))


async def execute(state: "RunState", ctx: "StepContext") -> None:
    filled = detect_filled_domains(state.lld_json)

    # Fast path: deploy_domains already set (e.g. JSON input with pre-selection)
    if state.deploy_domains:
        resolved = resolve_dependencies(state.deploy_domains)
        state.deploy_domains = resolved
        state.deploy_envs = domains_to_envs(resolved)
        log.info("module_selection_preset", domains=resolved, envs=state.deploy_envs)
        return

    # Build the selection email
    domain_lines = []
    for d in sorted(DOMAIN_MODULE_MAP.keys(), key=lambda x: int(x[1:])):
        target = DOMAIN_MODULE_MAP[d]
        deps = DOMAIN_DEPENDENCIES.get(d, [])
        status = "READY" if d in filled else "EMPTY — no values detected"
        dep_note = f"  (requires {', '.join(deps)})" if deps else ""
        domain_lines.append(f"  {d}  {target.name}{dep_note}\n       Status: {status}")

    body = ctx.email.templates.module_selection_email(
        run_id=state.run_id,
        requester_name=state.requester_name or "Engineer",
        domain_lines=domain_lines,
        filled_domains=filled,
    )

    await ctx.gmail.send(
        to=state.requester_email,
        subject=f"[LZ-{state.run_id}] Module selection required",
        body=body,
    )
    log.info("module_selection_email_sent", to=state.requester_email)

    # Wait for reply
    try:
        reply = await asyncio.wait_for(
            ctx.reply_queue.get(),
            timeout=REPLY_TIMEOUT_S,
        )
    except asyncio.TimeoutError:
        raise RuntimeError(
            f"No module selection received within 7 days for run {state.run_id}"
        )

    selected = _parse_selection(reply, list(DOMAIN_MODULE_MAP.keys()))
    if not selected:
        # Default to all filled domains if reply is unparseable
        selected = filled
        log.warning("module_selection_parse_failed_using_filled", reply=reply[:200])

    resolved = resolve_dependencies(selected)
    state.deploy_domains = resolved
    state.deploy_envs = domains_to_envs(resolved)

    log.info(
        "module_selection_complete",
        requested=selected,
        resolved=resolved,
        envs=state.deploy_envs,
    )
