
# --- Log receiving ---
# Note: Removing this resource disables receiving.
resource "huaweicloud_lts_log_converge_switch" "this" {
  count = local.enabled ? 1 : 0
}

# --- Target log groups and streams ---
resource "huaweicloud_lts_group" "target" {
  for_each = local.target_groups

  group_name  = each.value
  ttl_in_days = var.converged_retention_days
  tags        = var.tags
}

resource "huaweicloud_lts_stream" "target" {
  for_each = local.target_streams

  group_id    = huaweicloud_lts_group.target[each.value.group].id
  stream_name = each.value.stream
  ttl_in_days = var.converged_retention_days
  tags        = var.tags
}

# --- Member log convergence ---
resource "huaweicloud_lts_log_converge" "member" {
  for_each = local.enabled ? local.remote_members : {}

  organization_id       = var.organization_id
  management_account_id = var.management_account_id
  management_project_id = data.huaweicloud_identity_projects.admin[0].projects[0].id
  member_account_id     = each.value.account_id

  dynamic "log_mapping_config" {
    for_each = each.value.mappings
    content {
      source_log_group_id   = log_mapping_config.value.source_log_group_id
      target_log_group_name = log_mapping_config.value.target_log_group_name
      target_log_group_id   = huaweicloud_lts_group.target[log_mapping_config.value.target_log_group_name].id

      dynamic "log_stream_config" {
        for_each = log_mapping_config.value.streams
        content {
          source_log_stream_id   = log_stream_config.value.source_log_stream_id
          target_log_stream_name = log_stream_config.value.target_log_stream_name
          target_log_stream_id   = huaweicloud_lts_stream.target["${log_mapping_config.value.target_log_group_name}__${log_stream_config.value.target_log_stream_name}"].id
          target_log_stream_ttl  = var.converged_retention_days
        }
      }
    }
  }

  depends_on = [huaweicloud_lts_log_converge_switch.this]
}

# --- Converged log archival ---
resource "huaweicloud_lts_transfer" "archive" {
  for_each = local.streams_by_group

  log_group_id = huaweicloud_lts_group.target[each.key].id

  dynamic "log_streams" {
    for_each = each.value
    content {
      log_stream_id = huaweicloud_lts_stream.target["${each.key}__${log_streams.value}"].id
    }
  }

  log_transfer_info {
    log_transfer_type   = "OBS"
    log_transfer_mode   = "cycle"
    log_storage_format  = "RAW"
    log_transfer_status = "ENABLE"

    log_transfer_detail {
      obs_period      = var.transfer_period
      obs_period_unit = var.transfer_period_unit
      obs_bucket_name = huaweicloud_obs_bucket.archive[0].bucket
      # Note: Omit the trailing slash to avoid recurring drift.
      obs_dir_prefix_name  = each.key
      obs_encrypted_enable = true
      obs_encrypted_id     = huaweicloud_kms_key.archive[0].id
      obs_time_zone        = "UTC"
      obs_time_zone_id     = "Etc/GMT"
    }
  }
}

# --- Admin-local log archival ---
# Note: Runs after converged transfers establish LTS access to the encryption key.
resource "huaweicloud_lts_transfer" "archive_local" {
  for_each = local.enabled ? local.local_mappings : {}

  depends_on = [huaweicloud_lts_transfer.archive]

  log_group_id = each.value.source_log_group_id

  dynamic "log_streams" {
    for_each = each.value.streams
    content {
      log_stream_id = log_streams.value.source_log_stream_id
    }
  }

  log_transfer_info {
    log_transfer_type   = "OBS"
    log_transfer_mode   = "cycle"
    log_storage_format  = "RAW"
    log_transfer_status = "ENABLE"

    log_transfer_detail {
      obs_period      = var.transfer_period
      obs_period_unit = var.transfer_period_unit
      obs_bucket_name = huaweicloud_obs_bucket.archive[0].bucket
      # Note: Omit the trailing slash to avoid recurring drift.
      obs_dir_prefix_name  = each.key
      obs_encrypted_enable = true
      obs_encrypted_id     = huaweicloud_kms_key.archive[0].id
      obs_time_zone        = "UTC"
      obs_time_zone_id     = "Etc/GMT"
    }
  }
}
