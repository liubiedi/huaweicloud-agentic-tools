# --- Account IAM baseline ---

locals {
  iam_enabled = var.enable_iam_baseline

  # Service agency defaults
  _service_agencies = var.service_agencies == null ? [] : var.service_agencies
}

# --- Password policy ---

resource "huaweicloud_identity_password_policy" "this" {
  count = local.iam_enabled ? 1 : 0

  minimum_password_length               = var.iam_password_policy.minimum_password_length
  password_validity_period              = var.iam_password_policy.maximum_password_age
  number_of_recent_passwords_disallowed = var.iam_password_policy.password_reuse_prevention
  minimum_password_age                  = var.iam_password_policy.minimum_password_age
  password_char_combination             = var.iam_password_policy.password_char_combination
  maximum_consecutive_identical_chars   = var.iam_password_policy.maximum_consecutive_identical_chars
  password_not_username_or_invert       = var.iam_password_policy.password_not_username_or_invert
}

# --- Login policy ---

resource "huaweicloud_identity_login_policy" "this" {
  count = local.iam_enabled ? 1 : 0

  account_validity_period    = var.iam_login_policy.account_validity_period
  custom_info_for_login      = var.iam_login_policy.custom_info_for_login
  lockout_duration           = var.iam_login_policy.lockout_duration
  login_failed_times         = var.iam_login_policy.login_failed_times
  period_with_login_failures = var.iam_login_policy.period_with_login_failures
  session_timeout            = var.iam_login_policy.session_timeout
  show_recent_login_info     = var.iam_login_policy.show_recent_login_info
}

# --- Operation protection policy ---

resource "huaweicloud_identity_protection_policy" "this" {
  count = local.iam_enabled ? 1 : 0

  protection_enabled = var.iam_protection_policy.operation_protection

  self_management {
    access_key = var.iam_protection_policy.self_management
    password   = var.iam_protection_policy.self_management
    mobile     = var.iam_protection_policy.self_management
    email      = var.iam_protection_policy.self_management
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
