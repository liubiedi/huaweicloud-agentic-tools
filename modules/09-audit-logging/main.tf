locals {
  # CTS org tracker is a global service — hard-coded to cn-north-4
  cts_region = "cn-north-4"

  tags = merge({
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Layer     = "audit-logging"
  }, var.tags)
}

# ── Log Archive OBS Bucket ────────────────────────────────────────────────────

resource "huaweicloud_obs_bucket" "log_archive" {
  bucket        = var.log_archive_bucket
  storage_class = "STANDARD"
  region        = var.log_archive_bucket_region

  versioning {
    status = "Enabled"
  }

  dynamic "encryption" {
    for_each = var.kms_key_id != "" ? [1] : []
    content {
      kms_key_id = var.kms_key_id
    }
  }

  lifecycle_rule {
    name    = "archive-transition"
    enabled = true
    prefix  = ""

    transition {
      days          = var.archive_cold_after_days
      storage_class = "WARM"
    }

    dynamic "expiration" {
      for_each = var.archive_expire_after_days > 0 ? [1] : []
      content {
        days = var.archive_expire_after_days
      }
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

resource "huaweicloud_obs_bucket_policy" "log_archive" {
  bucket = huaweicloud_obs_bucket.log_archive.id
  policy = jsonencode({
    Statement = [
      {
        Sid    = "AllowCTSWrite"
        Effect = "Allow"
        Principal = {
          Service = ["cts.myhuaweicloud.com"]
        }
        Action   = ["s3:PutObject", "s3:GetBucketAcl"]
        Resource = [
          "arn:aws:s3:::${var.log_archive_bucket}",
          "arn:aws:s3:::${var.log_archive_bucket}/*"
        ]
      },
      {
        Sid    = "DenyNonSSLAccess"
        Effect = "Deny"
        Principal = { ID = ["*"] }
        Action   = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${var.log_archive_bucket}",
          "arn:aws:s3:::${var.log_archive_bucket}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# ── CTS Organization Tracker ──────────────────────────────────────────────────
# Must be in cn-north-4. The region is intentionally not a variable.

resource "huaweicloud_cts_tracker" "org" {
  region = local.cts_region

  bucket_name              = var.log_archive_bucket
  file_prefix              = "cts"
  is_organization_tracker  = true
  is_support_validate      = true
  is_support_trace_files_encryption = var.kms_key_id != "" ? true : false
  kms_id                   = var.kms_key_id != "" ? var.kms_key_id : null
  is_lts_enabled           = true
  status                   = "enabled"

  depends_on = [huaweicloud_obs_bucket.log_archive]
}

resource "huaweicloud_cts_notification" "key_events" {
  count = var.smn_topic_urn != "" ? 1 : 0

  region           = local.cts_region
  name             = "lz-cts-key-event-alerts"
  operation_type   = "customized"
  smn_topic        = var.smn_topic_urn
  status           = "enabled"

  filter {
    condition = "OR"

    rule = ["code", "startsWith", "400"]
    rule = ["code", "startsWith", "403"]
    rule = ["code", "startsWith", "404"]
  }
}

# ── LTS Log Groups and Streams ────────────────────────────────────────────────

resource "huaweicloud_lts_group" "groups" {
  for_each = { for g in var.log_groups : g.name => g }

  group_name  = each.value.name
  ttl_in_days = each.value.retention_days
  region      = var.home_region
  tags        = local.tags
}

resource "huaweicloud_lts_stream" "streams" {
  for_each = {
    for pair in flatten([
      for g in var.log_groups : [
        for s in g.streams : {
          key        = "${g.name}__${s}"
          group_name = g.name
          stream     = s
        }
      ]
    ]) : pair.key => pair
  }

  group_id    = huaweicloud_lts_group.groups[each.value.group_name].id
  stream_name = each.value.stream
  region      = var.home_region
}

# ── LTS → OBS transfer (long-term archive) ────────────────────────────────────

resource "huaweicloud_lts_transfer" "archive" {
  for_each = { for g in var.log_groups : g.name => g }

  log_group_id = huaweicloud_lts_group.groups[each.key].id

  log_streams {
    log_stream_ids = [for s in each.value.streams : huaweicloud_lts_stream.streams["${each.key}__${s}"].id]
  }

  log_transfer_info {
    log_transfer_type   = "OBS"
    log_transfer_mode   = "cycle"
    log_storage_format  = "JSON"
    log_transfer_status = "ENABLE"

    log_transfer_detail {
      obs_period          = 1
      obs_period_unit     = "hour"
      obs_bucket_name     = var.log_archive_bucket
      obs_dir_prefix_name = each.key
      obs_prefix_name     = ""
      obs_time_zone       = "UTC+08:00"
    }
  }

  depends_on = [huaweicloud_obs_bucket.log_archive]
  region     = var.home_region
}
