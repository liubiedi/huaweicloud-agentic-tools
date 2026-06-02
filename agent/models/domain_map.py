from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class DeployTarget:
    domain_id: str
    name: str
    # Terraform env directory (under envs/)
    env: str
    # Module names inside that env (as terraform module addresses)
    modules: list[str]


# Maps each LLD domain sheet to the Terraform env + modules it provisions.
# Multiple domains can map to the same env; the unique sorted env list is what
# gets applied.
DOMAIN_MODULE_MAP: dict[str, DeployTarget] = {
    "D1": DeployTarget("D1", "Org & Accounts (RGC bootstrap, OUs, member accounts)", "01-foundation", ["org_foundation"]),
    "D2": DeployTarget("D2", "Identity Center + IAM Baseline (SSO, password/MFA policy)", "01-foundation", ["identity_center", "iam_baseline"]),
    "D3": DeployTarget("D3", "Network (ER, CFW, NAT, spoke VPC, WAF, DNS)", "02-network", ["network_hub", "network_spoke", "public_services"]),
    "D4": DeployTarget("D4", "Shared Resources (KMS, OBS, SFS Turbo, Images)", "03-security-audit", ["shared_resources"]),
    "D5": DeployTarget("D5", "Security Center (SecMaster, HSS, DBSS, CSMS)", "03-security-audit", ["security_center"]),
    "D6": DeployTarget("D6", "Audit & Logging (CTS, LTS, OBS archive, Config/RMS)", "03-security-audit", ["audit_logging", "compliance_config"]),
    "D7": DeployTarget("D7", "Ops & Monitoring (Cloud Eye, AOM, SMN, FunctionGraph)", "04-ops-finance", ["ops_monitoring"]),
    "D8": DeployTarget("D8", "Finance Governance (tag policies, budget alerts)", "04-ops-finance", ["finance_governance"]),
    "D9": DeployTarget("D9", "Data Perimeter (SCPs, VPC Endpoints)", "05-perimeter", ["data_perimeter"]),
}

# Domains that must be deployed before the key domain (direct prerequisites only).
DOMAIN_DEPENDENCIES: dict[str, list[str]] = {
    "D2": ["D1"],
    "D3": ["D1"],
    "D4": ["D1", "D3"],
    "D5": ["D1", "D4"],
    "D6": ["D1"],
    "D7": ["D1"],
    "D8": ["D1"],
    "D9": ["D1", "D3"],
}

# Ordered env deployment sequence (must match CLAUDE.md constraint: 00→01→02→03→04→05)
ENV_ORDER = ["01-foundation", "02-network", "03-security-audit", "04-ops-finance", "05-perimeter"]


def domains_to_envs(domains: list[str]) -> list[str]:
    """Return ordered, deduplicated env list for the given domain selection."""
    envs = {DOMAIN_MODULE_MAP[d].env for d in domains if d in DOMAIN_MODULE_MAP}
    return [e for e in ENV_ORDER if e in envs]


def resolve_dependencies(selected: list[str]) -> list[str]:
    """Expand selected domains to include all transitive prerequisites."""
    resolved: set[str] = set(selected)
    changed = True
    while changed:
        changed = False
        for d in list(resolved):
            for dep in DOMAIN_DEPENDENCIES.get(d, []):
                if dep not in resolved:
                    resolved.add(dep)
                    changed = True
    # Preserve domain order D1→D9
    return [d for d in sorted(DOMAIN_MODULE_MAP.keys()) if d in resolved]
