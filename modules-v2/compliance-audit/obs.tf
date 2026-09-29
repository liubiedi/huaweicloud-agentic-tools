
# --- CTS audit bucket ---

resource "huaweicloud_obs_bucket" "audit" {
  bucket        = local.audit_bucket_name
  storage_class = "STANDARD"
  acl           = "private"

  # Note: Renaming replaces the bucket; force_destroy permits deletion of stored audit logs.
  force_destroy = var.audit_bucket_force_destroy

  versioning = true

  encryption    = true
  sse_algorithm = "kms"
  kms_key_id    = huaweicloud_kms_key.audit.id

  lifecycle_rule {
    name    = "audit-retention"
    enabled = true
    expiration {
      days = var.audit_retention_days
    }
    # Archive transition
    dynamic "transition" {
      for_each = var.audit_cold_after_days > 0 ? [1] : []
      content {
        days          = var.audit_cold_after_days
        storage_class = "COLD"
      }
    }
    noncurrent_version_expiration {
      days = var.audit_retention_days
    }
    dynamic "noncurrent_version_transition" {
      for_each = var.audit_cold_after_days > 0 ? [1] : []
      content {
        days          = var.audit_cold_after_days
        storage_class = "COLD"
      }
    }
    abort_incomplete_multipart_upload {
      days = 7
    }
  }

  tags = var.tags
}

# --- TLS-only access policy ---
resource "huaweicloud_obs_bucket_policy" "audit_tls_only" {
  bucket = huaweicloud_obs_bucket.audit.id
  policy = <<POLICY
{
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": {"ID": "*"},
      "Action": ["*"],
      "Resource": ["${huaweicloud_obs_bucket.audit.bucket}", "${huaweicloud_obs_bucket.audit.bucket}/*"],
      "Condition": {"Bool": {"SecureTransport": ["false"]}}
    }
  ]
}
POLICY
}

resource "huaweicloud_obs_bucket_bpa" "audit" {
  bucket = huaweicloud_obs_bucket.audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Note: Replace the public-access block when the bucket is replaced.
  lifecycle {
    replace_triggered_by = [huaweicloud_obs_bucket.audit]
  }
}

# --- CTS delivery permissions ---
# Note: Delivery is within the audit account; no cross-account grant is configured.
