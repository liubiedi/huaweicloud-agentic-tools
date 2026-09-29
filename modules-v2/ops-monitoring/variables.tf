# --- Monitoring inputs ---

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
  description = "Account this ops module instance deploys into. Substituted for the {account-name} token in topic_name."
}

# --- Notification inputs ---

variable "topic_name" {
  type    = string
  default = "{account-name}-lz-alerts"
}

variable "subscribers" {
  type = list(object({
    # Supported notification protocols
    protocol = string
    endpoint = string
  }))
  default     = []
  description = "Topic subscribers. Email subscribers require out-of-band confirmation (click link in email)."
}

variable "smn_lts_group_id" {
  type        = string
  default     = ""
  description = "LTS group ID for SMN delivery logs (a module 6 LTS group). Blank = no SMN log delivery."
}

variable "smn_lts_stream_id" {
  type    = string
  default = ""
}

# --- One-click alarm inputs ---

variable "one_click_alarms" {
  type = list(object({
    namespace     = string
    event_enabled = optional(bool, true)
  }))
  default     = []
  description = "Cloud Eye one-click monitoring bundles to enable. one_click_alarm_id is resolved from namespace via the ces_one_click_alarms data source. The bundle applies to all resources of the service; event_enabled toggles its event alarm rules. Each enabled bundle notifies the SMN topic."
}

variable "custom_alarm_rules" {
  type    = any
  default = []
}

# --- Optional AOM and FunctionGraph inputs ---

variable "enable_aom" {
  type    = bool
  default = false
}
variable "enable_fgs" {
  type    = bool
  default = false
}
