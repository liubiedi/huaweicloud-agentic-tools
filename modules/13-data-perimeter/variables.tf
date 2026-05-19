variable "home_region" {
  type        = string
  description = "Region for data perimeter resources"
}

variable "root_id" {
  type        = string
  description = "Organizations root ID for SCP attachment"
}

variable "vpc_endpoint_services" {
  type = list(object({
    name              = string
    vpc_id            = string
    subnet_id         = string
    service_type      = string
    service_name      = string
    approval_enabled  = optional(bool, false)
  }))
  description = "VPC endpoint services to create for private service access"
  default     = []
}

variable "vpc_endpoints" {
  type = list(object({
    name         = string
    vpc_id       = string
    subnet_id    = string
    service_id   = string
  }))
  description = "VPC endpoints to create in spoke VPCs"
  default     = []
}

variable "allow_services_bypass_region_scp" {
  type        = list(string)
  description = "Service namespaces excluded from the region-boundary SCP"
  default = [
    "iam:*",
    "organizations:*",
    "identitycenter:*",
    "billing:*",
    "bss:*",
    "cts:*",
    "rms:*",
  ]
}

variable "deny_services" {
  type        = list(string)
  description = "Services to explicitly deny in all member accounts via SCP"
  default     = []
}

variable "enforce_mode" {
  type        = bool
  description = "Set to true to switch SCPs from monitor to enforce mode"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags for data perimeter resources"
  default     = {}
}
