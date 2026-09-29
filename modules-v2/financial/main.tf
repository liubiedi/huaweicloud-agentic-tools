# --- Provider requirements ---

terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = { source = "huaweicloud/huaweicloud", version = "~> 1.87" }
    time        = { source = "hashicorp/time", version = ">= 0.9" }
  }
}

locals {
  # Predefined tag pairs
  predefined_tag_pairs = flatten([
    for t in var.predefined_tags : (
      length(t.values) > 0 ?
      [for v in t.values : { key = t.key, value = v }] :
      [{ key = t.key, value = "*" }]
    )
  ])
}

# --- Enterprise project authorization ---
# Note: Removing the resource does not revoke the authorization grant.

resource "huaweicloud_enterprise_project_authority" "this" {
  count = var.enable_multi_ep ? 1 : 0
}

# --- Authorization propagation wait ---
resource "time_sleep" "eps_authority_propagation" {
  count = var.enable_multi_ep ? 1 : 0

  create_duration = "60s"

  triggers = {
    authority_id = huaweicloud_enterprise_project_authority.this[0].id
  }
}

resource "huaweicloud_enterprise_project" "cost_centers" {
  for_each = var.enable_multi_ep ? var.cost_centers : {}

  name        = each.key
  description = each.value.description
  type        = each.value.enterprise_project_type

  depends_on = [time_sleep.eps_authority_propagation]
}

# --- Predefined tag dictionary ---

resource "huaweicloud_tms_tags" "predefined" {
  count = var.enable_predefined_tags && length(local.predefined_tag_pairs) > 0 ? 1 : 0

  dynamic "tags" {
    for_each = local.predefined_tag_pairs
    content {
      key   = tags.value.key
      value = tags.value.value
    }
  }
}

# --- Bulk resource tagging ---

resource "huaweicloud_tms_resource_tags" "bulk" {
  for_each = var.enable_bulk_tag_resources ? { for idx, t in var.bulk_tag_targets : tostring(idx) => t } : {}

  project_id = each.value.project_id
  # Resource tag map
  tags = each.value.tags

  dynamic "resources" {
    for_each = each.value.resources
    content {
      resource_id   = resources.value.resource_id
      resource_type = resources.value.resource_type
    }
  }
}
