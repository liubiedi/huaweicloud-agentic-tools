from __future__ import annotations

import secrets
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, Field


class Step(str, Enum):
    LLD_READ = "lld_read"
    MODULE_SELECTION = "module_selection"
    GAP_FILL = "gap_fill"
    VALIDATION = "validation"
    CAF_CHECK = "caf_check"
    PREFLIGHT = "preflight"
    ARTIFACTS = "artifacts"
    PLAN_GATE = "plan_gate"
    APPROVAL = "approval"
    CICD_EXECUTE = "cicd_execute"
    POST_APPLY = "post_apply"
    DONE = "done"
    FAILED = "failed"


TERMINAL_STEPS = {Step.DONE, Step.FAILED}

STEP_ORDER = [
    Step.LLD_READ,
    Step.MODULE_SELECTION,
    Step.GAP_FILL,
    Step.VALIDATION,
    Step.CAF_CHECK,
    Step.PREFLIGHT,
    Step.ARTIFACTS,
    Step.PLAN_GATE,
    Step.APPROVAL,
    Step.CICD_EXECUTE,
    Step.POST_APPLY,
    Step.DONE,
]


class CheckResult(BaseModel):
    id: str
    name: str
    status: Literal["PASS", "FAIL", "SKIP"]
    details: str = ""
    fix: str = ""


class CicdEventType(str, Enum):
    STEP_START = "STEP_START"
    STEP_SUCCESS = "STEP_SUCCESS"
    STEP_ERROR = "STEP_ERROR"


class CicdEvent(BaseModel):
    event_type: CicdEventType
    run_id: str
    module: str | None = None
    resource: str | None = None
    error_code: str | None = None
    error_message: str | None = None
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ErrorEvent(BaseModel):
    step: str
    module: str | None
    error_code: str | None
    error_message: str
    category: str | None
    remediated: bool
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class RunState(BaseModel):
    run_id: str
    step: Step = Step.LLD_READ
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    lld_source_key: str = ""
    # Raw parsed LLD keyed by domain: {"D1": {field: value, ...}, "D2": {...}, ...}
    lld_json: dict[str, Any] = Field(default_factory=dict)
    # Metadata fields from the Metadata sheet
    lld_metadata: dict[str, Any] = Field(default_factory=dict)

    # User-selected domains (e.g. ["D1","D2","D3"]); populated after MODULE_SELECTION step
    deploy_domains: list[str] = Field(default_factory=list)
    # Derived envs from deploy_domains (e.g. ["01-foundation","02-network"])
    deploy_envs: list[str] = Field(default_factory=list)

    gap_rounds: int = 0
    recheck_rounds: int = 0
    gate_attempts: int = 0

    preflight_results: list[CheckResult] = Field(default_factory=list)
    preflight_failed_ids: list[str] = Field(default_factory=list)

    current_env: str | None = None
    current_module: str | None = None
    envs_applied: list[str] = Field(default_factory=list)
    attempt_counts: dict[str, int] = Field(default_factory=dict)

    hmac_token: str = Field(default_factory=lambda: secrets.token_hex(32))
    artifacts_obs_prefix: str = ""

    caf_ack: bool = False
    plan_summary: str = ""
    approval_email_id: str | None = None

    errors: list[ErrorEvent] = Field(default_factory=list)
    requester_email: str = ""
    requester_name: str = ""

    def touch(self) -> None:
        self.updated_at = datetime.now(timezone.utc)

    def next_step(self) -> Step:
        idx = STEP_ORDER.index(self.step)
        return STEP_ORDER[idx + 1] if idx + 1 < len(STEP_ORDER) else Step.DONE

    def attempt_key(self, scope: str) -> str:
        return f"{self.step.value}:{scope}"

    def increment_attempt(self, scope: str) -> int:
        key = self.attempt_key(scope)
        self.attempt_counts[key] = self.attempt_counts.get(key, 0) + 1
        return self.attempt_counts[key]

    def get_attempt(self, scope: str) -> int:
        return self.attempt_counts.get(self.attempt_key(scope), 0)
