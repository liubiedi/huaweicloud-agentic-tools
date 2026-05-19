output "kms_key_ids" {
  value       = { for k, v in huaweicloud_kms_key.keys : k => v.id }
  description = "Map of key alias to KMS key ID"
}

output "kms_key_arns" {
  value       = { for k, v in huaweicloud_kms_key.keys : k => v.key_id }
  description = "Map of key alias to KMS key ARN/ID"
}

output "shared_bucket_names" {
  value       = { for k, v in huaweicloud_obs_bucket.shared : k => v.id }
  description = "Map of shared OBS bucket names"
}

output "sfs_turbo_ids" {
  value       = { for k, v in huaweicloud_sfs_turbo.instances : k => v.id }
  description = "Map of SFS Turbo instance name to ID"
}

output "shared_image_ids" {
  value       = { for k, v in huaweicloud_images_image.shared : k => v.id }
  description = "Map of image name to IMS image ID"
}
