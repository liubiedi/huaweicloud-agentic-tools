output "address_group_ids" {
  description = "Address group NAME -> ID."
  value       = { for k, v in huaweicloud_cfw_address_group.this : k => v.id }
}

output "domain_group_ids" {
  description = "Domain name group NAME -> ID."
  value       = { for k, v in huaweicloud_cfw_domain_name_group.this : k => v.id }
}

output "service_group_ids" {
  description = "Service group NAME -> ID."
  value       = { for k, v in huaweicloud_cfw_service_group.this : k => v.id }
}

output "acl_rule_ids" {
  description = "ACL rule NAME -> ID."
  value       = { for k, v in huaweicloud_cfw_acl_rule.this : k => v.id }
}

output "black_white_list_ids" {
  description = "Black/white list key -> ID."
  value       = { for k, v in huaweicloud_cfw_black_white_list.this : k => v.id }
}
