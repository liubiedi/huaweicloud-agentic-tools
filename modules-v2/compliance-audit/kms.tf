# Log-infrastructure CMKs - one per bucket.

resource "huaweicloud_kms_key" "audit" {
  key_alias         = local.kms_audit_alias
  key_description   = "Encrypts the central CTS audit OBS bucket"
  pending_days      = var.kms_pending_days
  rotation_enabled  = true
  rotation_interval = 365

  tags = var.tags
}

