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

variable "tfstate_bucket" {
  type = string
}

variable "enforce_mode" {
  type        = bool
  default     = false
  description = "WARNING: set to true only after verifying VPC endpoints are in place in all spoke accounts"
}

variable "deny_services" {
  type        = list(string)
  description = "Service actions to explicitly deny via SCP"
  default     = []
}
