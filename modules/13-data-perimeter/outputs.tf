output "deny_services_policy_id" {
  value       = length(var.deny_services) > 0 ? huaweicloud_organizations_policy.deny_services[0].id : null
  description = "SCP ID for denied services policy"
}

output "obs_vpcep_only_policy_id" {
  value       = var.enforce_mode ? huaweicloud_organizations_policy.obs_vpcep_only[0].id : null
  description = "SCP ID for OBS VPCEP-only policy (null if not in enforce mode)"
}

output "vpcep_service_ids" {
  value       = { for k, v in huaweicloud_vpcep_service.services : k => v.id }
  description = "Map of VPC endpoint service name to ID"
}

output "vpcep_endpoint_ids" {
  value       = { for k, v in huaweicloud_vpcep_endpoint.endpoints : k => v.id }
  description = "Map of VPC endpoint name to ID"
}
