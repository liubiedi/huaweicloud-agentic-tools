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

variable "logging_account_domain" {
  type = string
}

variable "security_ops_account_domain" {
  type = string
}

variable "tfstate_bucket" {
  type = string
}

variable "log_archive_bucket" {
  type        = string
  description = "OBS bucket for CTS and LTS cold archive"
}

variable "alert_email_endpoints" {
  type    = list(string)
  default = []
}

variable "hss_quota_count" {
  type    = number
  default = 10
}

variable "enable_dbss" {
  type    = bool
  default = false
}

variable "dbss_vpc_id" {
  type    = string
  default = ""
}

variable "dbss_subnet_id" {
  type    = string
  default = ""
}

variable "dbss_security_group_id" {
  type    = string
  default = ""
}
