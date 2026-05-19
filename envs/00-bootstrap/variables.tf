variable "home_region" {
  type    = string
  default = "cn-east-3"
}

variable "master_access_key" {
  type      = string
  sensitive = true
}

variable "master_secret_key" {
  type      = string
  sensitive = true
}

variable "tfstate_bucket_name" {
  type        = string
  description = "OBS bucket name for Terraform state files"
}
