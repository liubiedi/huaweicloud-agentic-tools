import pytest
from agent.cicd.error_classifier import classify, ErrorCategory


@pytest.mark.parametrize("code,msg,expected_category", [
    ("CBC.0150", "quota exceeded", ErrorCategory.QUOTA_EXCEEDED),
    ("VPC.0601", "VPC quota limit reached", ErrorCategory.QUOTA_EXCEEDED),
    (None, "quota exceeded for resource type", ErrorCategory.QUOTA_EXCEEDED),
    ("IAM.0003", "Access denied", ErrorCategory.PERMISSION_DENIED),
    (None, "AccessDenied: user is not authorized", ErrorCategory.PERMISSION_DENIED),
    (None, "AlreadyExists: resource already exist", ErrorCategory.RESOURCE_EXISTS),
    (None, "_DUPLICATE resource found", ErrorCategory.RESOURCE_EXISTS),
    (None, "RGC_PROVISIONING in progress", ErrorCategory.DEPENDENCY_NOT_READY),
    (None, "account is not ready yet propagat", ErrorCategory.DEPENDENCY_NOT_READY),
    (None, "_INVALID_INPUT: bad parameter value", ErrorCategory.INVALID_PARAM),
    (None, "ServiceUnavailable: 503", ErrorCategory.SERVICE_UNAVAILABLE),
    ("APIGW.0503", "temporarily unavailable", ErrorCategory.SERVICE_UNAVAILABLE),
    (None, "REGION_NOT_SUPPORTED for service X", ErrorCategory.REGION_UNSUPPORTED),
    (None, "ORG.ACCOUNT_NOT_FOUND in organization", ErrorCategory.ACCOUNT_NOT_FOUND),
])
def test_classify_static_table(code, msg, expected_category):
    result = classify(code, msg)
    assert result.category == expected_category
    assert result.confidence == 1.0


def test_classify_unknown_does_not_raise():
    result = classify(None, "some completely novel error message xyz123")
    # Should return something (LLM fallback or UNKNOWN) without raising
    assert result.category is not None


def test_quota_policy_allows_retries():
    result = classify("CBC.0150", "quota exceeded")
    assert result.policy.max_retries >= 1


def test_permission_denied_escalates():
    result = classify("IAM.0003", "Access denied")
    assert result.policy.action == "escalate" or result.policy.max_retries <= 1


def test_dependency_policy_has_wait():
    result = classify(None, "RGC_PROVISIONING in progress")
    assert result.policy.wait_s > 0
    assert result.policy.max_retries > 5
