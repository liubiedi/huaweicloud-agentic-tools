# --- Log aggregation inputs ---
# Note: Use assume_role credentials so the archive bucket is created in the LTS admin account.

variable "enable_log_aggregation" {
  type        = bool
  default     = true
  description = "Master toggle. false = no switch/targets/converge/transfers/bucket."
}

variable "account_name" {
  type        = string
  default     = ""
  description = "Name of the LTS delegated-admin account this module deploys into. Replaces the {account-name} token in names below."
}

variable "organization_id" {
  type        = string
  default     = ""
  description = "Huawei Organizations org ID (from 01-foundation state)."
}

variable "management_account_id" {
  type        = string
  default     = ""
  description = "Domain (account) ID of the LTS delegated-admin account - lts_log_converge.management_account_id."
}

variable "home_region" {
  type        = string
  default     = ""
  description = "Region this module deploys into. Used to resolve the admin account's region project ID (lts_log_converge.management_project_id)."
}

# --- Member-to-admin log mappings ---

variable "converge_members" {
  type = map(object({
    # Member account domain ID
    account_id = string
    mappings = list(object({
      source_log_group_id   = string
      target_log_group_name = string
      streams = list(object({
        source_log_stream_id   = string
        target_log_stream_name = string
      }))
    }))
  }))
  default     = {}
  description = "Per member-account converge config, keyed by account NAME. Source IDs are resolved by the env (generated per-account data lookups); target groups/streams are created by this module and referenced by ID."
}

variable "converged_retention_days" {
  type        = number
  default     = 90
  description = "Hot (LTS) retention of the converged target groups/streams, in days."
}

# --- Archive bucket inputs ---

variable "archive_bucket_name" {
  type        = string
  description = "REQUIRED. OBS bucket (globally unique) receiving the LTS transfers. Supports the {account-name} token."
}

variable "kms_archive_alias" {
  type        = string
  description = "REQUIRED. KMS alias for the archive-bucket key. Supports the {account-name} token."
}

variable "archive_cold_after_days" {
  type        = number
  default     = 0
  description = "Days before archive objects move to the COLD storage class (0 = never)."
}

variable "archive_retention_days" {
  type        = number
  default     = 365
  description = "Archive bucket object expiration (days)."
}

variable "kms_pending_days" {
  type        = number
  default     = 7
  description = "KMS key pending-delete window (days). Production: 30."
}

variable "archive_bucket_force_destroy" {
  type        = bool
  default     = false
  description = "DANGER: allow Terraform to delete a NON-EMPTY archive bucket (deletes archived logs). Only needed to recreate on an archive_bucket_name rename."
}

# --- Transfer schedule ---
# Note: Supported intervals are 2/5/30 minutes or 1/3/6/12 hours.

variable "transfer_period" {
  type        = number
  default     = 30
  description = "OBS transfer interval length. Valid with transfer_period_unit: 2|5|30 min, 1|3|6|12 hour."
}

variable "transfer_period_unit" {
  type        = string
  default     = "min"
  description = "OBS transfer interval unit: min | hour."
}

variable "tags" {
  type    = map(string)
  default = {}
}
