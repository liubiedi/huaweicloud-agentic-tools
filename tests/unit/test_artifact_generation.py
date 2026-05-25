"""Unit tests for tfvars artifact generation (no cloud calls)."""
import re
import pytest
from agent.steps.step08_artifacts import _render_tfvars


def _norm(s: str) -> str:
    """Collapse alignment spaces around '=' so assertions ignore padding."""
    return re.sub(r'\s+=\s+', ' = ', s)


SAMPLE_LLD = {
    "_metadata": {"project_name": "TestLZ", "run_id": None},
    "D1": {
        "home_region": "cn-east-3",
        "org_name": "TestOrg",
        "log_archive_account_name": "lz-log-archive",
        "log_archive_account_email": "log@example.com",
        "audit_account_name": "lz-audit",
        "audit_account_email": "audit@example.com",
        "enable_identity_center": True,
        "identity_center_admin_email": "admin@example.com",
        "rgc_log_retention_days": 365,
        "enable_workloads_ou": True,
        "workloads_ou_name": "Workloads",
        "enable_sandbox_ou": True,
        "sandbox_ou_name": "Sandbox",
        "enable_infrastructure_ou": True,
        "infrastructure_ou_name": "Infrastructure",
        "security_ops_account_name": "lz-security-ops",
        "security_ops_account_email": "secops@example.com",
        "network_ops_account_name": "lz-network-ops",
        "network_ops_account_email": "netops@example.com",
        "ops_monitoring_account_name": "lz-ops-monitoring",
        "ops_monitoring_account_email": "opsmon@example.com",
    },
    "D2": {
        "enable_scim_sync": True,
        "session_duration_admin": "PT4H",
        "session_duration_developer": "PT8H",
        "platform_team_group_name": "lz-platform-admins",
        "password_min_length": 12,
        "password_max_age_days": 90,
        "password_reuse_prevention": 5,
        "mfa_enforce_console": True,
        "root_disable_console": True,
        "require_uppercase": True,
        "require_numbers": True,
        "require_special_chars": True,
    },
    "D3": {
        "er_instance_name": "lz-hub-er",
        "er_asn": 64512,
        "er_availability_zones": "cn-east-3a,cn-east-3b",
        "enable_default_propagation": True,
        "enable_cloud_firewall": True,
        "cfw_name": "lz-hub-cfw",
        "cfw_protect_eips": True,
        "cfw_log_retention_days": 7,
        "enable_nat_gateway": True,
        "nat_gateway_name": "lz-hub-nat",
        "nat_gateway_spec": "Small",
        "shared_bandwidth_name": "lz-shared-bandwidth",
        "shared_bandwidth_size_mbps": 100,
        "enable_vpn": False,
        "enable_direct_connect": False,
        "sandbox_vpc_name": "lz-sandbox-vpc",
        "sandbox_vpc_cidr": "10.0.0.0/16",
        "sandbox_subnet_cidr": "10.0.0.0/24",
        "sandbox_availability_zone": "cn-east-3a",
        "enable_vpc_flow_logs": True,
        "enable_waf": True,
        "waf_instance_count": 2,
        "enable_private_dns": True,
    },
    "D9": {
        "allowed_regions": "cn-east-3,cn-north-4",
        "enable_region_scp": True,
        "enable_root_protect_scp": True,
        "enable_require_mfa_scp": True,
        "enable_deny_internet_gw_scp": False,
        "scp_enforcement_mode": False,
        "enable_obs_vpcep": False,
        "enable_iam_vpcep": False,
        "enable_dns_vpcep": False,
        "obs_require_vpcep_only": False,
    },
}


def test_render_01_foundation_contains_required_fields():
    tfvars = _norm(_render_tfvars("01-foundation", "run-abc", SAMPLE_LLD))
    assert 'home_region = "cn-east-3"' in tfvars
    assert 'org_name = "TestOrg"' in tfvars
    assert 'log_archive_account_email = "log@example.com"' in tfvars
    assert 'audit_account_email = "audit@example.com"' in tfvars
    assert "enable_identity_center = true" in tfvars
    assert "password_min_length = 12" in tfvars


def test_render_02_network_contains_required_fields():
    tfvars = _norm(_render_tfvars("02-network", "run-abc", SAMPLE_LLD))
    assert 'sandbox_vpc_cidr = "10.0.0.0/16"' in tfvars
    assert 'sandbox_subnet_cidr = "10.0.0.0/24"' in tfvars
    assert 'er_availability_zones = ["cn-east-3a", "cn-east-3b"]' in tfvars


def test_render_05_perimeter_contains_scp_enforcement():
    tfvars = _norm(_render_tfvars("05-perimeter", "run-abc", SAMPLE_LLD))
    assert "scp_enforcement_mode = false" in tfvars
    assert 'allowed_regions = ["cn-east-3", "cn-north-4"]' in tfvars


def test_render_boolean_values():
    tfvars = _norm(_render_tfvars("01-foundation", "run-abc", SAMPLE_LLD))
    assert "enable_identity_center = true" in tfvars
    assert "mfa_enforce_console = true" in tfvars
    assert "root_disable_console = true" in tfvars


def test_render_run_id_comment():
    tfvars = _render_tfvars("01-foundation", "my-run-xyz", SAMPLE_LLD)
    assert "my-run-xyz" in tfvars


def test_render_unknown_env_returns_comment():
    tfvars = _render_tfvars("99-unknown", "run-abc", SAMPLE_LLD)
    assert "99-unknown" in tfvars
