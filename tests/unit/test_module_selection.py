"""Unit tests for module selection parsing and domain dependency resolution."""
import pytest
from agent.steps.step02_module_selection import _parse_selection
from agent.models.domain_map import resolve_dependencies, domains_to_envs, DOMAIN_MODULE_MAP


AVAILABLE = list(DOMAIN_MODULE_MAP.keys())


@pytest.mark.parametrize("reply,expected", [
    ("all", ["D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9"]),
    ("ALL", ["D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9"]),
    ("I want to deploy: D1, D2, D3", ["D1", "D2", "D3"]),
    ("d1 d2 d3", ["D1", "D2", "D3"]),
    ("D1,D2,D9", ["D1", "D2", "D9"]),
    ("Please deploy D1 and D2 for me", ["D1", "D2"]),
    ("deploy D7", ["D7"]),
])
def test_parse_selection(reply, expected):
    result = _parse_selection(reply, AVAILABLE)
    assert result == expected


def test_parse_empty_reply():
    result = _parse_selection("No domains mentioned here", AVAILABLE)
    assert result == []


def test_resolve_dependencies_d3_requires_d1():
    resolved = resolve_dependencies(["D3"])
    assert "D1" in resolved
    assert "D3" in resolved


def test_resolve_dependencies_d5_requires_d4_d1():
    resolved = resolve_dependencies(["D5"])
    assert "D1" in resolved
    assert "D4" in resolved
    assert "D5" in resolved


def test_resolve_dependencies_d9_requires_d3_d1():
    resolved = resolve_dependencies(["D9"])
    assert "D1" in resolved
    assert "D3" in resolved
    assert "D9" in resolved


def test_resolve_dependencies_d2_only_requires_d1():
    resolved = resolve_dependencies(["D2"])
    assert "D1" in resolved
    assert "D2" in resolved
    assert "D3" not in resolved


def test_resolve_dependencies_no_duplication():
    resolved = resolve_dependencies(["D1", "D2", "D3"])
    assert len(resolved) == len(set(resolved))


def test_domains_to_envs_d1_d2():
    envs = domains_to_envs(["D1", "D2"])
    assert envs == ["01-foundation"]


def test_domains_to_envs_d1_d3():
    envs = domains_to_envs(["D1", "D3"])
    assert "01-foundation" in envs
    assert "02-network" in envs
    # Must be in order
    assert envs.index("01-foundation") < envs.index("02-network")


def test_domains_to_envs_all():
    envs = domains_to_envs(AVAILABLE)
    assert envs == ["01-foundation", "02-network", "03-security-audit", "04-ops-finance", "05-perimeter"]


def test_domains_to_envs_d4_d5_d6_same_env():
    envs = domains_to_envs(["D4", "D5", "D6"])
    assert envs == ["03-security-audit"]
