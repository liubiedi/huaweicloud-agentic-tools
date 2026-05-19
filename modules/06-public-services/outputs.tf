output "elb_id" {
  value       = huaweicloud_elb_loadbalancer.shared.id
  description = "Shared ELB instance ID"
}

output "elb_vip_address" {
  value       = huaweicloud_elb_loadbalancer.shared.ipv4_address
  description = "ELB private VIP address"
}

output "https_listener_id" {
  value       = huaweicloud_elb_listener.https.id
  description = "HTTPS listener ID"
}

output "waf_instance_id" {
  value       = var.enable_waf ? huaweicloud_waf_dedicated_instance.this[0].id : null
  description = "WAF dedicated instance ID"
}

output "waf_policy_id" {
  value       = var.enable_waf ? huaweicloud_waf_policy.default[0].id : null
  description = "Default WAF policy ID"
}

output "public_dns_zone_ids" {
  value       = { for k, v in huaweicloud_dns_zone.public : k => v.id }
  description = "Map of public DNS zone name to zone ID"
}

output "private_dns_zone_ids" {
  value       = { for k, v in huaweicloud_dns_zone.private : k => v.id }
  description = "Map of private DNS zone name to zone ID"
}

output "dns_inbound_endpoint_id" {
  value       = huaweicloud_dns_endpoint.inbound.id
  description = "DNS inbound resolver endpoint ID"
}
