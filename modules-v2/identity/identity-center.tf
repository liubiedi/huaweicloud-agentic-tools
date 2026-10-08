# --- Identity Center content ---

locals {
  ic_enabled = var.enable_identity_center_content

  # Identity input defaults
  _groups = var.groups == null ? [] : var.groups
  _users  = var.users == null ? [] : var.users

  group_memberships = local.ic_enabled ? flatten([
    for u in local._users : [
      for g in u.group_names : {
        key       = "${u.user_name}__${g}"
        user_name = u.user_name
        group     = g
      }
    ]
  ]) : []

  # System policy names
  all_system_policy_names = local.ic_enabled ? toset(flatten([
    for ps_name, ps in var.permission_sets : ps.system_policies
  ])) : toset([])

  # System policy ID lookup
  system_policy_id = {
    for name in local.all_system_policy_names :
    name => one([
      for p in data.huaweicloud_identity_permissions.system[name].permissions : p.id
      if p.name == name
    ])
  }

  # Permission-set policy mappings
  ps_to_system_policies = local.ic_enabled ? {
    for ps_name, ps in var.permission_sets :
    ps_name => [for n in ps.system_policies : local.system_policy_id[n]]
    if length(ps.system_policies) > 0
  } : {}

  ps_to_v5_policies = local.ic_enabled ? {
    for ps_name, ps in var.permission_sets : ps_name => ps.system_identity_policies
    if length(ps.system_identity_policies) > 0
  } : {}

  ps_to_custom_policy = local.ic_enabled ? {
    for ps_name, ps in var.permission_sets : ps_name => ps.custom_policy
    if ps.custom_policy != null
  } : {}

  # Principal lookup: groups created here, plus every group and user in the identity store
  assignments_enabled = local.ic_enabled && length(var.account_assignments) > 0
  group_id = merge(
    { for g in try(data.huaweicloud_identitycenter_groups.all[0].groups, []) : g.name => g.id },
    { for k, g in huaweicloud_identitycenter_group.this : k => g.id },
  )
  user_id = merge(
    { for u in try(data.huaweicloud_identitycenter_users.all[0].users, []) : u.user_name => u.id },
    { for k, u in huaweicloud_identitycenter_user.this : k => u.id },
  )

  assignments = {
    for a in var.account_assignments :
    "${a.account}__${coalesce(a.group, a.user)}__${a.permission_set}" => a
  }
}

# --- Identity store directory ---
data "huaweicloud_identitycenter_groups" "all" {
  count = local.assignments_enabled ? 1 : 0

  identity_store_id = var.identity_store_id
}

data "huaweicloud_identitycenter_users" "all" {
  count = local.assignments_enabled ? 1 : 0

  identity_store_id = var.identity_store_id
}

# --- IAM policy catalog ---
data "huaweicloud_identity_permissions" "system" {
  for_each = local.all_system_policy_names

  name = each.value
  type = "system"
}

# --- Identity groups ---

resource "huaweicloud_identitycenter_group" "this" {
  for_each = local.ic_enabled ? { for g in local._groups : g.name => g } : {}

  identity_store_id = var.identity_store_id
  name              = each.value.name
  description       = each.value.description
}

# --- Identity users ---

resource "huaweicloud_identitycenter_user" "this" {
  for_each = local.ic_enabled ? { for u in local._users : u.user_name => u } : {}

  identity_store_id = var.identity_store_id
  user_name         = each.value.user_name
  display_name      = each.value.display_name
  family_name       = each.value.family_name
  given_name        = each.value.given_name
  email             = each.value.email
  # Password setup delivery
  password_mode = "EMAIL"
}

# --- Group memberships ---

resource "huaweicloud_identitycenter_group_membership" "this" {
  for_each = local.ic_enabled ? { for m in local.group_memberships : m.key => m } : {}

  identity_store_id = var.identity_store_id
  group_id          = huaweicloud_identitycenter_group.this[each.value.group].id
  member_id         = huaweicloud_identitycenter_user.this[each.value.user_name].id
}

