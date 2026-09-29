# --- Provider requirements ---

terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = { source = "huaweicloud/huaweicloud", version = "~> 1.87" }
  }
}

# --- SCP attachment validation ---
check "attach_target_when_scps" {
  assert {
    condition     = !var.enable_scps || var.attach_target_id != ""
    error_message = "attach_target_id is required when enable_scps = true (typically the Workloads OU ID from 01-foundation)."
  }
}

# --- Organization path validation ---
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
