locals {
  tags = merge({
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Layer     = "compliance-config"
  }, var.tags)
}

# ── RMS Resource Recorder ─────────────────────────────────────────────────────

resource "huaweicloud_rms_resource_recorder" "org" {
  agency_name = "rms_recorder_agency"
  region      = var.home_region

  selector {
    all_supported = true
  }

  obs_channel {
    bucket = var.obs_recorder_bucket
    region = var.home_region
  }

  dynamic "smn_channel" {
    for_each = var.smn_topic_urn != "" ? [1] : []
    content {
      topic_urn = var.smn_topic_urn
      region    = var.home_region
    }
  }
}

# ── RMS Resource Aggregator ───────────────────────────────────────────────────

resource "huaweicloud_rms_resource_aggregator" "org" {
  name        = "lz-org-aggregator"
  type        = "ORGANIZATION"
  region      = var.home_region
}

resource "huaweicloud_rms_resource_aggregator_authorization" "members" {
  for_each = toset(var.aggregator_account_ids)

  aggregator_id = huaweicloud_rms_resource_aggregator.org.id
  account_id    = each.value
  region        = var.home_region
}

# ── Conformance Packs ─────────────────────────────────────────────────────────

resource "huaweicloud_rms_assignment_package" "packs" {
  for_each = { for p in var.conformance_packs : p.name => p }

  name         = each.value.name
  template_key = each.value.template_key
  region       = var.home_region
}

# ── Organizational Conformance Pack deployment ────────────────────────────────

resource "huaweicloud_rms_organizational_policy_assignment" "packs" {
  for_each = { for p in var.conformance_packs : p.name => p }

  organization_policy_assignment_name = "${each.value.name}-org"
  policy_assignment_id                = huaweicloud_rms_assignment_package.packs[each.key].id
  region                              = var.home_region
}

# ── Custom Detective Rules ────────────────────────────────────────────────────

resource "huaweicloud_rms_policy_assignment" "custom" {
  for_each = { for r in var.custom_rules : r.name => r }

  name        = each.value.name
  description = each.value.description
  region      = var.home_region

  policy_filter {
    policy_name = each.value.policy_name
  }

  dynamic "parameters" {
    for_each = each.value.parameters
    content {
      name  = parameters.key
      value = jsonencode(parameters.value)
    }
  }
}
