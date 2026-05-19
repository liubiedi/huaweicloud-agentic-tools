output "smn_topic_urn" {
  value       = huaweicloud_smn_topic.ops_alerts.id
  description = "SMN topic URN for ops alerts — pass to other modules for alarm delivery"
}

output "aom_prometheus_id" {
  value       = huaweicloud_aom_prometheus_instance.lz.id
  description = "AOM Prometheus instance ID"
}

output "remediate_bucket_function_urn" {
  value       = var.enable_functiongraph_runbooks ? huaweicloud_fgs_function.remediate_public_bucket[0].urn : null
  description = "FunctionGraph URN for the public-bucket auto-remediation runbook"
}
