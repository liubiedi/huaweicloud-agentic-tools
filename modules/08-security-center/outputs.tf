output "secmaster_workspace_id" {
  value       = huaweicloud_secmaster_workspace.this.id
  description = "SecMaster workspace ID"
}

output "hss_group_id" {
  value       = huaweicloud_hss_host_group.all_hosts.id
  description = "HSS host group ID — spoke accounts register hosts to this group"
}

output "kms_key_ids" {
  value       = { for k, v in huaweicloud_kms_key.security : k => v.id }
  description = "Map of KMS key alias to ID"
}

output "audit_kms_key_id" {
  value       = try(huaweicloud_kms_key.security["lz-audit-key"].id, null)
  description = "KMS key ID for audit data encryption"
}

output "secret_kms_key_id" {
  value       = try(huaweicloud_kms_key.security["lz-secret-key"].id, null)
  description = "KMS key ID for CSMS secrets encryption"
}

output "dbss_instance_id" {
  value       = var.enable_dbss ? huaweicloud_dbss_instance.this[0].id : null
  description = "DBSS instance ID"
}

output "csms_secret_ids" {
  value       = { for k, v in huaweicloud_csms_secret.secrets : k => v.id }
  description = "Map of secret name to CSMS secret ID"
}
