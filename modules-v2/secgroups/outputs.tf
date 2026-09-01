output "secgroup_ids" {
  description = "Security group name -> id (this account)."
  value       = { for k, v in huaweicloud_networking_secgroup.this : k => v.id }
}
