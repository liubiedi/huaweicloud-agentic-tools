# --- Audit inputs ---

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

# --- Bucket names and key aliases ---
# Note: OBS bucket names must be globally unique.
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

# --- Retention settings ---

variable "audit_cold_after_days" {
  type        = number
  default     = 0
  description = "Days before audit objects move to the COLD storage class (0 = never)."
}

variable "audit_retention_days" {
  type    = number
  default = 365
}
# --- Encryption settings ---

variable "kms_pending_days" {
  type = number
  # Key deletion waiting period
  default = 7
}

# --- CTS extensions ---

# --- Key-event notifications ---
variable "cts_notifications" {
  type = list(object({
    name        = string
    description = optional(string, "")
    operations = list(object({
      service     = string
      resource    = string
      trace_names = list(string)
    }))
  }))
  default = []
}

variable "cts_notification_topic_urn" {
  type        = string
  default     = ""
  description = "SMN topic URN that cts_notifications publish to. Required when cts_notifications is non-empty."
}

variable "cts_data_trackers" {
  type    = any
  default = []
}
