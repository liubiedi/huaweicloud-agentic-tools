data "huaweicloud_identitycenter_instance" "this" {}

locals {
  instance_id = var.instance_id != "" ? var.instance_id : data.huaweicloud_identitycenter_instance.this.id
  identity_store_id = data.huaweicloud_identitycenter_instance.this.identity_store_id

  standard_permission_sets = {
    LzAdministrator = {
      description     = "Full administrative access to all services"
      session_duration = var.session_duration
      managed_policies = ["FullAccess"]
    }
    LzDeveloper = {
      description     = "Developer access — compute, storage, databases. No IAM write."
      session_duration = var.session_duration
      managed_policies = ["Tenant Guest", "Server Administrator"]
    }
    LzSecurityAuditor = {
      description     = "Read-only access to security services and logs"
      session_duration = var.session_duration
      managed_policies = ["Security Administrator"]
    }
    LzBillingViewer = {
      description     = "Billing and cost management read-only"
      session_duration = var.session_duration
      managed_policies = ["BSS Administrator"]
    }
    LzReadOnly = {
      description     = "Read-only access to all resources"
      session_duration = var.session_duration
      managed_policies = ["Tenant Guest"]
    }
  }
}

# ── Groups ────────────────────────────────────────────────────────────────────

resource "huaweicloud_identitycenter_group" "groups" {
  for_each = { for g in var.groups : g.name => g }

  identity_store_id = local.identity_store_id
  name              = each.value.name
  description       = each.value.description
}

# ── Users ─────────────────────────────────────────────────────────────────────

resource "huaweicloud_identitycenter_user" "users" {
  for_each = { for u in var.users : u.user_name => u }

  identity_store_id = local.identity_store_id
  user_name         = each.value.user_name
  display_name      = each.value.display_name

  name {
    family_name = each.value.family_name
    given_name  = each.value.given_name
  }

  emails {
    value   = each.value.email
    primary = true
  }
}

resource "huaweicloud_identitycenter_group_membership" "user_memberships" {
  for_each = {
    for pair in flatten([
      for u in var.users : [
        for g in u.group_names : {
          key      = "${u.user_name}__${g}"
          user_id  = huaweicloud_identitycenter_user.users[u.user_name].id
          group_id = huaweicloud_identitycenter_group.groups[g].id
        }
      ]
    ]) : pair.key => pair
  }

  identity_store_id = local.identity_store_id
  group_id          = each.value.group_id
  member_id         = each.value.user_id
}

# ── Standard permission sets ──────────────────────────────────────────────────

resource "huaweicloud_identitycenter_permission_set" "standard" {
  for_each = local.standard_permission_sets

  instance_id      = local.instance_id
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session_duration
}

resource "huaweicloud_identitycenter_permission_set_customer_policy_attachment" "standard" {
  for_each = {
    for pair in flatten([
      for ps_name, ps in local.standard_permission_sets : [
        for policy in ps.managed_policies : {
          key              = "${ps_name}__${policy}"
          permission_set   = ps_name
          policy_name      = policy
        }
      ]
    ]) : pair.key => pair
  }

  instance_id       = local.instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.standard[each.value.permission_set].id
  policy_document   = each.value.policy_name
}

resource "huaweicloud_identitycenter_provisioned_permission_set" "standard" {
  for_each = local.standard_permission_sets

  instance_id       = local.instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.standard[each.key].id
  target_type       = "AWS_ACCOUNT"
}

# ── Account assignments ───────────────────────────────────────────────────────

resource "huaweicloud_identitycenter_account_assignment" "assignments" {
  for_each = {
    for a in var.account_assignments :
    "${a.account_id}__${a.group_name}__${a.permission_set}" => a
  }

  instance_id       = local.instance_id
  permission_set_id = huaweicloud_identitycenter_permission_set.standard[each.value.permission_set].id
  principal_id      = huaweicloud_identitycenter_group.groups[each.value.group_name].id
  principal_type    = "GROUP"
  target_id         = each.value.account_id
  target_type       = "AWS_ACCOUNT"
}
