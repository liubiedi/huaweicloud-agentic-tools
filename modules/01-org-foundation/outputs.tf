output "organization_id" {
  value       = data.huaweicloud_organizations_organization.current.id
  description = "Organizations org ID"
}

output "root_id" {
  value       = data.huaweicloud_organizations_organization.current.root_id
  description = "Root OU ID"
}

output "log_archive_account_id" {
  value       = huaweicloud_rgc_landing_zone.this.log_archive_account_id
  description = "Account ID of the RGC-created Log Archive account"
}

output "audit_account_id" {
  value       = huaweicloud_rgc_landing_zone.this.audit_account_id
  description = "Account ID of the RGC-created Audit account"
}

output "member_account_ids" {
  value       = { for k, v in huaweicloud_organizations_account.members : k => v.id }
  description = "Map of account name to account ID for vended member accounts"
}

output "additional_ou_ids" {
  value       = { for k, v in huaweicloud_organizations_organizational_unit.additional : k => v.id }
  description = "Map of OU name to OU ID"
}

output "enterprise_project_id" {
  value       = huaweicloud_enterprise_project.lz.id
  description = "Landing zone enterprise project ID"
}

output "scp_deny_root_id" {
  value       = huaweicloud_organizations_policy.deny_root.id
  description = "SCP ID for deny-root policy"
}

output "scp_region_boundary_id" {
  value       = huaweicloud_organizations_policy.region_boundary.id
  description = "SCP ID for region boundary policy"
}
