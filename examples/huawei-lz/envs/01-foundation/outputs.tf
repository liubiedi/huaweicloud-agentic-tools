output "organization_id" {
  value       = module.org_foundation.organization_id
  description = "Huawei Organizations org ID"
}

output "root_id" {
  value       = module.org_foundation.root_id
  description = "Root OU ID — needed when other envs attach policies"
}

output "landing_zone_id" {
  value       = module.org_foundation.landing_zone_id
  description = "RGC landing zone resource ID"
}

output "landing_zone_status" {
  value       = module.org_foundation.landing_zone_status
  description = "Should read ENABLED after a successful apply"
}

output "log_archive_account_id" {
  value       = module.org_foundation.log_archive_account_id
  description = "Account ID of the RGC-created Log Archive account"
}

output "audit_account_id" {
  value       = module.org_foundation.audit_account_id
  description = "Account ID of the RGC-created Security/Audit account"
}

output "enterprise_project_id" {
  value       = module.org_foundation.enterprise_project_id
  description = "Landing zone enterprise project ID"
}

