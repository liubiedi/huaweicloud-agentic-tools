# --- Account predefined tags ---

locals {
  # Tag key-value pairs
  # Note: Skip keys without explicit values; TMS rejects wildcard values.
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
