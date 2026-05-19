output "log_archive_bucket_id" {
  value       = huaweicloud_obs_bucket.log_archive.id
  description = "Log archive OBS bucket ID"
}

output "log_archive_bucket_name" {
  value       = huaweicloud_obs_bucket.log_archive.bucket
  description = "Log archive OBS bucket name"
}

output "cts_tracker_id" {
  value       = huaweicloud_cts_tracker.org.id
  description = "CTS organization tracker ID"
}

output "lts_group_ids" {
  value       = { for k, v in huaweicloud_lts_group.groups : k => v.id }
  description = "Map of LTS log group name to ID"
}

output "lts_stream_ids" {
  value       = { for k, v in huaweicloud_lts_stream.streams : k => v.id }
  description = "Map of stream key (group__stream) to LTS stream ID"
}

output "security_log_group_id" {
  value       = try(huaweicloud_lts_group.groups["lz-security-logs"].id, null)
  description = "ID of the security log group — used by CFW, HSS, WAF modules"
}

output "network_log_group_id" {
  value       = try(huaweicloud_lts_group.groups["lz-network-logs"].id, null)
  description = "ID of the network log group — used by VPC, ER, ELB modules"
}
