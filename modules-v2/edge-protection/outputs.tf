output "antiddos_ids" {
  description = "Anti-DDoS row NAME -> resource ID."
  value       = { for k, v in huaweicloud_antiddos_basic.this : k => v.id }
}

output "waf_instance_id" {
  description = "Dedicated WAF instance ID (null when enable_waf = false)."
  value       = var.enable_waf ? huaweicloud_waf_dedicated_instance.this[0].id : null
}

output "waf_policy_id" {
  description = "Shared WAF policy ID (null when enable_waf = false)."
  value       = var.enable_waf ? huaweicloud_waf_policy.this[0].id : null
}

output "waf_domain_ids" {
  description = "Protected DOMAIN -> WAF dedicated-domain ID."
  value       = { for k, v in huaweicloud_waf_dedicated_domain.this : k => v.id }
}
