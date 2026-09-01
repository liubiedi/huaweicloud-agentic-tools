# TMS predefined-tag dictionary (per account).
#
# This module is org-level for SCPs (master account), but the predefined-tag
# dictionary is account-scoped. The env composition invokes this module once
# per account (via a generated provider alias) with enable_scps = false and
# enable_predefined_tags = true - so only the tag dictionary below is created
# in each member account.

locals {
  # Expand predefined_tags into individual (key, value) pairs.
  # TMS predefined tags are key+value entries; a value of "*" is rejected
  # (TMS.0010 Value is invalid). Free-form keys (no enumerated values) therefore
  # have nothing to predefine and are skipped - users still type any value at
  # tag time. Only keys WITH explicit values produce dictionary entries.
  predefined_tag_pairs = flatten([
    for t in var.predefined_tags :
    [for v in t.values : { key = t.key, value = v }]
  ])
}

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
