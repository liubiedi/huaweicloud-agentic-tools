variable "home_region" {
  type        = string
  description = "Deployment region for security services"
}

variable "secmaster_workspace_name" {
  type        = string
  description = "SecMaster workspace name"
  default     = "lz-secmaster"
}

variable "secmaster_edition" {
  type        = string
  description = "SecMaster edition: standard or professional"
  default     = "standard"
}

variable "hss_quota_count" {
  type        = number
  description = "Number of HSS host protection quota units to purchase"
  default     = 10
}

variable "hss_version" {
  type        = string
  description = "HSS version: hss.version.enterprise or hss.version.premium"
  default     = "hss.version.enterprise"
}

variable "dbss_availability_zone" {
  type        = string
  description = "AZ for DBSS instance"
}

variable "dbss_vpc_id" {
  type        = string
  description = "VPC ID for DBSS instance"
}

variable "dbss_subnet_id" {
  type        = string
  description = "Subnet ID for DBSS instance"
}

variable "dbss_security_group_id" {
  type        = string
  description = "Security group ID for DBSS instance"
}

variable "enable_dbss" {
  type        = bool
  description = "Deploy a Database Security Service instance"
  default     = true
}

variable "kms_keys" {
  type = list(object({
    alias            = string
    description      = string
    rotation_enabled = optional(bool, true)
  }))
  description = "KMS keys for security ops — dedicated keystore for audit and encryption"
  default = [
    { alias = "lz-audit-key", description = "Key for encrypting audit and compliance data" },
    { alias = "lz-secret-key", description = "Key for CSMS secrets encryption" },
  ]
}

variable "csms_secrets" {
  type = list(object({
    name        = string
    description = string
    kms_key_id  = optional(string, "")
  }))
  description = "CSMS secrets to create (values injected post-apply)"
  default     = []
}

variable "lts_log_group_id" {
  type        = string
  description = "LTS log group ID for security event streams"
  default     = ""
}

variable "smn_topic_urn" {
  type        = string
  description = "SMN topic URN for security alerts"
  default     = ""
}

variable "enterprise_project_id" {
  type        = string
  description = "Enterprise project ID"
  default     = "0"
}

variable "tags" {
  type        = map(string)
  description = "Tags for security resources"
  default     = {}
}
