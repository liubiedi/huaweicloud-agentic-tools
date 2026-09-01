locals {
  # Expand predefined_tags into individual (key, value) pairs.
  # For tags with no defined values, emit a single (key, "*") pair.
  predefined_tag_pairs = flatten([
    for t in var.predefined_tags : (
      length(t.values) > 0 ?
      [for v in t.values : { key = t.key, value = v }] :
      [{ key = t.key, value = "*" }]
    )
  ])
}

# ---- Multi-EP ----
# This module is called once per target account (cost-center fan-out), so the
# EPS authority is granted in each account before its enterprise projects are
# created. No-args; deleting it does NOT revoke the grant.

resource "huaweicloud_enterprise_project_authority" "this" {
  count = var.enable_multi_ep ? 1 : 0
}

# The authority grant propagates asynchronously; sleep once when the grant
# is first created.
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

# ---- TMS predefined tags (one resource holds the entire tag dictionary) ----

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

# ---- TMS bulk resource tagging ----

resource "huaweicloud_tms_resource_tags" "bulk" {
  for_each = var.enable_bulk_tag_resources ? { for idx, t in var.bulk_tag_targets : tostring(idx) => t } : {}

  project_id = each.value.project_id
  tags       = each.value.tags # tags is a map attribute, not a block

  dynamic "resources" {
    for_each = each.value.resources
    content {
      resource_id   = resources.value.resource_id
      resource_type = resources.value.resource_type
    }
  }
}
