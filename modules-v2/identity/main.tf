# Module 2 - identity and permission management
#
# Two halves, each gated by an enable_* flag. Env layer typically calls
# this module twice:
#   1. Once in master account with enable_identity_center_content = true
#      -> creates IC users/groups/permission sets/account assignments
#   2. Per-account (via provider alias) with enable_iam_baseline = true
#      -> creates v3 IAM baseline (password/login/protection) + agencies
#
# A single call with both flags set is supported (e.g., for the master
# account itself), though that's atypical.

# Identity Center content + IAM baseline live in identity-center.tf and
# iam-baseline.tf respectively. This file holds only locals + validations.

# Validation: when enable_identity_center_content = true, identity_store_id
# and identity_center_instance_id must be set.
check "ic_inputs_provided" {
  assert {
    condition     = !var.enable_identity_center_content || (var.identity_store_id != "" && var.identity_center_instance_id != "")
    error_message = "enable_identity_center_content = true requires identity_store_id and identity_center_instance_id (from module 1 outputs)."
  }
}
