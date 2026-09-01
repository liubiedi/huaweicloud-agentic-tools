locals {
  enabled = var.enable_log_aggregation

  # Substitute the {account-name} token with the account this module deploys into.
  archive_bucket_name = replace(var.archive_bucket_name, "{account-name}", var.account_name)
  kms_archive_alias   = replace(var.kms_archive_alias, "{account-name}", var.account_name)

  # Split sources by locality. REMOTE member accounts converge into target
  # groups/streams owned here; sources already IN this (admin) account skip the
  # converge (member == admin is not a converge case) and transfer their SOURCE
  # group straight to the archive bucket.
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

  # Flatten the REMOTE mappings into the distinct TARGET groups/streams this
  # module owns. Creating them explicitly (instead of letting the converge API
  # auto-create) keeps plans deterministic and lets the transfers reference them
  # by resource, not by deferred data lookup.
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

  # Streams per target group, for the one-transfer-per-group fan-in.
  streams_by_group = {
    for g in local.target_groups : g => [
      for k, s in local.target_streams : s.stream if s.group == g
    ]
  }
}

# The admin account's region project ID (project name == region ID), required by
# lts_log_converge.management_project_id on first use.
data "huaweicloud_identity_projects" "admin" {
  count = local.enabled ? 1 : 0

  name = var.home_region
}
