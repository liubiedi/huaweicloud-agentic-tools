resource "huaweicloud_kms_key" "archive" {
  count = local.enabled ? 1 : 0

  key_alias         = local.kms_archive_alias
  key_description   = "Encrypts the central LTS log-archive OBS bucket"
  pending_days      = var.kms_pending_days
  rotation_enabled  = true
  rotation_interval = 365

  tags = var.tags
}
