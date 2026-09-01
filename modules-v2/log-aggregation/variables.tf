# Module 12 - org-wide LTS log aggregation (log converge) + OBS archive.
#
# Runs in the LTS delegated-admin account (Organizations TrustedServices row
# service.LTS -> DelegatedAdmin). The provider MUST use the assume_role block
# (not agency-token mode): this module creates an OBS bucket, which under
# agency-token mode would land in the MASTER account.
#
# Member log streams (sources) converge into target groups/streams created here
# (hot retention converged_retention_days), and each target group transfers to
# the archive OBS bucket on a cycle (retention archive_retention_days).

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

# ---- Converge mappings (member sources -> admin targets) ----

variable "converge_members" {
  type = map(object({
    account_id = string # member domain ID
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

# ---- Archive bucket ----

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

# ---- Transfer cadence ----
# Valid combinations (Huawei): 2/5/30 min, 1/3/6/12 hour.

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
