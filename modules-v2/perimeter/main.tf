# Module 4 - data perimeter. SCP locals + resources live in policies.tf; the
# TMS predefined-tag dictionary lives in tms-tags.tf. This file holds the
# input-consistency checks.

# SCPs must attach somewhere (the Workloads OU). Tags-only invocations set
# enable_scps = false and are exempt.
check "attach_target_when_scps" {
  assert {
    condition     = !var.enable_scps || var.attach_target_id != ""
    error_message = "attach_target_id is required when enable_scps = true (typically the Workloads OU ID from module 1)."
  }
}

# The RAM-share / RMS-aggregation guardrails need an allowed org path. It can
# come from org_id + root_ou_id, or be set per-policy via allowed_org_path.
check "org_path_for_cross_org_scps" {
  assert {
    condition     = !(var.enable_scps && var.scps.deny_unauthorized_ram_share.enabled) || local._ram_org_path != ""
    error_message = "deny_unauthorized_ram_share needs an org path: set org_id + root_ou_id, or scps.deny_unauthorized_ram_share.allowed_org_path."
  }
  assert {
    condition     = !(var.enable_scps && var.scps.deny_unauthorized_rms_aggregation.enabled) || local._rms_org_path != ""
    error_message = "deny_unauthorized_rms_aggregation needs an org path: set org_id + root_ou_id, or scps.deny_unauthorized_rms_aggregation.allowed_org_path."
  }
}
