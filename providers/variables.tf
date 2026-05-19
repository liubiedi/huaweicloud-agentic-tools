variable "home_region" {
  type        = string
  description = "Primary deployment region"
  default     = "cn-east-3"
  validation {
    condition     = contains(["cn-east-3", "cn-north-4", "cn-south-1", "ap-southeast-1", "ap-southeast-2", "ap-southeast-3"], var.home_region)
    error_message = "Must be a supported Huawei Cloud region."
  }
}

variable "master_access_key" {
  type        = string
  description = "AK for the management (master) account"
  sensitive   = true
}

variable "master_secret_key" {
  type        = string
  description = "SK for the management (master) account"
  sensitive   = true
}

variable "network_ops_account_domain" {
  type        = string
  description = "Domain name of the network operations account"
}

variable "logging_account_domain" {
  type        = string
  description = "Domain name of the logging (log archive) account"
}

variable "security_ops_account_domain" {
  type        = string
  description = "Domain name of the security operations account"
}

variable "ops_monitoring_account_domain" {
  type        = string
  description = "Domain name of the O&M monitoring account"
}

variable "public_service_account_domain" {
  type        = string
  description = "Domain name of the public service account"
}

variable "sandbox_account_domain" {
  type        = string
  description = "Domain name of the sandbox account"
}

variable "organization_id" {
  type        = string
  description = "Huawei Cloud Organizations org ID"
  default     = ""
}
