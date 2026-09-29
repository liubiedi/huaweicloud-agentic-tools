# --- Provider requirements ---

terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = { source = "huaweicloud/huaweicloud", version = "~> 1.87" }
  }
}

# --- Account audit tracker ---
# Note: OBS and LTS transfers are disabled for this tracker.

resource "huaweicloud_cts_tracker" "this" {
  enabled              = true
  organization_enabled = false
  # Note: Keep false to disable LTS transfer.
  lts_enabled = false
  # OBS transfer disabled

  tags = var.tags
}
