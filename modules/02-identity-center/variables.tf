variable "home_region" {
  type        = string
  description = "Region for IAM Identity Center"
}

variable "instance_id" {
  type        = string
  description = "IAM Identity Center instance ID (retrieved from data source if blank)"
  default     = ""
}

variable "groups" {
  type = list(object({
    name        = string
    description = string
  }))
  description = "Groups to create in IAM Identity Center"
  default = [
    { name = "LzAdministrators", description = "Full administrative access" },
    { name = "LzDevelopers", description = "Developer access to workload accounts" },
    { name = "LzSecurityAuditors", description = "Read-only security audit access" },
    { name = "LzBillingViewers", description = "Billing read-only access" },
    { name = "LzReadOnly", description = "Read-only access to all resources" },
  ]
}

variable "users" {
  type = list(object({
    user_name    = string
    family_name  = string
    given_name   = string
    email        = string
    display_name = string
    group_names  = list(string)
  }))
  description = "Users to provision in IAM Identity Center"
  default     = []
}

variable "account_assignments" {
  type = list(object({
    account_id      = string
    group_name      = string
    permission_set  = string
  }))
  description = "Bindings of group + permission set to accounts"
  default     = []
}

variable "session_duration" {
  type        = string
  description = "Default session duration for permission sets (ISO 8601)"
  default     = "PT8H"
}
