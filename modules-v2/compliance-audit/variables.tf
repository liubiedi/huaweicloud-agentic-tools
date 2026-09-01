# Module 6 - unified compliance audit
# Lives in logging account (lz-infra). Owns: org CTS tracker + 3 OBS buckets +
# log-infra KMS + LTS infrastructure.

variable "environment" {
  type    = string
  default = "shared"
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "account_name" {
  type        = string
  default     = ""
  description = "Account this central audit module deploys into (the CTS delegated admin). Substituted for the {account-name} token in the bucket / KMS / CTS log-group / stream names below."
}

# Explicit, required names. OBS bucket names must be globally unique across all
# of Huawei Cloud, so there is no safe default/fallback - each must be provided.
variable "audit_bucket_name" {
  type        = string
  description = "Name for the CTS audit OBS bucket (globally unique)."
}
variable "audit_bucket_force_destroy" {
  type        = bool
  default     = false
  description = "Allow Terraform to delete a NON-EMPTY audit bucket (needed to recreate it on a rename - DESTROYS stored audit objects). Keep false unless you intend that."
}
variable "kms_audit_alias" {
  type        = string
  description = "KMS alias for the audit-bucket key."
}

variable "home_region" {
  type        = string
  description = "Used for OBS endpoints. The CTS org tracker is created in this region too (via the module's provider)."
}

variable "member_account_ids" {
  type        = list(string)
  default     = []
  description = "All created account IDs (from module 1's accounts output). Used for cross-account bucket policies + LTS cross_account_access."
}

# ---- Retention ----

variable "audit_cold_after_days" {
  type        = number
  default     = 0
  description = "Days before audit objects move to the COLD storage class (0 = never)."
}

variable "audit_retention_days" {
  type    = number
  default = 365
}
variable "lts_hot_retention_days" {
  type    = number
  default = 90
}

# ---- CTS LTS log group + stream (the single LTS pair, for the CTS trail) ----

variable "cts_log_group_name" {
  type        = string
  default     = "lz-cts"
  description = "CTS LTS log group name. Supports {account-name}."
}
variable "cts_log_stream_name" {
  type        = string
  default     = ""
  description = "CTS LTS log stream name. Supports {account-name}. Blank = cts_log_group_name."
}

# ---- KMS ----

variable "kms_pending_days" {
  type    = number
  default = 7 # Day-1 default; production should bump to 30
}

# ---- CTS extensions (deferred - default off) ----

variable "cts_notifications" {
  type    = any
  default = []
}

variable "cts_data_trackers" {
  type    = any
  default = []
}
