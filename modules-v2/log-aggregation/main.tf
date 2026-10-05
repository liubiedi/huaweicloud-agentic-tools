# --- Provider requirements ---

terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = { source = "huaweicloud/huaweicloud", version = "~> 1.87" }
  }
}

locals {
  enabled = var.enable_log_aggregation

  # Account-name substitution
  archive_bucket_name = replace(var.archive_bucket_name, "{account-name}", var.account_name)
  kms_archive_alias   = replace(var.kms_archive_alias, "{account-name}", var.account_name)

  # Local and remote log sources
  remote_members = {
    for k, v in var.converge_members : k => v
    if v.account_id != var.management_account_id
  }
  local_mappings = {
    for m in flatten([
      for k, v in var.converge_members : v.mappings
      if v.account_id == var.management_account_id
    ]) : m.target_log_group_name => m
  }

  # Target group and stream mappings
  _all_mappings = flatten([
    for acct, m in local.remote_members : m.mappings
  ])

  target_groups = local.enabled ? toset([for m in local._all_mappings : m.target_log_group_name]) : toset([])

  target_streams = local.enabled ? {
    for pair in flatten([
      for m in local._all_mappings : [
        for s in m.streams : {
          key    = "${m.target_log_group_name}__${s.target_log_stream_name}"
          group  = m.target_log_group_name
          stream = s.target_log_stream_name
        }
      ]
    ]) : pair.key => pair
  } : {}

  # Streams by target group
  streams_by_group = {
    for g in local.target_groups : g => [
      for k, s in local.target_streams : s.stream if s.group == g
    ]
  }
}

# --- Admin region project lookup ---
data "huaweicloud_identity_projects" "admin" {
  count = local.enabled ? 1 : 0

  name = var.home_region
}
