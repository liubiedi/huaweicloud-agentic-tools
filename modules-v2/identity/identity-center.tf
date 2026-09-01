# Identity Center workforce content.
#
# Gated by var.enable_identity_center_content. Some argument names differ
# from the Huawei docs; trust the provider schema.

locals {
  ic_enabled = var.enable_identity_center_content

  # Callers may pass null for these (no groups/users configured); coalesce so
  # the for-expressions below never iterate a null value.
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

  # All unique system-policy display names referenced by the permission sets.
  # Sheet holds friendly names ("BSS Administrator"); the IC attach-managed-role
  # API needs the policy ID, so we resolve name -> id via a data source below.
  all_system_policy_names = local.ic_enabled ? toset(flatten([
    for ps_name, ps in var.permission_sets : ps.system_policies
  ])) : toset([])

  # name -> policy ID (exact-name match from the IAM permissions catalog).
  system_policy_id = {
    for name in local.all_system_policy_names :
    name => one([
      for p in data.huaweicloud_identity_permissions.system[name].permissions : p.id
      if p.name == name
    ])
  }

  # PS -> list of system policy IDs (one attachment per PS holds the SET)
  ps_to_system_policies = local.ic_enabled ? {
    for ps_name, ps in var.permission_sets :
    ps_name => [for n in ps.system_policies : local.system_policy_id[n]]
    if length(ps.system_policies) > 0
  } : {}

  ps_to_v5_policies = local.ic_enabled ? {
    for ps_name, ps in var.permission_sets : ps_name => ps.system_identity_policies
    if length(ps.system_identity_policies) > 0
  } : {}
}

# Resolve each system-policy display name to its IAM policy ID.
data "huaweicloud_identity_permissions" "system" {
  for_each = local.all_system_policy_names

  name = each.value
  type = "system"
}

# ---- Groups ----

resource "huaweicloud_identitycenter_group" "this" {
  for_each = local.ic_enabled ? { for g in local._groups : g.name => g } : {}

  identity_store_id = var.identity_store_id
  name              = each.value.name
  description       = each.value.description
}

# ---- Users ----
#
# In the provider schema, family_name, given_name, email, password_mode are
# top-level Required args (NOT nested in name/emails blocks).

resource "huaweicloud_identitycenter_user" "this" {
  for_each = local.ic_enabled ? { for u in local._users : u.user_name => u } : {}

  identity_store_id = var.identity_store_id
  user_name         = each.value.user_name
  display_name      = each.value.display_name
  family_name       = each.value.family_name
  given_name        = each.value.given_name
  email             = each.value.email
  password_mode     = "EMAIL" # send password setup email to user
}

# ---- Group memberships ----

resource "huaweicloud_identitycenter_group_membership" "this" {
  for_each = local.ic_enabled ? { for m in local.group_memberships : m.key => m } : {}

  identity_store_id = var.identity_store_id
  group_id          = huaweicloud_identitycenter_group.this[each.value.group].id
  member_id         = huaweicloud_identitycenter_user.this[each.value.user_name].id
}

# ---- Permission sets ----

resource "huaweicloud_identitycenter_permission_set" "this" {
  for_each = local.ic_enabled ? var.permission_sets : {}

  instance_id      = var.identity_center_instance_id
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session_duration
}

# System (v2012) policy attachments - one resource per PS, holds a SET of policy IDs
resource "huaweicloud_identitycenter_system_policy_attachment" "this" {
  for_each = local.ic_enabled ? local.ps_to_system_policies : {}

  instance_id       = var.identity_center_instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.this[each.key].id
  policy_ids        = each.value
}

# System identity (v5) policy attachments
resource "huaweicloud_identitycenter_system_identity_policy_attachment" "this" {
  for_each = local.ic_enabled ? local.ps_to_v5_policies : {}

  instance_id       = var.identity_center_instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.this[each.key].id
  policy_ids        = each.value
}

# ---- Account assignments ----

resource "huaweicloud_identitycenter_account_assignment" "this" {
  for_each = local.ic_enabled ? {
    for a in var.account_assignments :
    "${a.account_id}__${a.group_name}__${a.permission_set}" => a
  } : {}

  instance_id       = var.identity_center_instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.this[each.value.permission_set].id
  principal_id      = huaweicloud_identitycenter_group.this[each.value.group_name].id
  principal_type    = "GROUP"
  target_id         = each.value.account_id
  target_type       = "ACCOUNT"
}

# ---- Permission set provisioning (push PS to target account) ----
# One resource per (account, PS) pair.

resource "huaweicloud_identitycenter_provision_permission_set" "this" {
  for_each = local.ic_enabled ? {
    for a in var.account_assignments :
    "${a.account_id}__${a.permission_set}" => a
    # Dedupe in case multiple groups bind to the same PS in the same account
  } : {}

  instance_id       = var.identity_center_instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.this[each.value.permission_set].id
  account_id        = each.value.account_id

  depends_on = [huaweicloud_identitycenter_account_assignment.this]
}

# ---- IC password policy ----

resource "huaweicloud_identitycenter_password_policy" "this" {
  count = local.ic_enabled ? 1 : 0

  identity_store_id            = var.identity_store_id
  minimum_password_length      = lookup(var.ic_password_policy, "min_password_length", 12)
  max_password_age             = lookup(var.ic_password_policy, "password_max_age_days", 90)
  password_reuse_prevention    = lookup(var.ic_password_policy, "password_reuse_prevention", 1) # IC max is 1
  require_uppercase_characters = lookup(var.ic_password_policy, "require_uppercase", true)
  require_lowercase_characters = lookup(var.ic_password_policy, "require_lowercase", true)
  require_numbers              = lookup(var.ic_password_policy, "require_numbers", true)
  require_symbols              = lookup(var.ic_password_policy, "require_symbols", true)
}

# ---- IC MFA management ----

resource "huaweicloud_identitycenter_mfa_management_setting" "this" {
  count = local.ic_enabled ? 1 : 0

  instance_id       = var.identity_center_instance_id
  identity_store_id = var.identity_store_id
  # Valid values: READ_ACTIONS | ALL_ACTIONS (controls users' MFA self-management).
  user_permission = lookup(var.ic_mfa_management, "user_permission", "ALL_ACTIONS")
}

# ---- IC registered regions ----
# Region registration is owned by module 1 (it must run before the IC instance
# starts). Registering it again here conflicts ("already registered"), so it is
# intentionally not managed in this module.
