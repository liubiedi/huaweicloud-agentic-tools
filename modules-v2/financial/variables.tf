# --- Financial management inputs ---

variable "environment" {
  type    = string
  default = "shared"
}
variable "tags" {
  type    = map(string)
  default = {}
}

# --- Feature switches ---

variable "enable_multi_ep" {
  type    = bool
  default = false
}
variable "enable_predefined_tags" {
  type    = bool
  default = false
}
variable "enable_bulk_tag_resources" {
  type    = bool
  default = false
}

# --- Enterprise projects ---

variable "cost_centers" {
  type = map(object({
    description             = string
    enterprise_project_type = optional(string, "prod")
  }))
  default     = {}
  description = "Map of cost-center EP name -> config. Additive to the 01-foundation bootstrap EP."
}

# --- Predefined tags ---

variable "predefined_tags" {
  type = list(object({
    key    = string
    values = list(string)
  }))
  default = [
    { key = "Project", values = [] },
    { key = "Owner", values = [] },
    { key = "Environment", values = ["production", "staging", "development", "shared"] },
    { key = "BU", values = [] },
  ]
  description = "Canonical predefined tag dictionary. Values list can be empty for free-form values."
}

# --- Bulk resource tags ---

variable "bulk_tag_targets" {
  type = list(object({
    project_id = string
    resources = list(object({
      resource_id   = string
      resource_type = string
    }))
    tags = map(string)
  }))
  default     = []
  description = "Bulk-apply tags to existing resources. Use with care - destructive-ish."
}
