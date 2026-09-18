# Org-wide CTS tracker: one tracker in the CTS admin account records every
# member account into the central bucket.
#
# 'name' on the tracker is computed by the service; never set it. With
# lts_enabled the service writes the trail to an LTS group/stream it creates
# itself (CTS / system-trace) - exposed as group_id / stream_id.
#
# The tracker is created in the module's provider region (home_region). Note:
# Huawei's org-wide CTS tracker is a global service - if the deployment region
# doesn't support it, creation fails at apply (the provider does not restrict it).

resource "huaweicloud_cts_tracker" "org" {
  bucket_name          = huaweicloud_obs_bucket.audit.bucket
  file_prefix          = "org-audit"
  organization_enabled = true
  lts_enabled          = true
  enabled              = true

  validate_file = true
  compress_type = "gzip"
  # Encrypt delivered trace files with the audit key (Config rule:
  # "CTS Trackers Are Encrypted"). CTS gets the KMS grant automatically.
  kms_id = huaweicloud_kms_key.audit.id

  tags = var.tags
}

# ---- Key-event notifications (var-driven; empty list = none) ----
#
# One customized notification per var.cts_notifications entry: a trace matching
# any of its (service, resource, trace_names) blocks publishes to the ops SMN
# topic. See docs/engineering-notes.md for trace-name and scope rules.
resource "huaweicloud_cts_notification" "this" {
  for_each = { for n in var.cts_notifications : n.name => n }

  name           = each.value.name
  operation_type = "customized"
  smn_topic      = var.cts_notification_topic_urn
  enabled        = true

  dynamic "operations" {
    for_each = each.value.operations
    content {
      service     = operations.value.service
      resource    = operations.value.resource
      trace_names = operations.value.trace_names
    }
  }
}

# huaweicloud_cts_data_tracker stays deferred (cts_data_trackers, default off).
