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

variable "master_account_id" {
  type        = string
  description = "Master (management) account ID"
}

variable "log_archive_email" {
  type        = string
  description = "Email for the Log Archive account — immutable after bootstrap"
}

variable "audit_email" {
  type        = string
  description = "Email for the Audit account — immutable after bootstrap"
}

variable "log_archive_bucket_name" {
  type        = string
  description = "OBS bucket name for RGC audit log archive"
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

variable "sso_users" {
  type = list(object({
    user_name    = string
    family_name  = string
    given_name   = string
    email        = string
    display_name = string
    group_names  = list(string)
  }))
  default = []
}
