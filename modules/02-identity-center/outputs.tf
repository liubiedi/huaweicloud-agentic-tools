output "instance_id" {
  value       = local.instance_id
  description = "IAM Identity Center instance ID"
}

output "identity_store_id" {
  value       = local.identity_store_id
  description = "Identity store ID"
}

output "group_ids" {
  value       = { for k, v in huaweicloud_identitycenter_group.groups : k => v.id }
  description = "Map of group name to group ID"
}

output "user_ids" {
  value       = { for k, v in huaweicloud_identitycenter_user.users : k => v.id }
  description = "Map of username to user ID"
}

output "permission_set_ids" {
  value       = { for k, v in huaweicloud_identitycenter_permission_set.standard : k => v.id }
  description = "Map of permission set name to ID"
}
