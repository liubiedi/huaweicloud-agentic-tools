"""Unit tests for pre-flight checks with mocked Huawei Cloud API responses."""
import pytest
from unittest.mock import AsyncMock, MagicMock
from agent.cloud.preflight_checks import (
    check_a1_oidc, check_a2_agency, check_c1_vpc_quota, check_d3_account_emails,
)
from agent.models.run_state import CheckResult

LLD_SAMPLE = {
    "D1": {
        "log_archive_account_email": "log@example.com",
        "audit_account_email": "audit@example.com",
    }
}


@pytest.fixture
def mock_client():
    client = AsyncMock()
    return client


@pytest.mark.asyncio
async def test_a1_oidc_pass(mock_client):
    mock_client.get_oidc_providers.return_value = [{"id": "my-idp"}]
    result = await check_a1_oidc(mock_client, LLD_SAMPLE)
    assert result.status == "PASS"
    assert result.id == "A1"


@pytest.mark.asyncio
async def test_a1_oidc_fail_no_providers(mock_client):
    mock_client.get_oidc_providers.return_value = []
    result = await check_a1_oidc(mock_client, LLD_SAMPLE)
    assert result.status == "FAIL"
    assert result.fix


@pytest.mark.asyncio
async def test_a1_oidc_fail_on_api_error(mock_client):
    mock_client.get_oidc_providers.side_effect = Exception("Connection refused")
    result = await check_a1_oidc(mock_client, LLD_SAMPLE)
    assert result.status == "FAIL"
    assert "Connection refused" in result.details


@pytest.mark.asyncio
async def test_a2_agency_pass(mock_client):
    mock_client.list_agencies.return_value = [
        {"name": "OrganizationAccountAccessAgency", "id": "abc123"}
    ]
    result = await check_a2_agency(mock_client, LLD_SAMPLE)
    assert result.status == "PASS"


@pytest.mark.asyncio
async def test_a2_agency_fail_not_found(mock_client):
    mock_client.list_agencies.return_value = [{"name": "SomeOtherAgency"}]
    result = await check_a2_agency(mock_client, LLD_SAMPLE)
    assert result.status == "FAIL"
    # fix should instruct the user how to resolve the missing agency
    assert result.fix and len(result.fix) > 10


@pytest.mark.asyncio
async def test_c1_vpc_quota_pass(mock_client):
    mock_client.get_vpc_quota.return_value = {
        "resources": [{"type": "vpc", "quota": 10, "used": 3}]
    }
    result = await check_c1_vpc_quota(mock_client, LLD_SAMPLE)
    assert result.status == "PASS"
    assert "7 free" in result.details


@pytest.mark.asyncio
async def test_c1_vpc_quota_fail_exhausted(mock_client):
    mock_client.get_vpc_quota.return_value = {
        "resources": [{"type": "vpc", "quota": 5, "used": 5}]
    }
    result = await check_c1_vpc_quota(mock_client, LLD_SAMPLE)
    assert result.status == "FAIL"
    assert result.fix


@pytest.mark.asyncio
async def test_d3_account_emails_pass(mock_client):
    mock_client.list_accounts.return_value = [
        {"email": "other@example.com"}
    ]
    result = await check_d3_account_emails(mock_client, LLD_SAMPLE)
    assert result.status == "PASS"


@pytest.mark.asyncio
async def test_d3_account_emails_fail_conflict(mock_client):
    mock_client.list_accounts.return_value = [
        {"email": "log@example.com"},  # conflicts with LLD
    ]
    result = await check_d3_account_emails(mock_client, LLD_SAMPLE)
    assert result.status == "FAIL"
    assert "log@example.com" in result.details


@pytest.mark.asyncio
async def test_d3_skip_when_no_emails():
    lld_empty = {"D1": {}}
    client = AsyncMock()
    result = await check_d3_account_emails(client, lld_empty)
    assert result.status == "SKIP"
    client.list_accounts.assert_not_called()
