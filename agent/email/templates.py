"""All outbound email templates rendered as plain-text strings."""
from __future__ import annotations

from textwrap import dedent
from typing import Any


def module_selection_email(
    run_id: str,
    requester_name: str,
    domain_lines: list[str],
    filled_domains: list[str],
) -> str:
    filled_str = ", ".join(filled_domains) if filled_domains else "none detected"
    domains_block = "\n".join(domain_lines)
    return dedent(f"""\
        Hi {requester_name},

        I have parsed your Landing Zone LLD (Run ID: {run_id}).

        The following governance domains are available for deployment:

        {domains_block}

        Domains with detected values: {filled_str}

        Please reply to this email and specify which domains you want to deploy.
        Examples:
          • "all"                   — deploy all 9 domains in sequence
          • "D1, D2, D3"            — deploy only Org, Identity, and Network
          • "D1 D2"                 — same as above without commas

        Dependencies are resolved automatically (e.g. selecting D3 also selects D1).

        Reply format (keep the subject line unchanged):
            I want to deploy: D1, D2, D3

        Regards,
        LZ Agent
    """)


def gap_fill_email(
    run_id: str,
    requester_name: str,
    gaps: dict[str, list[str]],
    round_num: int,
    max_rounds: int,
) -> str:
    lines = []
    for domain_id, fields in sorted(gaps.items()):
        lines.append(f"\n  {domain_id}:")
        for f in fields:
            lines.append(f"    {domain_id}.{f} = ")
    fields_block = "\n".join(lines)

    return dedent(f"""\
        Hi {requester_name},

        Round {round_num}/{max_rounds}: the following required fields are still empty
        in your LLD (Run ID: {run_id}).

        Please reply with the missing values using the format below.
        Copy the lines, fill in the values after "=", and send back.

        ─────────────────────────────────────────────────────
        {fields_block}
        ─────────────────────────────────────────────────────

        Notes:
        • Use dot notation:  D1.org_name = MyCompanyCloud
        • Booleans: true / false
        • Lists (e.g. allowed_regions): comma-separated: cn-east-3, cn-north-4

        Regards,
        LZ Agent
    """)


def preflight_report_email(
    run_id: str,
    requester_name: str,
    results: list[dict],
    recheck_round: int,
    max_recheck: int,
    failed_ids: list[str],
) -> str:
    rows = []
    for r in results:
        icon = "✓" if r["status"] == "PASS" else ("✗" if r["status"] == "FAIL" else "–")
        rows.append(f"  {icon} [{r['id']}] {r['name']}: {r['status']}")
        if r.get("details"):
            rows.append(f"        {r['details']}")
        if r.get("fix") and r["status"] == "FAIL":
            rows.append(f"        Fix: {r['fix']}")

    block = "\n".join(rows)
    pass_count = sum(1 for r in results if r["status"] == "PASS")
    fail_count = len(failed_ids)

    if fail_count == 0:
        summary = "All pre-flight checks PASSED. Proceeding to artifact generation."
        action = ""
    else:
        summary = (
            f"{fail_count} check(s) FAILED. "
            f"This is round {recheck_round}/{max_recheck}."
        )
        action = dedent("""\

            Action required:
            • Resolve the issues described above
            • Reply with "RECHECK" to re-run failed checks
            • Reply with "SKIP" to skip failed checks and proceed (not recommended)
            • Reply with "ABORT" to cancel the deployment
        """)

    return dedent(f"""\
        Hi {requester_name},

        Pre-flight check report for Run ID: {run_id}
        {summary}

        Results:
        {block}
        {action}
        Regards,
        LZ Agent
    """)


def approval_email(
    run_id: str,
    requester_name: str,
    env: str,
    plan_summary: str,
) -> str:
    return dedent(f"""\
        Hi {requester_name},

        Terraform plan for env/{env} is ready for your approval (Run ID: {run_id}).

        ─── Plan Summary ───────────────────────────────────────
        {plan_summary}
        ────────────────────────────────────────────────────────

        Please reply with one of:
          APPROVE  — proceed with terraform apply
          REJECT   — cancel deployment and notify the team

        Reply format (keep the subject line unchanged):
            APPROVE

        Regards,
        LZ Agent
    """)


def completion_email(
    run_id: str,
    requester_name: str,
    deployed_envs: list[str],
    post_apply_summary: str,
    duration_minutes: float,
    partial: bool = False,
) -> str:
    status = "PARTIAL" if partial else "SUCCESS"
    verb = "partially deployed" if partial else "deployed"
    envs_str = ", ".join(deployed_envs)

    return dedent(f"""\
        Hi {requester_name},

        Landing Zone deployment {status} (Run ID: {run_id})

        Environments {verb}: {envs_str}
        Total duration: {duration_minutes:.1f} minutes

        ─── Post-apply verification ────────────────────────────
        {post_apply_summary}
        ────────────────────────────────────────────────────────

        CTS audit trail: search CTS for tracker "lz-org-cts-tracker" to review
        all API calls made during this deployment. Zero manual console steps.

        Regards,
        LZ Agent
    """)


def escalation_email(
    run_id: str,
    requester_name: str,
    title: str,
    details: str,
    suggested_action: str,
) -> str:
    return dedent(f"""\
        Hi {requester_name},

        ⚠ Escalation required for Landing Zone run {run_id}

        {title}

        ─── Details ─────────────────────────────────────────────
        {details}
        ─────────────────────────────────────────────────────────

        Suggested action:
        {suggested_action}

        Please reply with one of:
          RESUME  — after you have resolved the issue manually
          ABORT   — cancel the deployment

        Regards,
        LZ Agent
    """)
