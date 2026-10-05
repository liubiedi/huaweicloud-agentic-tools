# --- Config recorder and aggregation ---

locals {
  config_recorder_region = var.config.recorder_bucket_region != "" ? var.config.recorder_bucket_region : var.home_region

  _create_recorder = var.enable_config && var.config.enable_recorder

  # Recorder prerequisite resolution
  recorder_bucket_name = local._create_recorder && var.config.create_recorder_bucket ? one(huaweicloud_obs_bucket.config_recorder[*].bucket) : var.config.recorder_bucket_name
  recorder_agency_name = local._create_recorder && var.config.create_recorder_agency ? one(huaweicloud_identity_trust_agency.config_recorder[*].name) : var.config.recorder_agency_name
}

# --- Recorder bucket and access controls ---

resource "huaweicloud_obs_bucket" "config_recorder" {
  count = local._create_recorder && var.config.create_recorder_bucket ? 1 : 0

  bucket        = var.config.recorder_bucket_name
  storage_class = "STANDARD"
  acl           = "private"
  versioning    = true
  # Note: Grant the recorder agency key access before enabling KMS encryption.
  encryption    = var.config.recorder_bucket_kms_encrypt
  sse_algorithm = var.config.recorder_bucket_kms_encrypt ? "kms" : null
  force_destroy = false

  tags = var.tags
}

resource "huaweicloud_obs_bucket_bpa" "config_recorder" {
  count = local._create_recorder && var.config.create_recorder_bucket ? 1 : 0

  bucket = huaweicloud_obs_bucket.config_recorder[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Recorder bucket policy ---
resource "huaweicloud_obs_bucket_policy" "config_recorder" {
  count = local._create_recorder && var.config.create_recorder_bucket ? 1 : 0

  bucket        = huaweicloud_obs_bucket.config_recorder[0].id
  policy_format = "obs"
  policy = jsonencode({
    Statement = concat([
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = { ID = ["*"] }
        Action    = ["*"]
        Resource = [
          huaweicloud_obs_bucket.config_recorder[0].id,
          "${huaweicloud_obs_bucket.config_recorder[0].id}/*",
        ]
        Condition = { Bool = { SecureTransport = ["false"] } }
      },
      ], length(var.config.recorder_bucket_writer_domains) > 0 ? [
      {
        Sid       = "AllowMemberConfigRecorderWrites"
        Effect    = "Allow"
        Principal = { ID = [for d in var.config.recorder_bucket_writer_domains : "domain/${d}"] }
        Action    = ["PutObject", "GetObject", "DeleteObject", "AbortMultipartUpload", "ListBucket", "GetBucketLocation"]
        Resource = [
          huaweicloud_obs_bucket.config_recorder[0].id,
          "${huaweicloud_obs_bucket.config_recorder[0].id}/*",
        ]
      },
    ] : [])
  })

  depends_on = [huaweicloud_obs_bucket_bpa.config_recorder]
}

# --- Recorder trust agency ---
resource "huaweicloud_identity_trust_agency" "config_recorder" {
  count = local._create_recorder && var.config.create_recorder_agency ? 1 : 0

  name        = var.config.recorder_agency_name
  description = "Config (RMS) resource-recorder trust agency."
  trust_policy = jsonencode({
    Version = "5.0"
    Statement = [
      {
        Effect = "Allow"
        # Config service principal
        Principal = { Service = [var.config.recorder_agency_delegated_service] }
        Action    = ["sts:agencies:assume", "sts::tagSession", "sts::setSourceIdentity"]
      },
    ]
  })
  # Recorder access policies
  policy_names = var.config.recorder_agency_roles
}

# --- Resource recorder ---

resource "huaweicloud_rms_resource_recorder" "this" {
  count = local._create_recorder ? 1 : 0

  agency_name = local.recorder_agency_name

  selector {
    all_supported  = var.config.recorder_all_supported
    resource_types = var.config.recorder_all_supported ? null : var.config.recorder_resource_types
  }

  obs_channel {
    bucket = local.recorder_bucket_name
    region = local.config_recorder_region
  }

  dynamic "smn_channel" {
    for_each = var.config.recorder_smn_topic_urn != "" ? [1] : []
    content {
      topic_urn = var.config.recorder_smn_topic_urn
    }
  }

  depends_on = [
    huaweicloud_obs_bucket.config_recorder,
    huaweicloud_identity_trust_agency.config_recorder,
  ]
}

# --- Organization resource aggregator ---

resource "huaweicloud_rms_resource_aggregator" "org" {
  count = var.enable_config && var.config.enable_aggregator ? 1 : 0

  name = var.config.aggregator_name
  type = "ORGANIZATION"
  tags = var.tags
}
