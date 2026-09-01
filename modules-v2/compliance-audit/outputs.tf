output "audit_bucket_name" { value = huaweicloud_obs_bucket.audit.bucket }
output "audit_bucket_id" { value = huaweicloud_obs_bucket.audit.id }

output "kms_key_ids" {
  description = "Map of log-infra KMS alias -> key ID"
  value = {
    "lz-audit-bucket" = huaweicloud_kms_key.audit.id
  }
}

output "cts_tracker_id" {
  description = "Org CTS tracker ID"
  value       = huaweicloud_cts_tracker.org.id
}

output "cts_log_group_id" {
  description = "CTS LTS log group ID."
  value       = huaweicloud_lts_group.cts.id
}

output "cts_log_stream_id" {
  description = "CTS LTS log stream ID."
  value       = huaweicloud_lts_stream.cts.id
}
