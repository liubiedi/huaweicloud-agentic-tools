# Module 01 - organization and accounts
#
# Creates the organization from scratch: OUs, member accounts (each with its
# auto-created cross-account agency), the Identity Center instance, trusted
# services and delegated admins, plus an optional tag policy and a bootstrap
# enterprise project. Everything else depends on this module, so it applies
# first.

# ---- Common locals ----

locals {

  # OUs split by level: top-level (parent is the root) vs child (parent is a
  # top-level OU).
  ou_top   = { for k, v in var.organizational_units : k => v if contains(["", "root"], v.parent) }
  ou_child = { for k, v in var.organizational_units : k => v if !contains(["", "root"], v.parent) }

  # OU name -> ID, for placing accounts. "" or "root" means the org root.
  ou_id_for = merge(
    {
      ""     = huaweicloud_organizations_organization.this.root_id
      "root" = huaweicloud_organizations_organization.this.root_id
    },
    { for k, v in huaweicloud_organizations_organizational_unit.this : k => v.id },
    { for k, v in huaweicloud_organizations_organizational_unit.child : k => v.id },
  )

  # Account name -> ID, for delegated administrators.
  account_id_for = merge(
    { for k, v in huaweicloud_organizations_account.core : k => v.id },
    { for k, v in huaweicloud_organizations_account.workload : k => v.id },
  )
}

# ---- Organization ----

resource "huaweicloud_organizations_organization" "this" {
  enabled_policy_types = var.enabled_policy_types
}

# OUs, up to two levels (root -> top -> child). A for_each resource cannot
# reference its own instances to resolve parents, so top-level and child OUs
# are separate resources. Deeper nesting is rejected by the workbook parser.

resource "huaweicloud_organizations_organizational_unit" "this" {
  for_each = local.ou_top

  name      = each.key
  parent_id = huaweicloud_organizations_organization.this.root_id
}

resource "huaweicloud_organizations_organizational_unit" "child" {
  for_each = local.ou_child

  name      = each.key
  parent_id = huaweicloud_organizations_organizational_unit.this[each.value.parent].id
}

# Member accounts. Setting agency_name makes Huawei create the trust agency
# inside each new account automatically, so the master can assume into it
# right away.

resource "huaweicloud_organizations_account" "core" {
  for_each = var.core_accounts

  name        = each.key
  email       = each.value.email
  description = each.value.description
  parent_id   = local.ou_id_for[each.value.ou]
  agency_name = var.cross_account_agency_name
}

resource "huaweicloud_organizations_account" "workload" {
  for_each = var.workload_accounts

  name        = each.key
  email       = each.value.email
  description = each.value.description
  parent_id   = local.ou_id_for[each.value.ou]
  agency_name = var.cross_account_agency_name
}

# ---- Identity Center ----

# The home region must be registered before the service can start, or the
# start fails with IIC.1214 "Region not registered". Neither step references
# the other's attributes, so the ordering is spelled out with depends_on.
resource "huaweicloud_identitycenter_registered_region" "this" {
  region_id = var.home_region

  depends_on = [huaweicloud_organizations_organization.this]
}

resource "huaweicloud_identitycenter_instance" "this" {
  alias = var.identity_center_alias != "" ? var.identity_center_alias : null

  depends_on = [
    huaweicloud_organizations_organization.this,
    huaweicloud_identitycenter_registered_region.this,
  ]
}

# ---- Trusted services ----

resource "huaweicloud_organizations_trusted_service" "this" {
  for_each = toset(var.trusted_services)

  service = each.value

  depends_on = [huaweicloud_organizations_organization.this]
}

# Delegated administrators (optional). Key is the service principal, which
# must also be a trusted service; value is the account name.

resource "huaweicloud_organizations_delegated_administrator" "this" {
  for_each = var.delegated_administrators

  service_principal = each.key
  account_id        = local.account_id_for[each.value]

  depends_on = [huaweicloud_organizations_trusted_service.this]
}

# Tag policies (optional). Needs "tag_policy" in enabled_policy_types.

resource "huaweicloud_organizations_policy" "custom_tag" {
  for_each = { for p in var.tag_policies : p.name => p }

  name        = each.value.name
  description = each.value.description
  type        = "tag_policy"
  content     = each.value.content

  depends_on = [huaweicloud_organizations_organization.this]
}

resource "huaweicloud_organizations_policy_attach" "custom_tag" {
  for_each = huaweicloud_organizations_policy.custom_tag

  policy_id = each.value.id
  entity_id = huaweicloud_organizations_organization.this.root_id
}

# Bootstrap enterprise project (optional). 08-financial creates the real
# cost-center projects later; this is just the starter one for the master
# account.

# Grants the EPS capability to the master account. Takes no arguments, and
# deleting it does not revoke the grant.
resource "huaweicloud_enterprise_project_authority" "this" {
  count = var.create_enterprise_project ? 1 : 0
}

resource "huaweicloud_enterprise_project" "bootstrap" {
  count = var.create_enterprise_project ? 1 : 0

  name        = var.enterprise_project_name
  description = "Landing zone bootstrap enterprise project"

  depends_on = [huaweicloud_enterprise_project_authority.this]
}
