output "recorder_id" {
  value       = huaweicloud_rms_resource_recorder.org.id
  description = "RMS resource recorder ID"
}

output "aggregator_id" {
  value       = huaweicloud_rms_resource_aggregator.org.id
  description = "RMS org resource aggregator ID"
}

output "conformance_pack_ids" {
  value       = { for k, v in huaweicloud_rms_assignment_package.packs : k => v.id }
  description = "Map of conformance pack name to assignment package ID"
}

output "custom_rule_ids" {
  value       = { for k, v in huaweicloud_rms_policy_assignment.custom : k => v.id }
  description = "Map of custom rule name to policy assignment ID"
}
