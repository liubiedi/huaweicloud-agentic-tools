# ---- Archive bucket (LTS transfer destination) ----

resource "huaweicloud_obs_bucket" "archive" {
  count = local.enabled ? 1 : 0

  bucket        = local.archive_bucket_name
  storage_class = "STANDARD"
  acl           = "private"

  # OBS bucket names are immutable: changing archive_bucket_name destroys +
  # recreates the bucket. force_destroy lets Terraform delete a NON-EMPTY old
  # bucket on that rename - i.e. it DELETES the archived logs. Default false.
  force_destroy = var.archive_bucket_force_destroy

  versioning = true

  encryption    = true
  sse_algorithm = "kms"
  kms_key_id    = huaweicloud_kms_key.archive[0].id

  lifecycle_rule {
    name    = "log-archive-retention"
    enabled = true
    expiration {
      days = var.archive_retention_days
    }
    # Move objects to the COLD storage class after N days (0 = keep STANDARD).
    dynamic "transition" {
      for_each = var.archive_cold_after_days > 0 ? [1] : []
      content {
        days          = var.archive_cold_after_days
        storage_class = "COLD"
      }
    }
    noncurrent_version_expiration {
      days = var.archive_retention_days
    }
    dynamic "noncurrent_version_transition" {
      for_each = var.archive_cold_after_days > 0 ? [1] : []
      content {
        days          = var.archive_cold_after_days
        storage_class = "COLD"
      }
    }
    abort_incomplete_multipart_upload {
      days = 7
    }
  }

  tags = var.tags
}

# Deny any request that does not use TLS (Config rule: "OBS Buckets Should
# Deny Requests Not Encrypted with SSL"). LTS transfers and SOC pulls use HTTPS.
resource "huaweicloud_obs_bucket_policy" "archive_tls_only" {
  count  = local.enabled ? 1 : 0
  bucket = huaweicloud_obs_bucket.archive[0].id
  policy = <<POLICY
{
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": {"ID": "*"},
      "Action": ["*"],
      "Resource": ["${huaweicloud_obs_bucket.archive[0].bucket}", "${huaweicloud_obs_bucket.archive[0].bucket}/*"],
      "Condition": {"Bool": {"SecureTransport": ["false"]}}
    }
  ]
}
POLICY
}

resource "huaweicloud_obs_bucket_bpa" "archive" {
  count = local.enabled ? 1 : 0

  bucket = huaweicloud_obs_bucket.archive[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  lifecycle {
    replace_triggered_by = [huaweicloud_obs_bucket.archive]
  }
}
