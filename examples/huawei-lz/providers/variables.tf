variable "home_region" {
  type        = string
  description = "Primary deployment region for the landing zone (e.g. cn-east-3, cn-north-4, ap-southeast-1)"
}

variable "master_access_key" {
  type        = string
  description = "Huawei Cloud master-account access key (AK)"
  sensitive   = true
}

variable "master_secret_key" {
  type        = string
  description = "Huawei Cloud master-account secret key (SK)"
  sensitive   = true
}

variable "environment" {
  type        = string
  description = "Environment label applied to default_tags"
  default     = "production"
}
