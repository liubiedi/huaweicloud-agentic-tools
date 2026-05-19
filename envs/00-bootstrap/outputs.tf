output "tfstate_bucket_name" {
  value       = huaweicloud_obs_bucket.tfstate.id
  description = "OBS bucket name for Terraform state — configure as S3 backend for all other envs"
}

output "tfstate_kms_key_id" {
  value       = huaweicloud_kms_key.tfstate.id
  description = "KMS key ID used to encrypt the state bucket"
}

output "terraform_ci_agency_id" {
  value       = huaweicloud_identity_agency.terraform_ci.id
  description = "Agency ID for CI/CD Terraform automation"
}

output "obs_endpoint" {
  value       = "https://obs.${var.home_region}.myhuaweicloud.com"
  description = "OBS S3-compatible endpoint — use in backend S3 config"
}
