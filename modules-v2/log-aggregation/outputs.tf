output "archive_bucket_name" {
  description = "Name of the LTS archive OBS bucket (null when disabled)."
  value       = local.enabled ? huaweicloud_obs_bucket.archive[0].bucket : null
}

output "archive_kms_key_id" {
  description = "KMS key encrypting the archive bucket (null when disabled)."
  value       = local.enabled ? huaweicloud_kms_key.archive[0].id : null
}

output "target_group_ids" {
  description = "Converged target LTS group NAME -> ID."
  value       = { for k, v in huaweicloud_lts_group.target : k => v.id }
}

output "target_stream_ids" {
  description = "Converged target LTS stream '<group>__<stream>' -> ID."
  value       = { for k, v in huaweicloud_lts_stream.target : k => v.id }
}

output "converge_ids" {
  description = "Member account NAME -> converge resource ID."
  value       = { for k, v in huaweicloud_lts_log_converge.member : k => v.id }
}
