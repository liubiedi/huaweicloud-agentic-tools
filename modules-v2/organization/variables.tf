# ---- Module 1 - organization and account management ----

variable "environment" {
  type        = string
  description = "Environment label applied as a tag on resources"
  default     = "shared"
}

variable "home_region" {
  type        = string
  description = "Region registered with Identity Center before the IC service is started."
  default     = "ap-southeast-3"
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged into the module's standard tag set"
  default     = {}
}

# ---- Organization ----

variable "enabled_policy_types" {
  type        = set(string)
  description = "Policy types enabled at the org root. Required before any SCP / tag policy / dry-run policy can attach."
  default     = ["service_control_policy", "tag_policy"]

  validation {
    condition     = alltrue([for t in var.enabled_policy_types : contains(["service_control_policy", "tag_policy"], t)])
    error_message = "enabled_policy_types must only contain 'service_control_policy' and/or 'tag_policy'."
  }
}

# ---- Organizational Units ----

variable "organizational_units" {
  type = map(object({
    parent = optional(string, "")
  }))
  description = <<-EOT
    OUs to create. Map keyed by OU name. Each entry's `parent` field is either:
      - ""        (or "root") -> attach under the org root
      - "<OU>"    -> attach under another OU defined in this same map

    Self-referential ordering is resolved by Terraform automatically. Cycles
    will fail at plan time. Max depth is bounded by the Huawei Organizations
    API (typically 5 levels under root).
  EOT
  default = {
    Workloads = { parent = "" }
  }
}

# ---- Account creation - Pattern C ----

variable "core_accounts" {
  type = map(object({
    email       = string
    ou          = optional(string, "")
    description = optional(string, "")
  }))
  description = <<-EOT
    Core accounts (logging, security, network, ops, etc.). Map keyed by account
    name. Each entry: email (must be unique org-wide), ou (OU name from
    var.organizational_units; empty = root), description.

    Every account created here also gets a server-side cross-account agency
    named var.cross_account_agency_name (default OrganizationAccountAccessAgency),
    allowing the master to assume into the account immediately.
  EOT
}

variable "workload_accounts" {
  type = map(object({
    email       = string
    ou          = optional(string, "")
    description = optional(string, "")
  }))
  description = "Workload accounts (apps, environments). Same shape as core_accounts."
  default     = {}
}

variable "cross_account_agency_name" {
  type        = string
  description = "Name of the cross-account trust agency auto-created in each created account. The default is the name Huawei creates automatically."
  default     = "OrganizationAccountAccessAgency"
}

# ---- Identity Center ----

variable "identity_center_alias" {
  type        = string
  description = "Optional alias for the Identity Center instance. Empty = no alias set."
  default     = ""
}

# ---- Trusted services ----

variable "trusted_services" {
  type        = list(string)
  description = <<-EOT
    Organizations trusted service identifiers (format: service.<NAME>, e.g.
    service.CTS). Discover available via:
      data "huaweicloud_organizations_trusted_services_options" {}
    Default ships a baseline set: CTS (org-wide aggregation), IdentityCenter
    (org-wide IC), RAM (org-wide resource sharing).
  EOT
  default = [
    "service.CTS",
    "service.IdentityCenter",
    "service.RAM",
  ]
}

variable "delegated_administrators" {
  type        = map(string)
  description = <<-EOT
    Per-service delegated administrators. Keyed by service principal (e.g.
    "service.SecMaster"); value is the account name (key in core_accounts or
    workload_accounts) to delegate administration to. The module resolves the
    account name to its ID via the resource map.

    AccessAnalyzer and COC support at most 1 delegated admin; other services
    are unlimited but this map enforces one per service by construction.
    Every key here MUST also appear in var.trusted_services (the service must
    be enabled before it can have a delegated admin).
  EOT
  default     = {}
}

# ---- Tag policies (optional) ----
# Tag-key governance is expressed entirely via tag_policies (one per row of the
# 01_Foundation TagPolicies sheet). A row with blank values + blank scope is
# key-presence-only enforcement.

variable "tag_policies" {
  type = list(object({
    name        = string
    description = string
    content     = string
  }))
  description = "Additional custom tag policies. Content is raw Huawei tag-policy JSON."
  default     = []
}

# ---- Enterprise project (single bootstrap) ----

variable "create_enterprise_project" {
  type        = bool
  description = "Create the landing-zone bootstrap enterprise project. Requires EPS permissions on the provider AK/SK. Module 8 creates additional cost-center EPs."
  default     = false
}

variable "enterprise_project_name" {
  type        = string
  description = "Name of the bootstrap enterprise project (only used when create_enterprise_project = true)."
  default     = "landing-zone"
}
