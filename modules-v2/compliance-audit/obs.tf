# One OBS bucket:
#   - lz-audit  (the central CTS event trail)

# ---- Audit bucket (CTS events) ----

resource "huaweicloud_obs_bucket" "audit" {
  bucket        = local.audit_bucket_name
  storage_class = "STANDARD"
  acl           = "private"

  # OBS bucket names are immutable: changing audit_bucket_name destroys + recreates
  # the bucket. force_destroy lets Terraform delete a NON-EMPTY old bucket on that
  # rename - i.e. it DELETES the stored audit objects. Default false (safe): a
  # rename then fails until you opt in, so you don't lose audit logs by accident.
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
    # Move objects to the COLD storage class after N days (0 = keep STANDARD).
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

# Deny any request that does not use TLS (Config rule: "OBS Buckets Should
# Deny Requests Not Encrypted with SSL"). Pure Deny statement - grants for the
# CTS service delivery are unaffected (CTS writes over HTTPS).
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

  # The BPA's bucket is immutable. When the bucket is REPLACED (a rename), the BPA
  # must be replaced too rather than updated-in-place ("bucket can't be updated").
  lifecycle {
    replace_triggered_by = [huaweicloud_obs_bucket.audit]
  }
}

# No explicit OBS bucket policy: the org CTS tracker and the audit bucket live in
# the same (CTS-admin) account, so CTS writes in-account. (The old AWS/S3-style
# policy - s3:PutObject / arn:aws principals - is invalid for Huawei OBS:
# MalformedPolicy "invalid action". If cross-account CTS write is ever needed,
# add an OBS-format policy: policy_format="obs", Principal={ID=["domain/<id>"]},
# Action=["PutObject"].)
