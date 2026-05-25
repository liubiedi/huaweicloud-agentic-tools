"""
CI/CD error classifier.
Maps Huawei Cloud API error codes and message patterns to ErrorCategory + remediation policy.
Falls back to LLM (Claude API) for unclassified errors.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

import structlog

log = structlog.get_logger()


class ErrorCategory(str, Enum):
    QUOTA_EXCEEDED = "QUOTA_EXCEEDED"
    PERMISSION_DENIED = "PERMISSION_DENIED"
    RESOURCE_EXISTS = "RESOURCE_EXISTS"
    DEPENDENCY_NOT_READY = "DEPENDENCY_NOT_READY"
    INVALID_PARAM = "INVALID_PARAM"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"
    REGION_UNSUPPORTED = "REGION_UNSUPPORTED"
    ACCOUNT_NOT_FOUND = "ACCOUNT_NOT_FOUND"
    UNKNOWN = "UNKNOWN"


@dataclass
class RemediationPolicy:
    max_retries: int = 0
    wait_s: int = 0
    backoff: bool = False
    action: str = ""  # "import", "regen", "escalate"


@dataclass
class Classification:
    category: ErrorCategory
    policy: RemediationPolicy
    confidence: float = 1.0


_TABLE: list[tuple[str, ErrorCategory, RemediationPolicy]] = [
    # Quota exceeded
    (r"CBC\.0150|VPC\.0601|quota|QUOTA_EXCEEDED|QuotaExceeded",
     ErrorCategory.QUOTA_EXCEEDED,
     RemediationPolicy(max_retries=3, wait_s=30)),

    # Permission denied
    (r"IAM\.0003|APIGW\.0301|AccessDenied|Unauthorized|UNAUTHORIZED|403",
     ErrorCategory.PERMISSION_DENIED,
     RemediationPolicy(max_retries=1, wait_s=0, action="escalate")),

    # Resource already exists
    (r"_DUPLICATE|CONFLICT|AlreadyExists|already exist",
     ErrorCategory.RESOURCE_EXISTS,
     RemediationPolicy(max_retries=1, action="import")),

    # Dependency not ready (RGC provisioning, account propagation)
    (r"RGC_PROVISIONING|ACCOUNT_CREATING|account.*not.*ready|propagat",
     ErrorCategory.DEPENDENCY_NOT_READY,
     RemediationPolicy(max_retries=30, wait_s=60)),

    # Invalid parameter
    (r"_INVALID_INPUT|InvalidParameter|invalid.*parameter|INVALID",
     ErrorCategory.INVALID_PARAM,
     RemediationPolicy(max_retries=1, action="regen")),

    # Service temporarily unavailable
    (r"503|APIGW\.0503|ServiceUnavailable|temporarily unavailable",
     ErrorCategory.SERVICE_UNAVAILABLE,
     RemediationPolicy(max_retries=5, wait_s=30, backoff=True)),

    # Region not supported
    (r"REGION_NOT_SUPPORTED|region.*not.*support|not.*available.*region",
     ErrorCategory.REGION_UNSUPPORTED,
     RemediationPolicy(max_retries=0, action="escalate")),

    # Account not found in org
    (r"ORG\.ACCOUNT_NOT_FOUND|account.*not.*found|ACCOUNT_NOT_FOUND",
     ErrorCategory.ACCOUNT_NOT_FOUND,
     RemediationPolicy(max_retries=5, wait_s=120)),
]


def classify(error_code: str | None, error_message: str) -> Classification:
    """Classify a CI/CD error. Returns Classification with category and policy."""
    haystack = " ".join(filter(None, [error_code, error_message]))
    for pattern, category, policy in _TABLE:
        if re.search(pattern, haystack, re.IGNORECASE):
            log.debug("error_classified", pattern=pattern, category=category)
            return Classification(category=category, policy=policy)

    # LLM fallback
    result = _llm_classify(error_code, error_message)
    return result


def _llm_classify(error_code: str | None, error_message: str) -> Classification:
    """Use Claude API to classify an error when pattern matching fails."""
    try:
        import anthropic
        client = anthropic.Anthropic()
        prompt = f"""\
Classify this Huawei Cloud Terraform error into exactly one category.
Respond with JSON only: {{"category": "<CATEGORY>", "confidence": <0.0-1.0>}}

Categories: {", ".join(c.value for c in ErrorCategory)}

Error code: {error_code or "none"}
Error message: {error_message[:500]}"""

        message = client.messages.create(
            model="claude-opus-4-7",
            max_tokens=64,
            messages=[{"role": "user", "content": prompt}],
        )
        import json
        data = json.loads(message.content[0].text)
        category = ErrorCategory(data.get("category", "UNKNOWN"))
        confidence = float(data.get("confidence", 0.5))
        log.info("llm_classification", category=category, confidence=confidence)
        return Classification(
            category=category,
            policy=RemediationPolicy(max_retries=0, action="escalate"),
            confidence=confidence,
        )
    except Exception as exc:
        log.error("llm_classify_failed", error=str(exc))
        return Classification(
            category=ErrorCategory.UNKNOWN,
            policy=RemediationPolicy(max_retries=0, action="escalate"),
            confidence=0.0,
        )
