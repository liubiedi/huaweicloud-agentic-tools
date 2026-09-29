# --- Provider requirements ---

terraform {
  required_version = ">= 1.6.3"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.87"
    }
  }
}

# --- Identity configuration ---

# --- Identity module components ---
# Note: Content is in identity-center.tf; account policies are in iam-baseline.generated.tf.

# --- Identity Center input validation ---
check "ic_inputs_provided" {
  assert {
    condition     = !var.enable_identity_center_content || (var.identity_store_id != "" && var.identity_center_instance_id != "")
    error_message = "enable_identity_center_content = true requires identity_store_id and identity_center_instance_id (from module 1 outputs)."
  }
}
