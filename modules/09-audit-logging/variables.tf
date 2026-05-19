# CTS org tracker must be deployed in cn-north-4 — this is intentionally hard-coded in main.tf
variable "home_region" {
  type        = string
  description = "Primary region (used for LTS and OBS; CTS org tracker always cn-north-4)"
}

variable "log_archive_bucket" {
  type        = string
  description = "OBS bucket name for long-term CTS + LTS cold archive"
}

variable "log_archive_bucket_region" {
  type        = string
  description = "Region where the log archive OBS bucket lives"
  default     = "cn-east-3"
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encrypting the log archive bucket"
  default     = ""
}

variable "smn_topic_urn" {
  type        = string
  description = "SMN topic URN for CTS key event notifications"
  default     = ""
}

variable "log_groups" {
  type = list(object({
    name            = string
    retention_days  = optional(number, 365)
    streams         = list(string)
  }))
  description = "LTS log groups and streams to create"
  default = [
    {
      name           = "lz-security-logs"
      retention_days = 365
      streams        = ["cfw-logs", "hss-logs", "waf-logs", "cts-logs"]
    },
    {
      name           = "lz-network-logs"
      retention_days = 90
      streams        = ["vpc-flow-logs", "er-flow-logs", "elb-access-logs"]
    },
    {
      name           = "lz-application-logs"
      retention_days = 30
      streams        = ["app-access-logs", "app-error-logs"]
    },
  ]
}

variable "archive_cold_after_days" {
  type        = number
  description = "Transition logs to IA storage after N days"
  default     = 30
}

variable "archive_expire_after_days" {
  type        = number
  description = "Delete archived logs after N days (0 = never)"
  default     = 2555 # 7 years
}

variable "enterprise_project_id" {
  type        = string
  description = "Enterprise project ID"
  default     = "0"
}

variable "tags" {
  type        = map(string)
  description = "Tags for audit logging resources"
  default     = {}
}
