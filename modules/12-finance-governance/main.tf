locals {
  tag_policy_content = jsonencode({
    tags = {
      for tag in var.required_tags : tag.key => merge(
        { tag_key = { "@@assign" = tag.key } },
        length(tag.allowed_values) > 0 ? {
          tag_value = { "@@assign" = tag.allowed_values }
          enforced_for = { "@@assign" = ["huaweicloud:*:*"] }
        } : {}
      )
    }
  })
}

# ── Tag Policy ────────────────────────────────────────────────────────────────

resource "huaweicloud_organizations_policy" "required_tags" {
  name        = "lz-required-tags"
  description = "Enforce mandatory cost allocation tags on all resources"
  type        = "tag_policy"
  content     = local.tag_policy_content
}

resource "huaweicloud_organizations_policy_attach" "required_tags_root" {
  policy_id = huaweicloud_organizations_policy.required_tags.id
  entity_id = var.root_id
}

# ── Budget Alerts ─────────────────────────────────────────────────────────────

# Note: huaweicloud_bms_budget has limited provider support.
# Actual budget enforcement may require BSS API calls or console configuration.
# The resources below use whatever budget resource is available in the provider.

# ── RMS cost-governance detective rules ───────────────────────────────────────

resource "huaweicloud_rms_policy_assignment" "untagged_resources" {
  name        = "require-mandatory-tags"
  description = "Flag resources missing required cost allocation tags"
  region      = var.home_region

  policy_filter {
    policy_name = "required-tags"
  }

  parameters {
    name  = "tag1Key"
    value = jsonencode("Environment")
  }

  parameters {
    name  = "tag2Key"
    value = jsonencode("CostCenter")
  }

  parameters {
    name  = "tag3Key"
    value = jsonencode("Owner")
  }
}

resource "huaweicloud_rms_policy_assignment" "unattached_eips" {
  name        = "detect-unattached-eips"
  description = "Flag EIPs that are allocated but not associated — wasted spend"
  region      = var.home_region

  policy_filter {
    policy_name = "eip-attached"
  }
}

resource "huaweicloud_rms_policy_assignment" "unattached_evs" {
  name        = "detect-unattached-evs"
  description = "Flag EVS volumes that are available but not attached to any server"
  region      = var.home_region

  policy_filter {
    policy_name = "evs-volumes-attached"
  }
}
