locals {
  tags = merge({
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Layer     = "shared-resources"
  }, var.tags)
}

# ── KMS Keys ──────────────────────────────────────────────────────────────────

resource "huaweicloud_kms_key" "keys" {
  for_each = { for k in var.kms_keys : k.alias => k }

  key_alias       = each.value.alias
  key_description = each.value.description
  rotation_enabled = each.value.rotation_enabled
  pending_days    = each.value.pending_days
  region          = var.home_region
  enterprise_project_id = var.enterprise_project_id

  tags = local.tags
}

resource "huaweicloud_ram_resource_share" "kms" {
  for_each = {
    for k in var.kms_keys : k.alias => k
    if length(k.shared_account_ids) > 0
  }

  name           = "lz-kms-share-${each.key}"
  description    = "Share KMS key ${each.key} to spoke accounts"
  principals     = each.value.shared_account_ids
  resource_type  = "kms:cmk"
  resource_ids   = [huaweicloud_kms_key.keys[each.key].id]
}

# ── Shared OBS Buckets ────────────────────────────────────────────────────────

resource "huaweicloud_obs_bucket" "shared" {
  for_each = { for b in var.shared_obs_buckets : b.name => b }

  bucket        = each.value.name
  storage_class = each.value.storage_class
  region        = var.home_region

  dynamic "versioning" {
    for_each = each.value.versioning ? [1] : []
    content {
      status = "Enabled"
    }
  }

  dynamic "encryption" {
    for_each = each.value.kms_key_id != "" ? [1] : []
    content {
      kms_key_id = each.value.kms_key_id
    }
  }

  lifecycle_rule {
    name    = "abort-incomplete-mpu"
    enabled = true

    abort_incomplete_multipart_upload {
      days = 7
    }
  }

  tags = local.tags
}

resource "huaweicloud_obs_bucket_policy" "shared" {
  for_each = { for b in var.shared_obs_buckets : b.name => b if length(b.shared_account_ids) > 0 }

  bucket = huaweicloud_obs_bucket.shared[each.key].id
  policy = jsonencode({
    Statement = [
      {
        Sid    = "AllowSharedAccounts"
        Effect = "Allow"
        Principal = {
          ID = [for id in each.value.shared_account_ids : "arn:aws:iam::${id}:root"]
        }
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${each.key}",
          "arn:aws:s3:::${each.key}/*"
        ]
      }
    ]
  })
}

# ── SFS Turbo ─────────────────────────────────────────────────────────────────

resource "huaweicloud_sfs_turbo" "instances" {
  for_each = { for s in var.sfs_turbo_instances : s.name => s }

  name              = each.value.name
  size              = each.value.size
  share_type        = each.value.share_type
  vpc_id            = each.value.vpc_id
  subnet_id         = each.value.subnet_id
  security_group_id = each.value.security_group_id
  availability_zone = each.value.availability_zone
  region            = var.home_region
  enterprise_project_id = var.enterprise_project_id

  tags = local.tags
}

# ── IMS Shared Images ─────────────────────────────────────────────────────────

resource "huaweicloud_images_image" "shared" {
  for_each = { for img in var.shared_images : img.name => img }

  name        = each.value.name
  image_url   = each.value.image_url
  os_type     = each.value.os_type
  description = each.value.description
  region      = var.home_region

  tags = local.tags
}

resource "huaweicloud_images_image_share" "shares" {
  for_each = {
    for pair in flatten([
      for img in var.shared_images : [
        for acct_id in img.shared_account_ids : {
          key      = "${img.name}__${acct_id}"
          img_name = img.name
          acct_id  = acct_id
        }
      ]
    ]) : pair.key => pair
  }

  source_image_id = huaweicloud_images_image.shared[each.value.img_name].id
  target_project_ids = [each.value.acct_id]
  region          = var.home_region
}
