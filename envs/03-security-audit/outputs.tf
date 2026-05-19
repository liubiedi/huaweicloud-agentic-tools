output "smn_topic_urn" {
  value = module.ops_monitoring_early.smn_topic_urn
}

output "cts_tracker_id" {
  value = module.audit_logging.cts_tracker_id
}

output "log_archive_bucket_name" {
  value = module.audit_logging.log_archive_bucket_name
}

output "security_log_group_id" {
  value = module.audit_logging.security_log_group_id
}

output "network_log_group_id" {
  value = module.audit_logging.network_log_group_id
}

output "secmaster_workspace_id" {
  value = module.security_center.secmaster_workspace_id
}

output "audit_kms_key_id" {
  value = module.security_center.audit_kms_key_id
}

output "conformance_pack_ids" {
  value = module.compliance_config.conformance_pack_ids
}
