output "public_zone_ids" {
  description = "Public zone NAME -> ID."
  value       = { for k, v in huaweicloud_dns_zone.public : k => v.id }
}

output "private_zone_ids" {
  description = "Private zone NAME -> ID."
  value       = { for k, v in huaweicloud_dns_zone.private : k => v.id }
}

output "recordset_ids" {
  description = "Record set key '<zone>__<name>__<type>' -> ID."
  value       = { for k, v in huaweicloud_dns_recordset.this : k => v.id }
}

output "resolver_endpoint_ids" {
  description = "Resolver endpoint NAME -> ID."
  value       = { for k, v in huaweicloud_dns_endpoint.this : k => v.id }
}

output "resolver_endpoint_ips" {
  description = "Resolver endpoint NAME -> resolver IP addresses."
  value       = { for k, v in huaweicloud_dns_endpoint.this : k => v.ip_addresses[*].ip }
}

output "resolver_rule_ids" {
  description = "Resolver (forwarding) rule NAME -> ID."
  value       = { for k, v in huaweicloud_dns_resolver_rule.this : k => v.id }
}

output "access_log_ids" {
  description = "Access-log config NAME -> ID."
  value       = { for k, v in huaweicloud_dns_resolver_access_log.this : k => v.id }
}
