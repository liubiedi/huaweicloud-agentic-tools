output "tfstate_bucket_name" {
  value       = huaweicloud_obs_bucket.tfstate.bucket
  description = "Pass this as -backend-config=bucket=... when running terraform init in later envs"
}

output "tfstate_bucket_region" {
  value       = var.home_region
  description = "Pass this as -backend-config=region=... when running terraform init in later envs"
}

output "tfstate_kms_key_id" {
  value       = huaweicloud_kms_key.tfstate.id
  description = "KMS key encrypting the state bucket"
}
