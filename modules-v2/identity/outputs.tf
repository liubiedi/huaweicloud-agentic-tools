output "group_ids" {
  description = "Map of IC group name -> ID (only populated when enable_identity_center_content = true)"
  value       = { for k, v in huaweicloud_identitycenter_group.this : k => v.id }
}

output "user_ids" {
  description = "Map of IC user_name -> ID"
  value       = { for k, v in huaweicloud_identitycenter_user.this : k => v.id }
}

output "permission_set_ids" {
  description = "Map of permission set name -> ID"
  value       = { for k, v in huaweicloud_identitycenter_permission_set.this : k => v.id }
}

output "agency_ids" {
  description = "Map of service agency name -> ID (per-account IAM baseline)"
  value       = { for k, v in huaweicloud_identity_agency.this : k => v.id }
}

output "agency_urns" {
  description = "Map of service agency name -> agency ID. (The resource exposes no URN; the ID is the usable identifier for OBS bucket policies / module 6.)"
  value       = { for k, v in huaweicloud_identity_agency.this : k => v.id }
}
