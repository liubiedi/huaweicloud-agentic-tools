variable "home_region" {
  type        = string
  description = <<-EOT
    Primary deployment region. Use the Huawei region ID format
    (e.g. cn-east-3, cn-north-4, ap-southeast-1, ap-southeast-3, cn-south-1).
    See: https://support.huaweicloud.com/intl/en-us/productdesc-cc/cc_01_0003.html
    The Huawei API will validate the exact value at plan/apply time.
  EOT
  validation {
    # Shape check only — catches typos, accepts any well-formed Huawei region ID.
    condition     = can(regex("^[a-z]{2}-[a-z]+-?[0-9]+$", var.home_region))
    error_message = "home_region must be a Huawei region ID like cn-east-3 or ap-southeast-3."
  }
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

variable "environment" {
  type        = string
  description = "Environment label for default_tags"
  default     = "production"
}

# ── RGC-specific inputs ─────────────────────────────────────────────────────

variable "core_ou_name" {
  type        = string
  description = "Name of the CORE OU that RGC creates"
  default     = "Core"
}

variable "log_archive_account_name" {
  type        = string
  description = "Display name for the RGC Log Archive account"
  default     = "log-archive"
}

variable "audit_account_name" {
  type        = string
  description = "Display name for the RGC Security/Audit account"
  default     = "audit"
}

variable "audit_email" {
  type        = string
  description = "Email for the Security/Audit account — IMMUTABLE after RGC bootstrap"
}

variable "enable_identity_center" {
  type        = bool
  description = "Enable IAM Identity Center as part of bootstrap"
  default     = true
}

variable "identity_store_email" {
  type        = string
  description = "Identity Center store email (required when enable_identity_center = true)"
  default     = ""
}

variable "deny_ungoverned_regions" {
  type        = bool
  description = "Block all activity in regions not listed in region_configuration_list"
  default     = false
}

variable "enable_org_aggregation" {
  type        = bool
  description = "Enable organizational aggregation (CTS org-wide tracker)"
  default     = true
}

variable "logging_multi_az" {
  type        = bool
  description = "Multi-AZ storage for the RGC-managed logging + access-logging buckets"
  default     = false
}

variable "trusted_services" {
  type        = list(string)
  description = "Trusted service identifiers (format: service.<NAME>). Empty by default."
  default     = []
}

variable "logging_retention_days" {
  type        = number
  description = "Retention days for the RGC logging bucket"
  default     = 365
}

variable "access_logging_retention_days" {
  type        = number
  description = "Retention days for the RGC access-logging bucket"
  default     = 3650
}

# ── Optional extras ─────────────────────────────────────────────────────────

variable "additional_ous" {
  type = list(object({
    name      = string
    parent_id = optional(string, "")
  }))
  default = []
}

variable "additional_member_accounts" {
  type = list(object({
    name        = string
    email       = string
    parent_ou   = string
    description = optional(string, "")
  }))
  default = []
}

variable "tag_policies" {
  type = list(object({
    name        = string
    description = string
    content     = string
  }))
  default = []
}

variable "enable_default_tag_policy" {
  type        = bool
  description = "Attach a built-in tag policy at the root requiring standard tag keys"
  default     = false
}

variable "default_tag_policy_required_keys" {
  type        = list(string)
  description = "Tag keys the default tag policy enforces"
  default     = ["ManagedBy", "CostCenter", "Environment"]
}

variable "enterprise_project_name" {
  type        = string
  description = "Enterprise project name for cost allocation"
  default     = "landing-zone"
}
