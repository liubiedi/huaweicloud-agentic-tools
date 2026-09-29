# --- Account IAM baseline ---

locals {
  iam_enabled = var.enable_iam_baseline

  # Service agency defaults
  _service_agencies = var.service_agencies == null ? [] : var.service_agencies
}

# --- Password policy ---

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

# --- Login policy ---

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

# --- Operation protection policy ---

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

# --- Service agencies ---

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
