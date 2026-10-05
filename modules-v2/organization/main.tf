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

# --- Organization mappings ---

locals {

  # Organizational units by level
  ou_top   = { for k, v in var.organizational_units : k => v if contains(["", "root"], v.parent) }
  ou_child = { for k, v in var.organizational_units : k => v if !contains(["", "root"], v.parent) }

  # OU name-to-ID map
  ou_id_for = merge(
    {
      ""     = huaweicloud_organizations_organization.this.root_id
      "root" = huaweicloud_organizations_organization.this.root_id
    },
    { for k, v in huaweicloud_organizations_organizational_unit.this : k => v.id },
    { for k, v in huaweicloud_organizations_organizational_unit.child : k => v.id },
  )

  # Account name-to-ID map
  account_id_for = merge(
    { for k, v in huaweicloud_organizations_account.core : k => v.id },
    { for k, v in huaweicloud_organizations_account.workload : k => v.id },
  )
}

# --- Organization ---

resource "huaweicloud_organizations_organization" "this" {
  enabled_policy_types = var.enabled_policy_types
}

# --- Organizational units ---
# Note: Top-level and child OUs are separate resources to resolve parent IDs.

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

# --- Member accounts and trust agencies ---

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

# --- Identity Center ---

# Note: Register the home region before starting Identity Center.
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

# --- Trusted services ---

resource "huaweicloud_organizations_trusted_service" "this" {
  for_each = toset(var.trusted_services)

  service = each.value

  depends_on = [huaweicloud_organizations_organization.this]
}

# --- Delegated administrators ---

resource "huaweicloud_organizations_delegated_administrator" "this" {
  for_each = var.delegated_administrators

  service_principal = each.key
  account_id        = local.account_id_for[each.value]

  depends_on = [huaweicloud_organizations_trusted_service.this]
}

# --- Tag policies ---
# Note: Requires tag_policy in enabled_policy_types.

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

# --- Enterprise project authorization ---
# Note: Removing the resource does not revoke the authorization grant.
resource "huaweicloud_enterprise_project_authority" "this" {
  count = var.create_enterprise_project ? 1 : 0
}

resource "huaweicloud_enterprise_project" "bootstrap" {
  count = var.create_enterprise_project ? 1 : 0

  name        = var.enterprise_project_name
  description = "Landing zone bootstrap enterprise project"

  depends_on = [huaweicloud_enterprise_project_authority.this]
}
