"""
Gap-fill step: detect required fields that are still empty in the selected
domains, email the engineer, wait for reply, merge values back in.
Repeats up to MAX_ROUNDS times; escalates if gaps remain.
"""
from __future__ import annotations

import asyncio
import re
from typing import TYPE_CHECKING, Any

import jsonschema
import structlog

from agent.models.domain_map import DOMAIN_MODULE_MAP

if TYPE_CHECKING:
    from agent.models.run_state import RunState
    from agent.orchestrator import StepContext

log = structlog.get_logger()

MAX_ROUNDS = 2
REPLY_TIMEOUT_S = 7 * 24 * 3600


def _required_fields_for_domain(schema: dict, domain_id: str) -> list[str]:
    """Extract 'required' field names for a given domain from lld_schema."""
    domain_schema = schema.get("properties", {}).get(domain_id, {})
    return domain_schema.get("required", [])


def detect_gaps(lld_json: dict[str, Any], deploy_domains: list[str], schema: dict) -> dict[str, list[str]]:
    """
    Return {domain_id: [missing_field, ...]} for all required fields that are
    None/empty in the selected domains.
    """
    gaps: dict[str, list[str]] = {}
    for domain_id in deploy_domains:
        required = _required_fields_for_domain(schema, domain_id)
        domain_data = lld_json.get(domain_id, {})
        missing = [
            f for f in required
            if domain_data.get(f) is None or domain_data.get(f) == ""
        ]
        if missing:
            gaps[domain_id] = missing
    return gaps


def _parse_reply(reply_body: str) -> dict[str, str]:
    """
    Parse engineer's gap-fill reply.

    Expects lines like:
        D1.log_archive_account_email = lz-log@example.com
    or (short form):
        log_archive_account_email = lz-log@example.com

    Returns {"D1.log_archive_account_email": "lz-log@example.com", ...}
    """
    result: dict[str, str] = {}
    for line in reply_body.splitlines():
        line = line.strip()
        if "=" not in line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        result[key.strip()] = value.strip()
    return result


def _apply_reply(lld_json: dict[str, Any], parsed: dict[str, str]) -> int:
    """Merge reply values into lld_json. Returns count of fields updated."""
    updated = 0
    for key, value in parsed.items():
        if "." in key:
            domain, field = key.split(".", 1)
        else:
            # Try to find the field in any domain
            field = key
            domain = None
            for d_id, d_data in lld_json.items():
                if isinstance(d_data, dict) and field in d_data:
                    domain = d_id
                    break

        if domain and domain in lld_json and isinstance(lld_json[domain], dict):
            # Normalise boolean strings
            lv = value.lower()
            if lv in ("true", "yes"):
                value = True
            elif lv in ("false", "no"):
                value = False
            lld_json[domain][field] = value
            updated += 1
    return updated


async def execute(state: "RunState", ctx: "StepContext") -> None:
    import json as _json, pathlib as _pl
    schema_path = _pl.Path(__file__).parent.parent / "models" / "lld_schema.json"
    schema = _json.loads(schema_path.read_text())

    for round_num in range(1, MAX_ROUNDS + 1):
        gaps = detect_gaps(state.lld_json, state.deploy_domains, schema)
        if not gaps:
            log.info("gap_fill_no_gaps", round=round_num)
            return

        state.gap_rounds = round_num
        log.info("gap_fill_sending", round=round_num, gap_count=sum(len(v) for v in gaps.values()))

        body = ctx.email.templates.gap_fill_email(
            run_id=state.run_id,
            requester_name=state.requester_name or "Engineer",
            gaps=gaps,
            round_num=round_num,
            max_rounds=MAX_ROUNDS,
        )

        await ctx.gmail.send(
            to=state.requester_email,
            subject=f"[LZ-{state.run_id}] LLD gap-fill required (round {round_num}/{MAX_ROUNDS})",
            body=body,
        )

        try:
            reply = await asyncio.wait_for(ctx.reply_queue.get(), timeout=REPLY_TIMEOUT_S)
        except asyncio.TimeoutError:
            raise RuntimeError(f"Gap-fill timeout: no reply within 7 days (round {round_num})")

        parsed = _parse_reply(reply)
        updated = _apply_reply(state.lld_json, parsed)
        log.info("gap_fill_reply_applied", updated=updated, round=round_num)

    # Final check
    gaps = detect_gaps(state.lld_json, state.deploy_domains, schema)
    if gaps:
        # Escalate — still has gaps after max rounds
        flat = []
        for domain_id, fields in gaps.items():
            for f in fields:
                flat.append(f"{domain_id}.{f}")
        raise RuntimeError(
            f"LLD still has {len(flat)} required fields empty after {MAX_ROUNDS} rounds: "
            + ", ".join(flat[:10])
        )
