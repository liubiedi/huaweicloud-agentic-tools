"""
Pre-flight check registry.

MVP checks: A1, A2, C1, D3
Full checks: B1-B3, C2-C4, D1-D2 added in later waves.

Each check is an async function: (client, lld_json) -> CheckResult
"""
from __future__ import annotations

import asyncio
import re
from typing import Any, Callable, Coroutine

import structlog

from agent.models.run_state import CheckResult
from agent.cloud.huaweicloud_client import HuaweiCloudClient

log = structlog.get_logger()

CheckFn = Callable[
    [HuaweiCloudClient, dict[str, Any]],
    Coroutine[Any, Any, CheckResult],
]

_CHECK_TIMEOUT_S = 30


# ── MVP checks ────────────────────────────────────────────────────────────────

async def check_a1_oidc(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    """A1: At least one IAM OIDC identity provider is configured."""
    try:
        providers = await client.get_oidc_providers()
        if providers:
            return CheckResult(
                id="A1", name="OIDC identity provider",
                status="PASS",
                details=f"{len(providers)} provider(s) found: {', '.join(p['id'] for p in providers)}",
            )
        return CheckResult(
            id="A1", name="OIDC identity provider",
            status="FAIL",
            details="No OIDC identity providers found in master account.",
            fix="Create an IAM identity provider for your IdP before enabling Identity Center.",
        )
    except Exception as exc:
        return CheckResult(
            id="A1", name="OIDC identity provider",
            status="FAIL",
            details=f"API error: {exc}",
            fix="Verify HWC_ACCESS_KEY / HWC_SECRET_KEY have IAM read permissions.",
        )


async def check_a2_agency(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    """A2: OrganizationAccountAccessAgency exists in the master account."""
    target = "OrganizationAccountAccessAgency"
    try:
        agencies = await client.list_agencies()
        found = [a for a in agencies if a.get("name") == target]
        if found:
            return CheckResult(
                id="A2", name="OrganizationAccountAccessAgency",
                status="PASS",
                details=f"Agency found (ID: {found[0].get('id', '?')})",
            )
        return CheckResult(
            id="A2", name="OrganizationAccountAccessAgency",
            status="FAIL",
            details=f"Agency '{target}' not found.",
            fix=(
                "Create the agency with 'Organizations Admin' trust policy. "
                "See docs/manually-managed.md for setup instructions."
            ),
        )
    except Exception as exc:
        return CheckResult(
            id="A2", name="OrganizationAccountAccessAgency",
            status="FAIL",
            details=f"API error: {exc}",
            fix="Verify HWC_ACCESS_KEY has IAM Agency read permission.",
        )


async def check_c1_vpc_quota(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    """C1: VPC quota is not exhausted (need at least 1 free slot)."""
    try:
        quota = await client.get_vpc_quota()
        resources = quota.get("resources", [])
        vpc_resource = next((r for r in resources if r.get("type") == "vpc"), None)
        if not vpc_resource:
            return CheckResult(
                id="C1", name="VPC quota", status="SKIP",
                details="VPC quota resource not found in API response.",
            )
        limit = vpc_resource.get("quota", 0)
        used = vpc_resource.get("used", 0)
        free = limit - used
        if free >= 1:
            return CheckResult(
                id="C1", name="VPC quota", status="PASS",
                details=f"VPC quota: {used}/{limit} used, {free} free.",
            )
        return CheckResult(
            id="C1", name="VPC quota", status="FAIL",
            details=f"VPC quota exhausted: {used}/{limit}.",
            fix="Delete unused VPCs or raise quota via Huawei Cloud console → Quotas.",
        )
    except Exception as exc:
        return CheckResult(
            id="C1", name="VPC quota", status="FAIL",
            details=f"API error: {exc}",
            fix="Verify HWC_ACCESS_KEY has VPC read permission.",
        )


async def check_d3_account_emails(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    """D3: Log-archive and audit emails in LLD are not already used by existing accounts."""
    log_email = lld_json.get("D1", {}).get("log_archive_account_email", "")
    audit_email = lld_json.get("D1", {}).get("audit_account_email", "")
    required = {e for e in [log_email, audit_email] if e}
    if not required:
        return CheckResult(
            id="D3", name="Account emails not reused", status="SKIP",
            details="Log-archive / audit emails not set in LLD yet.",
        )
    try:
        accounts = await client.list_accounts()
        existing_emails = {a.get("email", "").lower() for a in accounts}
        conflicts = {e for e in required if e.lower() in existing_emails}
        if not conflicts:
            return CheckResult(
                id="D3", name="Account emails not reused", status="PASS",
                details=f"Emails {required} are not used by existing accounts.",
            )
        return CheckResult(
            id="D3", name="Account emails not reused", status="FAIL",
            details=f"Emails already in use by existing accounts: {conflicts}",
            fix=(
                "Each Huawei Cloud account requires a unique email. "
                "Update the LLD with different email addresses."
            ),
        )
    except Exception as exc:
        return CheckResult(
            id="D3", name="Account emails not reused", status="FAIL",
            details=f"API error: {exc}",
            fix="Verify HWC_ACCESS_KEY has Organizations read permission.",
        )


# ── Full-spec checks (Phase 2) — stubs ───────────────────────────────────────

async def check_b1_er_quota(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    return CheckResult(id="B1", name="Enterprise Router quota", status="SKIP",
                       details="Not yet implemented (Phase 2).")


async def check_b2_cfw_enabled(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    return CheckResult(id="B2", name="Cloud Firewall service enabled", status="SKIP",
                       details="Not yet implemented (Phase 2).")


async def check_b3_eip_quota(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    return CheckResult(id="B3", name="EIP quota", status="SKIP",
                       details="Not yet implemented (Phase 2).")


async def check_c2_kms_quota(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    return CheckResult(id="C2", name="KMS key quota", status="SKIP",
                       details="Not yet implemented (Phase 2).")


async def check_c3_obs_bucket_name(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    return CheckResult(id="C3", name="OBS bucket name available", status="SKIP",
                       details="Not yet implemented (Phase 2).")


async def check_c4_hss_quota(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    return CheckResult(id="C4", name="HSS quota", status="SKIP",
                       details="Not yet implemented (Phase 2).")


async def check_d1_org_enabled(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    return CheckResult(id="D1", name="Organizations service enabled", status="SKIP",
                       details="Not yet implemented (Phase 2).")


async def check_d2_rgc_status(client: HuaweiCloudClient, lld_json: dict) -> CheckResult:
    return CheckResult(id="D2", name="RGC landing zone status", status="SKIP",
                       details="Not yet implemented (Phase 2).")


# ── Registry ──────────────────────────────────────────────────────────────────

# MVP: run A1, A2, C1, D3. Extend list for full PRD.
MVP_CHECKS: list[CheckFn] = [check_a1_oidc, check_a2_agency, check_c1_vpc_quota, check_d3_account_emails]
FULL_CHECKS: list[CheckFn] = [
    check_a1_oidc, check_a2_agency,
    check_b1_er_quota, check_b2_cfw_enabled, check_b3_eip_quota,
    check_c1_vpc_quota, check_c2_kms_quota, check_c3_obs_bucket_name, check_c4_hss_quota,
    check_d1_org_enabled, check_d2_rgc_status, check_d3_account_emails,
]


async def run_checks(
    client: HuaweiCloudClient,
    lld_json: dict,
    check_ids: list[str] | None = None,
    use_full: bool = False,
) -> list[CheckResult]:
    """
    Run all MVP (or full) checks in parallel.
    If check_ids is given, only those checks are run (for RECHECK).
    """
    registry = FULL_CHECKS if use_full else MVP_CHECKS
    if check_ids is not None:
        registry = [f for f in registry if f.__name__.split("_")[1].upper() in {c.upper() for c in check_ids}]

    async def _run_one(fn: CheckFn) -> CheckResult:
        try:
            return await asyncio.wait_for(fn(client, lld_json), timeout=_CHECK_TIMEOUT_S)
        except asyncio.TimeoutError:
            check_id = fn.__name__.split("_")[1].upper()
            return CheckResult(id=check_id, name=fn.__name__, status="FAIL",
                               details=f"Check timed out after {_CHECK_TIMEOUT_S}s.",
                               fix="Check network connectivity to Huawei Cloud APIs.")

    results = await asyncio.gather(*[_run_one(fn) for fn in registry])
    return list(results)
