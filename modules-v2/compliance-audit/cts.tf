# --- Organization audit tracker ---
# Note: The service assigns the tracker name and creates CTS/system-trace when LTS is enabled.
# Note: The provider region must support the organization tracker.

resource "huaweicloud_cts_tracker" "org" {
  bucket_name          = huaweicloud_obs_bucket.audit.bucket
  file_prefix          = "org-audit"
  organization_enabled = true
  lts_enabled          = true
  enabled              = true

  validate_file = true
  compress_type = "gzip"
  # Audit trace encryption
  kms_id = huaweicloud_kms_key.audit.id

  tags = var.tags
}

# --- Key-event notifications ---
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

