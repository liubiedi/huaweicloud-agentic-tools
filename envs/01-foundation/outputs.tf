output "organization_id" {
  value = module.org_foundation.organization_id
}

output "root_id" {
  value = module.org_foundation.root_id
}

output "log_archive_account_id" {
  value = module.org_foundation.log_archive_account_id
}

output "audit_account_id" {
  value = module.org_foundation.audit_account_id
}

output "member_account_ids" {
  value = module.org_foundation.member_account_ids
}

output "enterprise_project_id" {
  value = module.org_foundation.enterprise_project_id
}

output "sso_instance_id" {
  value = module.identity_center.instance_id
}

output "permission_set_ids" {
  value = module.identity_center.permission_set_ids
}
