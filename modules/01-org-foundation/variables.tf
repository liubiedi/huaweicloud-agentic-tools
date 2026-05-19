variable "home_region" {
  type        = string
  description = "Primary deployment region"
}

variable "log_archive_email" {
  type        = string
  description = "Email for the Log Archive account — immutable after RGC bootstrap"
  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.log_archive_email))
    error_message = "Must be a valid email address."
  }
}

variable "audit_email" {
  type        = string
  description = "Email for the Audit (security ops) account — immutable after RGC bootstrap"
  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.audit_email))
    error_message = "Must be a valid email address."
  }
}

variable "log_archive_bucket_name" {
  type        = string
  description = "OBS bucket name for RGC-managed audit logs"
}

variable "additional_ous" {
  type = list(object({
    name      = string
    parent_id = optional(string, "")
  }))
  description = "Extra OUs to create beyond the RGC defaults (Security, Sandbox)"
  default     = []
}

variable "additional_member_accounts" {
  type = list(object({
    name        = string
    email       = string
    parent_ou   = string
    description = optional(string, "")
  }))
  description = "Member accounts to vend via Organizations"
  default     = []
}

variable "trusted_services" {
  type        = list(string)
  description = "AWS-style service principals to enable as Organizations trusted services"
  default = [
    "config.myhuaweicloud.com",
    "secmaster.myhuaweicloud.com",
    "cts.myhuaweicloud.com",
    "identitycenter.myhuaweicloud.com",
    "ram.myhuaweicloud.com",
  ]
}

variable "tag_policies" {
  type = list(object({
    name        = string
    description = string
    content     = string
  }))
  description = "Tag policies to attach at the root"
  default     = []
}

variable "enterprise_project_name" {
  type        = string
  description = "Enterprise project name for cost allocation"
  default     = "landing-zone"
}
