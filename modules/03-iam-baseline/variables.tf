variable "home_region" {
  type        = string
  description = "Region for IAM baseline configuration"
}

variable "org_id" {
  type        = string
  description = "Organizations org ID for trust relationships"
}

variable "master_account_id" {
  type        = string
  description = "Master account ID for cross-account agency trust"
}

variable "enable_mfa" {
  type        = bool
  description = "Enforce MFA for all IAM users"
  default     = true
}

variable "password_min_length" {
  type        = number
  description = "Minimum IAM password length"
  default     = 14
}

variable "password_max_age" {
  type        = number
  description = "Maximum password age in days"
  default     = 90
}

variable "session_timeout" {
  type        = number
  description = "Console session timeout in minutes"
  default     = 60
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "CIDR ranges permitted to access the console. Empty = no restriction."
  default     = []
}

variable "cross_account_agencies" {
  type = list(object({
    name            = string
    description     = string
    trust_domain    = string
    trust_services  = list(string)
    policy_names    = list(string)
  }))
  description = "IAM agencies to create for cross-account or service trust"
  default     = []
}
