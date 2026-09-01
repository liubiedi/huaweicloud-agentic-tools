# Per-account IAM baseline: password/login/protection policies plus service
# agencies.

locals {
  iam_enabled = var.enable_iam_baseline

  # Caller may pass null (no service agencies configured) - coalesce so the
  # for-expression never iterates a null value.
  _service_agencies = var.service_agencies == null ? [] : var.service_agencies
}

# ---- Password policy (v3) ----
#
# Schema: maximum_consecutive_identical_chars, minimum_password_age,
# minimum_password_length, number_of_recent_passwords_disallowed,
# password_not_username_or_invert, password_validity_period,
# password_char_combination.

resource "huaweicloud_identity_password_policy" "this" {
  count = local.iam_enabled ? 1 : 0

  minimum_password_length               = lookup(var.iam_password_policy, "minimum_password_length", 12)
  password_validity_period              = lookup(var.iam_password_policy, "password_validity_period", 90)
  number_of_recent_passwords_disallowed = lookup(var.iam_password_policy, "password_reuse_prevention", 1)
  minimum_password_age                  = lookup(var.iam_password_policy, "minimum_password_age", 0)
  password_char_combination             = lookup(var.iam_password_policy, "password_char_combination", 2)
  maximum_consecutive_identical_chars   = lookup(var.iam_password_policy, "maximum_consecutive_identical_chars", 0)
  password_not_username_or_invert       = lookup(var.iam_password_policy, "password_not_username_or_invert", true)
}

# ---- Login policy ----

resource "huaweicloud_identity_login_policy" "this" {
  count = local.iam_enabled ? 1 : 0

  account_validity_period    = lookup(var.iam_login_policy, "account_validity_period", 0)
  custom_info_for_login      = lookup(var.iam_login_policy, "custom_info_for_login", "")
  lockout_duration           = lookup(var.iam_login_policy, "lockout_duration", 15)
  login_failed_times         = lookup(var.iam_login_policy, "login_failed_times", 5)
  period_with_login_failures = lookup(var.iam_login_policy, "period_with_login_failures", 15)
  session_timeout            = lookup(var.iam_login_policy, "session_timeout", 60)
  show_recent_login_info     = lookup(var.iam_login_policy, "show_recent_login_info", true)
}

# ---- Protection policy ----
#
# Schema:
#   protection_enabled (Required, Bool)
#   verification_mobile (Optional, String)
#   verification_email (Optional, String)
#   self_management (Optional, Block - list with MaxItems=1)
#     access_key, password, mobile, email (all Optional Bool)

resource "huaweicloud_identity_protection_policy" "this" {
  count = local.iam_enabled ? 1 : 0

  protection_enabled = lookup(var.iam_protection_policy, "operation_protection", true)

  self_management {
    access_key = lookup(var.iam_protection_policy, "self_management", true)
    password   = lookup(var.iam_protection_policy, "self_management", true)
    mobile     = lookup(var.iam_protection_policy, "self_management", true)
    email      = lookup(var.iam_protection_policy, "self_management", true)
  }
}

# ---- Service agencies ----
#
# Schema for huaweicloud_identity_agency: name, description, delegated_service_name,
# duration, all_resources_roles (Optional Set), project_role (Optional list of blocks).
# all_resources_roles is a Set of strings (role names), NOT a block.
# project_role is a list of blocks { project, roles }.

resource "huaweicloud_identity_agency" "this" {
  for_each = local.iam_enabled ? { for a in local._service_agencies : a.name => a } : {}

  name                   = each.value.name
  description            = each.value.description
  delegated_service_name = each.value.delegated_service
  duration               = each.value.duration

  all_resources_roles = each.value.all_resources ? each.value.policies : null

  dynamic "project_role" {
    for_each = each.value.all_resources ? [] : [1]
    content {
      project = each.value.project_name
      roles   = each.value.policies
    }
  }
}
