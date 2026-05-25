import json
import pytest
from agent.models.run_state import RunState, Step, CheckResult, CicdEvent, CicdEventType


def test_run_state_roundtrip():
    state = RunState(run_id="test-123", step=Step.GAP_FILL, requester_email="eng@example.com")
    state.deploy_domains = ["D1", "D2"]
    state.deploy_envs = ["01-foundation"]
    state.gap_rounds = 1

    serialized = state.model_dump_json()
    restored = RunState.model_validate(json.loads(serialized))

    assert restored.run_id == "test-123"
    assert restored.step == Step.GAP_FILL
    assert restored.deploy_domains == ["D1", "D2"]
    assert restored.gap_rounds == 1
    assert restored.hmac_token == state.hmac_token


def test_step_order_next():
    state = RunState(run_id="x")
    state.step = Step.LLD_READ
    assert state.next_step() == Step.MODULE_SELECTION
    state.step = Step.MODULE_SELECTION
    assert state.next_step() == Step.GAP_FILL
    state.step = Step.POST_APPLY
    assert state.next_step() == Step.DONE


def test_attempt_counting():
    state = RunState(run_id="x", step=Step.CICD_EXECUTE)
    assert state.get_attempt("network_hub") == 0
    state.increment_attempt("network_hub")
    assert state.get_attempt("network_hub") == 1
    state.increment_attempt("network_hub")
    assert state.get_attempt("network_hub") == 2


def test_check_result_model():
    r = CheckResult(id="A1", name="OIDC", status="PASS", details="2 providers found")
    assert r.status == "PASS"
    d = r.model_dump()
    assert d["id"] == "A1"


def test_cicd_event_model():
    ev = CicdEvent(
        event_type=CicdEventType.STEP_ERROR,
        run_id="run-001",
        module="network_hub",
        error_code="VPC.0601",
        error_message="quota exceeded",
    )
    assert ev.event_type == CicdEventType.STEP_ERROR
    assert ev.run_id == "run-001"


def test_hmac_token_unique():
    s1 = RunState(run_id="a")
    s2 = RunState(run_id="b")
    assert s1.hmac_token != s2.hmac_token
    assert len(s1.hmac_token) == 64  # 32 bytes hex
