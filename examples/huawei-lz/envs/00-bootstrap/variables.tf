variable "home_region" {
  type        = string
  description = "Region for the OBS state bucket. Pick a region close to where you operate."
}

variable "master_access_key" {
  type        = string
  description = "Huawei Cloud master-account AK"
  sensitive   = true
}

variable "master_secret_key" {
  type        = string
  description = "Huawei Cloud master-account SK"
  sensitive   = true
}

variable "tfstate_bucket_name" {
  type        = string
  description = "Globally-unique OBS bucket name for Terraform state (lowercase, 3-63 chars)"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.tfstate_bucket_name))
    error_message = "Bucket name must be 3-63 lowercase alphanumeric chars, dots or hyphens."
  }
}
