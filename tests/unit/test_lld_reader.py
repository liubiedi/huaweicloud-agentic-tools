"""Unit tests for LLD Excel parser."""
import pytest
from agent.steps.step01_lld_reader import parse_excel, detect_filled_domains, _coerce


def test_coerce_boolean_true():
    assert _coerce("true", None) is True
    assert _coerce("yes", None) is True
    assert _coerce("TRUE", None) is True


def test_coerce_boolean_false():
    assert _coerce("false", None) is False
    assert _coerce("no", None) is False


def test_coerce_falls_back_to_default():
    assert _coerce(None, "default_value") == "default_value"
    assert _coerce("", "fallback") == "fallback"


def test_coerce_preserves_non_boolean_string():
    assert _coerce("cn-east-3", None) == "cn-east-3"
    assert _coerce("lz-org", None) == "lz-org"


def test_coerce_preserves_integer():
    assert _coerce(365, None) == 365


def test_detect_filled_domains_empty():
    lld = {"D1": {"home_region": None}, "D2": {"enable_scim_sync": None}}
    filled = detect_filled_domains(lld)
    assert filled == []


def test_detect_filled_domains_partial():
    lld = {
        "D1": {"home_region": "cn-east-3", "org_name": None},
        "D2": {"enable_scim_sync": None},
        "D3": {},
    }
    filled = detect_filled_domains(lld)
    assert "D1" in filled
    assert "D2" not in filled


def test_parse_excel_real_template():
    """Parse the actual LLD template and verify domain structure."""
    import pathlib
    template = pathlib.Path("/root/.claude/uploads/02ff1a3b-fe13-4dea-9d1c-a219157a4c78/82ae33fe-HuaweiCloudLZLLDTemplate.xlsx")
    if not template.exists():
        pytest.skip("LLD template file not present in test environment")

    result = parse_excel(str(template))

    # Metadata sheet should be parsed
    assert "_metadata" in result

    # All 9 domain sheets should be present
    for d in ["D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9"]:
        assert d in result, f"Domain {d} not found in parsed LLD"

    # D1 should have known field names
    d1 = result["D1"]
    assert "home_region" in d1
    assert "org_name" in d1
    assert "log_archive_account_email" in d1

    # D9 should have scp_enforcement_mode (CLAUDE.md constraint)
    d9 = result["D9"]
    assert "scp_enforcement_mode" in d9
