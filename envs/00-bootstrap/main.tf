provider "huaweicloud" {
  region     = var.home_region
  access_key = var.master_access_key
  secret_key = var.master_secret_key
}

# ── Terraform state OBS bucket ────────────────────────────────────────────────

resource "huaweicloud_kms_key" "tfstate" {
  key_alias        = "lz-tfstate-encryption"
  key_description  = "Encrypts Terraform state files in OBS"
  rotation_enabled = true
  region           = var.home_region
  tags = {
    ManagedBy = "terraform"
    Project   = "landing-zone"
  }
}

resource "huaweicloud_obs_bucket" "tfstate" {
  bucket        = var.tfstate_bucket_name
  storage_class = "STANDARD"
  region        = var.home_region

  versioning {
    status = "Enabled"
  }

  encryption {
    kms_key_id = huaweicloud_kms_key.tfstate.id
  }

  lifecycle_rule {
    name    = "expire-old-state-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }

  tags = {
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Purpose   = "tfstate"
  }
}

resource "huaweicloud_obs_bucket_policy" "tfstate" {
  bucket = huaweicloud_obs_bucket.tfstate.id
  policy = jsonencode({
    Statement = [
      {
        Sid    = "DenyNonSSL"
        Effect = "Deny"
        Principal = { ID = ["*"] }
        Action   = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${var.tfstate_bucket_name}",
          "arn:aws:s3:::${var.tfstate_bucket_name}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# ── Terraform automation IAM agency ──────────────────────────────────────────

resource "huaweicloud_identity_agency" "terraform_ci" {
  name                  = "lz-terraform-ci"
  description           = "Agency assumed by GitHub Actions / CI pipeline for Terraform runs"
  delegated_domain_name = "op_service"
  all_resources_roles   = ["FullAccess"]
}
