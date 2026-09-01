# Module 5 - unified security protection
# Lives in the security account. SecMaster Pattern C (security-only) by default.

variable "environment" {
  type    = string
  default = "shared"
}
variable "tags" {
  type    = map(string)
  default = {}
}

# ---- SecMaster ----

variable "enable_secmaster" {
  type    = bool
  default = true
}

variable "secmaster_workspace_name" {
  type    = string
  default = "lz-secmaster"
}

variable "secmaster_project_name" {
  type        = string
  description = "Project name (region project, typically same as home_region)."
}

variable "secmaster_modules" {
  type        = list(string)
  default     = ["security_governance", "alert_management"]
  description = "Functional modules to enable inside the SecMaster workspace."
}

variable "cloud_log_resources" {
  type = list(object({
    name         = string
    type         = string # e.g., "lts", "cts"
    workspace_id = optional(string, "")
    log_group_id = optional(string, "")
  }))
  default     = []
  description = "Cross-account log sources to ingest into SecMaster. Driven by module 6 outputs."
}

variable "alert_rules" {
  type = list(object({
    name        = string
    description = optional(string, "")
    severity    = string # tips, low, medium, high, fatal
    rule_type   = string # e.g., "log"
    query       = string # detection query
    triggers    = optional(any, {})
  }))
  default     = []
  description = "Baseline SecMaster detection rules. Empty default; populate per security baseline."
}

# ---- HSS (deferred - default off) ----

variable "enable_hss" {
  type    = bool
  default = false
}
variable "hss_quota_count" {
  type    = number
  default = 0
}
variable "hss_host_groups" {
  type    = any
  default = []
}
variable "hss_policy_groups" {
  type    = any
  default = []
}

# ---- DBSS (deferred - default off) ----

variable "enable_dbss" {
  type    = bool
  default = false
}
variable "dbss_specs" {
  type    = any
  default = {}
}

# ---- Future Pattern B upgrade (deferred - default off) ----

variable "enable_member_workspaces" {
  type    = bool
  default = false
}
variable "member_workspace_bindings" {
  type = list(object({
    member_account_workspace_id = string
    member_account_name         = string
  }))
  default = []
}
