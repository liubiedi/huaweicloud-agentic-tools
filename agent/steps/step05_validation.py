"""
Validation step: run JSON Schema validation on lld_json for selected domains.
Raises on any schema violation so the orchestrator transitions to FAILED.
"""
from __future__ import annotations

import json
import pathlib
from typing import TYPE_CHECKING

import jsonschema
import structlog

if TYPE_CHECKING:
    from agent.models.run_state import RunState
    from agent.orchestrator import StepContext

log = structlog.get_logger()

_SCHEMA_PATH = pathlib.Path(__file__).parent.parent / "models" / "lld_schema.json"


def _load_schema() -> dict:
    return json.loads(_SCHEMA_PATH.read_text())


def validate_lld(lld_json: dict, deploy_domains: list[str]) -> list[str]:
    """
    Validate only the selected domains against the JSON Schema.
    Returns a list of human-readable error strings (empty = valid).
    """
    schema = _load_schema()
    errors: list[str] = []

    for domain_id in deploy_domains:
        domain_schema = schema.get("properties", {}).get(domain_id)
        if not domain_schema:
            continue
        domain_data = lld_json.get(domain_id, {})
        # Build a sub-schema that validates just this domain's data
        sub_schema = {
            **domain_schema,
            "$schema": "https://json-schema.org/draft/2020-12/schema",
        }
        try:
            jsonschema.validate(instance=domain_data, schema=sub_schema)
        except jsonschema.ValidationError as exc:
            field_path = ".".join(str(p) for p in exc.absolute_path) or "(root)"
            errors.append(f"{domain_id}.{field_path}: {exc.message}")
        except jsonschema.SchemaError as exc:
            errors.append(f"Schema error in {domain_id}: {exc.message}")

    return errors


async def execute(state: "RunState", ctx: "StepContext") -> None:
    log.info("step05_validation_start", domains=state.deploy_domains)
    errors = validate_lld(state.lld_json, state.deploy_domains)

    if errors:
        detail = "\n".join(f"  • {e}" for e in errors)
        log.error("lld_validation_failed", error_count=len(errors))
        raise ValueError(
            f"LLD validation failed with {len(errors)} error(s):\n{detail}"
        )

    log.info("lld_validation_passed", domains=state.deploy_domains)
