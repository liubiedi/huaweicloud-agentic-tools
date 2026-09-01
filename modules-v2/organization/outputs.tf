output "organization_id" {
  description = "Huawei Organizations org ID"
  value       = huaweicloud_organizations_organization.this.id
}

output "organization_urn" {
  description = "Organization URN"
  value       = huaweicloud_organizations_organization.this.urn
}

output "master_account_id" {
  description = "Master (management) account ID"
  value       = huaweicloud_organizations_organization.this.master_account_id
}

output "master_account_name" {
  description = "Master account name (typically used as domain_name in cross-account provider config)"
  value       = huaweicloud_organizations_organization.this.master_account_name
}

output "root_id" {
  description = "Org root ID (attachment target for org-wide SCPs)"
  value       = huaweicloud_organizations_organization.this.root_id
}

output "ou_ids" {
  description = "Map of OU name -> OU ID (top-level + child OUs)"
  value = merge(
    { for k, v in huaweicloud_organizations_organizational_unit.this : k => v.id },
    { for k, v in huaweicloud_organizations_organizational_unit.child : k => v.id },
  )
}

output "workloads_ou_id" {
  description = "Workloads OU ID, or null if no OU named 'Workloads' exists. Module 4 uses this as default SCP attach target."
  value = lookup(merge(
    { for k, v in huaweicloud_organizations_organizational_unit.this : k => v.id },
    { for k, v in huaweicloud_organizations_organizational_unit.child : k => v.id },
  ), "Workloads", null)
}

output "accounts" {
  description = "Flat map of account name -> { id, urn, ou, role }. Env layer reads this to configure provider aliases per account. (email omitted - it is provider-sensitive and not needed downstream.)"
  value = merge(
    {
      for k, v in huaweicloud_organizations_account.core : k => {
        id   = v.id
        urn  = v.urn
        ou   = v.parent_id
        role = "core"
      }
    },
    {
      for k, v in huaweicloud_organizations_account.workload : k => {
        id   = v.id
        urn  = v.urn
        ou   = v.parent_id
        role = "workload"
      }
    },
  )
}

output "identity_store_id" {
  description = "Identity Center identity store ID - consumed by module 2 for IC user/group/permission_set content"
  value       = huaweicloud_identitycenter_instance.this.identity_store_id
}

output "identity_center_instance_urn" {
  description = "Identity Center instance URN"
  value       = huaweicloud_identitycenter_instance.this.instance_urn
}

output "identity_center_instance_id" {
  description = "Identity Center instance ID"
  value       = huaweicloud_identitycenter_instance.this.id
}

output "enterprise_project_id" {
  description = "Bootstrap enterprise project ID (null if create_enterprise_project = false)"
  value       = var.create_enterprise_project ? huaweicloud_enterprise_project.bootstrap[0].id : null
}

output "custom_tag_policy_ids" {
  description = "Map of custom tag policy name -> policy ID"
  value       = { for k, v in huaweicloud_organizations_policy.custom_tag : k => v.id }
}

output "cross_account_agency_name" {
  description = "Echo of the agency name used on every created account. Envs use this in provider aliases (agency_name = ...)."
  value       = var.cross_account_agency_name
}
