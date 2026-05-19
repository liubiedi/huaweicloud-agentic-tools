output "break_glass_group_id" {
  value       = huaweicloud_identity_group.break_glass.id
  description = "ID of the break-glass emergency admin group"
}

output "org_access_agency_id" {
  value       = huaweicloud_identity_agency.org_access.id
  description = "ID of OrganizationAccountAccessAgency"
}

output "terraform_agency_id" {
  value       = huaweicloud_identity_agency.terraform_automation.id
  description = "ID of the Terraform automation agency"
}

output "custom_agency_ids" {
  value       = { for k, v in huaweicloud_identity_agency.custom : k => v.id }
  description = "Map of custom agency name to ID"
}
