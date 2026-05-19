# ── Password policy ───────────────────────────────────────────────────────────

resource "huaweicloud_identity_password_policy" "this" {
  password_char_combination   = 4
  minimum_password_length     = var.password_min_length
  number_of_recent_passwords  = 5
  password_validity_period    = var.password_max_age
  password_not_username_or_invert = true
}

# ── Login policy ──────────────────────────────────────────────────────────────

resource "huaweicloud_identity_login_policy" "this" {
  account_validity_period     = 0
  custom_info_for_login       = ""
  lockout_duration            = 30
  login_failed_times          = 5
  period_with_login_failures  = 15
  session_timeout             = var.session_timeout
  show_recent_login_info      = true
}

# ── Protection policy (operation protection) ──────────────────────────────────

resource "huaweicloud_identity_protection_policy" "this" {
  enable_operation_protection_policy = true
}

# ── Console ACL (IP allowlist) ────────────────────────────────────────────────

resource "huaweicloud_identity_acl" "console" {
  count = length(var.allowed_ip_ranges) > 0 ? 1 : 0

  type = "console"

  dynamic "ip_ranges" {
    for_each = var.allowed_ip_ranges
    content {
      ip_range    = ip_ranges.value
      description = "LZ approved IP range"
    }
  }
}

# ── Break-glass emergency admin group ────────────────────────────────────────

resource "huaweicloud_identity_group" "break_glass" {
  name        = "lz-break-glass"
  description = "Emergency break-glass group — tightly monitored, no standing assignments"
}

resource "huaweicloud_identity_group_role_assignment" "break_glass_admin" {
  group_id   = huaweicloud_identity_group.break_glass.id
  role_id    = data.huaweicloud_identity_role.tenant_admin.id
  project_id = "all"
}

data "huaweicloud_identity_role" "tenant_admin" {
  name = "te_admin"
}

# ── OrganizationAccountAccessAgency ──────────────────────────────────────────
# This agency is created by RGC in every member account, but we re-declare it
# here for accounts not managed by RGC so the provider assume_role blocks work.

resource "huaweicloud_identity_agency" "org_access" {
  name                  = "OrganizationAccountAccessAgency"
  description           = "Allows the master account to assume roles in this account"
  delegated_domain_name = "op_service"

  all_resources_roles = ["FullAccess"]
}

# ── Custom cross-account agencies ─────────────────────────────────────────────

resource "huaweicloud_identity_agency" "custom" {
  for_each = { for a in var.cross_account_agencies : a.name => a }

  name                  = each.value.name
  description           = each.value.description
  delegated_domain_name = each.value.trust_domain != "" ? each.value.trust_domain : null
  delegated_service     = length(each.value.trust_services) > 0 ? each.value.trust_services[0] : null

  dynamic "all_resources_roles" {
    for_each = each.value.policy_names
    content {
      service = all_resources_roles.value
    }
  }
}

# ── Terraform automation agency ───────────────────────────────────────────────

resource "huaweicloud_identity_agency" "terraform_automation" {
  name                  = "lz-terraform-automation"
  description           = "Agency assumed by CI/CD pipeline Terraform runs"
  delegated_domain_name = "op_service"

  all_resources_roles = ["FullAccess"]
}
