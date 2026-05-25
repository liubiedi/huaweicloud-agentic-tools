variable "home_region" {
  type        = string
  description = "Primary deployment region (must be a Huawei-governed region, e.g. cn-east-3, cn-north-4, ap-southeast-1)"
}

variable "core_ou_name" {
  type        = string
  description = "Name of the CORE organizational unit created by RGC"
  default     = "Core"
}

variable "log_archive_account_name" {
  type        = string
  description = "Display name for the RGC-created Log Archive account"
  default     = "log-archive"
}

variable "audit_account_name" {
  type        = string
  description = "Display name for the RGC-created Security/Audit account"
  default     = "audit"
}

variable "audit_email" {
  type        = string
  description = "Email for the Audit (security ops) account — immutable after RGC bootstrap"
  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.audit_email))
    error_message = "Must be a valid email address."
  }
}

variable "identity_store_email" {
  type        = string
  description = "Email used for the Identity Center store. Required when enable_identity_center = true."
  default     = ""
  validation {
    condition     = var.identity_store_email == "" || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.identity_store_email))
    error_message = "Must be a valid email address or empty."
  }
}

variable "enable_identity_center" {
  type        = bool
  description = "Enable Identity Center as part of the landing zone bootstrap"
  default     = true
}

variable "enable_org_aggregation" {
  type        = bool
  description = "Enable organizational aggregation (CloudTrail/CTS org-wide tracker)"
  default     = true
}

variable "deny_ungoverned_regions" {
  type        = bool
  description = "If true, RGC denies all activity in regions not listed in region_configuration_list"
  default     = false
}

variable "logging_retention_days" {
  type        = number
  description = "Retention days for the RGC-managed logging bucket"
  default     = 365
}

variable "access_logging_retention_days" {
  type        = number
  description = "Retention days for the RGC-managed access-logging bucket"
  default     = 3650
}

variable "logging_multi_az" {
  type        = bool
  description = "Enable multi-AZ storage for the RGC logging buckets"
  default     = false
}

variable "additional_ous" {
  type = list(object({
    name      = string
    parent_id = optional(string, "")
  }))
  description = "Extra OUs to create beyond the RGC defaults"
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
  description = <<-EOT
    Service principals to register as Organizations trusted services. Values use
    the Huawei "service.<NAME>" format (e.g. "service.AOM"), NOT AWS-style FQDNs.
    Discover available identifiers in your account with:
      data "huaweicloud_organizations_trusted_services" "all" {}
    or via the Huawei console: Organizations > Services > Available services.
    Empty by default to avoid shipping incorrect identifiers.
  EOT
  default     = []
}

variable "enable_default_tag_policy" {
  type        = bool
  description = "Attach a built-in tag policy at the root that requires the keys in default_tag_policy_required_keys"
  default     = false
}

variable "default_tag_policy_required_keys" {
  type        = list(string)
  description = "Tag keys the default tag policy enforces (only used when enable_default_tag_policy = true)"
  default     = ["ManagedBy", "CostCenter", "Environment"]
}

variable "tag_policies" {
  type = list(object({
    name        = string
    description = string
    content     = string
  }))
  description = "Custom tag policies to attach at the root (additional to the built-in default)"
  default     = []
}

variable "enterprise_project_name" {
  type        = string
  description = "Enterprise project name for cost allocation"
  default     = "landing-zone"
}
