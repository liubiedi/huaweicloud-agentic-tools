# Bootstrap: creates the OBS bucket and KMS key that hold Terraform state
# for every later env composition. Run this first, with local state.

provider "huaweicloud" {
  region     = var.home_region
  access_key = var.master_access_key
  secret_key = var.master_secret_key

  default_tags = {
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Purpose   = "tfstate-backend"
  }
}

# KMS key for encrypting the state bucket
resource "huaweicloud_kms_key" "tfstate" {
  key_alias       = "${var.tfstate_bucket_name}-key"
  key_description = "Encrypts the Terraform state bucket for the landing zone"
  pending_days    = "30"
}

# OBS bucket — versioned + KMS-encrypted, private.
# `versioning`, `encryption`, `sse_algorithm`, `kms_key_id` are FLAT top-level
# arguments on huaweicloud_obs_bucket — NOT nested blocks. (Different from AWS S3.)
resource "huaweicloud_obs_bucket" "tfstate" {
  bucket        = var.tfstate_bucket_name
  acl           = "private"
  force_destroy = false
  versioning    = true

  encryption    = true
  sse_algorithm = "kms"
  kms_key_id    = huaweicloud_kms_key.tfstate.id

  lifecycle_rule {
    name    = "expire-old-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days = 7
    }
  }

  tags = {
    Critical = "true"
  }
}

# Note: no huaweicloud_obs_bucket_policy here. The bucket is `acl = "private"`
# and KMS-encrypted, which is enough for the state-backend case. If you later
# need a bucket policy, add a huaweicloud_obs_bucket_policy resource using
# Huawei OBS-native policy syntax (see provider docs — set policy_format="obs",
# the default; "aws:*" condition keys are not reliably honored).
