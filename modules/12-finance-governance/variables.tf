variable "home_region" {
  type        = string
  description = "Region for financial governance resources"
}

variable "required_tags" {
  type = list(object({
    key          = string
    allowed_values = optional(list(string), [])
  }))
  description = "Tags that must be present on all resources"
  default = [
    { key = "Environment", allowed_values = ["production", "staging", "dev", "sandbox"] },
    { key = "CostCenter", allowed_values = [] },
    { key = "Owner", allowed_values = [] },
    { key = "Project", allowed_values = [] },
  ]
}

variable "budget_alerts" {
  type = list(object({
    name            = string
    limit_amount    = number
    currency        = optional(string, "USD")
    time_unit       = optional(string, "MONTHLY")
    threshold_percent = number
    smn_topic_urn   = optional(string, "")
    email           = optional(string, "")
  }))
  description = "Budget alerts to configure"
  default     = []
}

variable "root_id" {
  type        = string
  description = "Organizations root ID for tag policy attachment"
}

variable "tags" {
  type        = map(string)
  description = "Tags for finance governance resources"
  default     = {}
}
