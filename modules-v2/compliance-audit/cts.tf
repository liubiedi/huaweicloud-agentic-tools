# Org-wide CTS tracker: one tracker in the CTS admin account records every
# member account into the central bucket.
#
# 'name' on the tracker is computed by the service; never set it.
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

# ---- Deferred CTS extensions (default off; var-driven empty maps) ----
#
# huaweicloud_cts_notification and huaweicloud_cts_data_tracker stay disabled
# until someone needs them. Check their schemas in the provider docs before
# re-enabling.