# --- Permission sets ---

resource "huaweicloud_identitycenter_permission_set" "this" {
  for_each = local.ic_enabled ? var.permission_sets : {}

  instance_id      = var.identity_center_instance_id
  name             = each.key
  description      = each.value.description
  session_duration = coalesce(each.value.session_duration, var.session_duration)
}

# --- System policy attachments ---
resource "huaweicloud_identitycenter_system_policy_attachment" "this" {
  for_each = local.ic_enabled ? local.ps_to_system_policies : {}

  instance_id       = var.identity_center_instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.this[each.key].id
  policy_ids        = each.value
}

# --- Identity policy attachments ---
resource "huaweicloud_identitycenter_system_identity_policy_attachment" "this" {
  for_each = local.ic_enabled ? local.ps_to_v5_policies : {}

  instance_id       = var.identity_center_instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.this[each.key].id
  policy_ids        = each.value
}

# --- Custom policy attachments ---
resource "huaweicloud_identitycenter_custom_policy_attachment" "this" {
  for_each = local.ps_to_custom_policy

  instance_id       = var.identity_center_instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.this[each.key].id
  custom_policy     = each.value
}

# --- Account assignments ---

resource "huaweicloud_identitycenter_account_assignment" "this" {
  for_each = local.ic_enabled ? local.assignments : {}

  instance_id       = var.identity_center_instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.this[each.value.permission_set].id
  principal_id      = each.value.group != null ? local.group_id[each.value.group] : local.user_id[each.value.user]
  principal_type    = each.value.group != null ? "GROUP" : "USER"
  target_id         = var.account_ids[each.value.account]
  target_type       = "ACCOUNT"

  # Note: The provider does not read target_type back, so an imported assignment would otherwise be replaced.
  lifecycle {
    ignore_changes = [target_type]
  }
}

# --- Permission-set provisioning ---

# Note: One provisioning per account and permission set, however many principals share it.
resource "huaweicloud_identitycenter_provision_permission_set" "this" {
  for_each = local.ic_enabled ? {
    for pair in distinct([
      for a in var.account_assignments : {
        account        = a.account
        permission_set = a.permission_set
      }
    ]) :
    "${pair.account}__${pair.permission_set}" => pair
  } : {}

  instance_id       = var.identity_center_instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.this[each.value.permission_set].id
  account_id        = var.account_ids[each.value.account]

  depends_on = [huaweicloud_identitycenter_account_assignment.this]
}

# --- Identity Center password policy ---

resource "huaweicloud_identitycenter_password_policy" "this" {
  count = local.ic_enabled ? 1 : 0

  identity_store_id       = var.identity_store_id
  minimum_password_length = lookup(var.ic_password_policy, "min_password_length", 12)
  max_password_age        = lookup(var.ic_password_policy, "password_max_age_days", 90)
  # Note: Identity Center allows a maximum of 1.
  password_reuse_prevention    = lookup(var.ic_password_policy, "password_reuse_prevention", 1)
  require_uppercase_characters = lookup(var.ic_password_policy, "require_uppercase", true)
  require_lowercase_characters = lookup(var.ic_password_policy, "require_lowercase", true)
  require_numbers              = lookup(var.ic_password_policy, "require_numbers", true)
  require_symbols              = lookup(var.ic_password_policy, "require_symbols", true)
}

# --- Identity Center MFA policy ---

resource "huaweicloud_identitycenter_mfa_management_setting" "this" {
  count = local.ic_enabled ? 1 : 0

  instance_id       = var.identity_center_instance_id
  identity_store_id = var.identity_store_id
  # MFA self-management scope
  user_permission = lookup(var.ic_mfa_management, "user_permission", "ALL_ACTIONS")
}

# --- Region registration ownership ---
# Note: 01-foundation registers regions before starting Identity Center.
