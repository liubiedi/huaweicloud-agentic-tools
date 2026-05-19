variable "home_region" {
  type        = string
  description = "Region for O&M monitoring resources"
}

variable "alert_email_endpoints" {
  type        = list(string)
  description = "Email addresses to subscribe to the ops alert SMN topic"
  default     = []
}

variable "alert_webhook_endpoints" {
  type = list(object({
    url     = string
    protocol = string
  }))
  description = "Webhook endpoints for alert notifications"
  default     = []
}

variable "aom_prometheus_instance_name" {
  type        = string
  description = "AOM Prometheus instance name"
  default     = "lz-prometheus"
}

variable "enable_functiongraph_runbooks" {
  type        = bool
  description = "Deploy FunctionGraph automation runbooks"
  default     = true
}

variable "functiongraph_agency" {
  type        = string
  description = "Agency name for FunctionGraph execution"
  default     = "lz-functiongraph-agency"
}

variable "log_group_id" {
  type        = string
  description = "LTS log group ID for FunctionGraph function logs"
  default     = ""
}

variable "enterprise_project_id" {
  type        = string
  description = "Enterprise project ID"
  default     = "0"
}

variable "tags" {
  type        = map(string)
  description = "Tags for O&M resources"
  default     = {}
}
