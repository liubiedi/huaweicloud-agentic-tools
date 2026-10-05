# --- Edge protection inputs ---
# Note: Deploy in the account owning the EIPs and WAF VPC.
# Note: Dedicated WAF provisions a paid instance; removing Anti-DDoS settings restores defaults.

variable "enterprise_project_id" {
  type        = string
  default     = "0"
  description = "Enterprise project ID for the WAF resources. '0' = default project."
}

variable "tags" {
  type    = map(string)
  default = {}
}

# --- Basic Anti-DDoS inputs ---

variable "eip_ids" {
  type        = map(string)
  default     = {}
  description = "EIP NAME -> ID (05-network eip_ids output). antiddos rows reference these by name."
}

variable "antiddos" {
  type = list(object({
    name = string
    # Network EIP name
    eip = string
    # Traffic-cleaning threshold
    threshold_mbps = optional(number, 100)
    # Note: Account SMN topic name; blank disables notifications.
    alarm_topic = optional(string, "")
  }))
  default     = []
  description = "Basic Anti-DDoS traffic-cleaning config per EIP."
  validation {
    condition = alltrue([
      for a in var.antiddos : contains([10, 30, 50, 70, 100, 120, 150, 200, 250, 300, 1000], a.threshold_mbps)
    ])
    error_message = "threshold_mbps must be one of 10, 30, 50, 70, 100, 120, 150, 200, 250, 300, 1000."
  }
}

# --- Dedicated WAF inputs ---

variable "enable_waf" {
  type        = bool
  default     = false
  description = "Create the dedicated WAF instance + policy + domains."
}

variable "waf_instance_name" {
  type        = string
  default     = "lz-waf"
  description = "Name of the dedicated WAF instance."
}

variable "waf_specification_code" {
  type        = string
  default     = "waf.instance.professional"
  description = "waf.instance.professional (WI-500, 2U4G ECS) | waf.instance.enterprise (WI-100, 8U16G ECS)."
  validation {
    condition     = contains(["waf.instance.professional", "waf.instance.enterprise"], var.waf_specification_code)
    error_message = "waf_specification_code must be waf.instance.professional or waf.instance.enterprise."
  }
}

variable "waf_availability_zone" {
  type        = string
  default     = ""
  description = "AZ for the WAF instance (e.g. ap-southeast-3a)."
}

variable "waf_vpc_id" {
  type        = string
  default     = ""
  description = "VPC the WAF instance lives in (hub DMZ VPC, resolved by the env from 05-network state)."
}

variable "waf_subnet_id" {
  type        = string
  default     = ""
  description = "Subnet for the WAF instance (within waf_vpc_id)."
}

variable "waf_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups for the WAF instance ECS. Empty = the module creates one (ingress 80/443 + egress all)."
}

variable "waf_ecs_flavor" {
  type        = string
  default     = ""
  description = "ECS flavor ID for the WAF engine. Blank = auto-select by spec (professional 2U4G / enterprise 8U16G) via the compute_flavors data source."
}

variable "waf_policy_name" {
  type        = string
  default     = "lz-waf-policy"
  description = "Name of the shared WAF protection policy all domains attach to."
}

variable "waf_domains" {
  type = list(object({
    # Protected domain or IP
    domain = string
    # Client-to-WAF protocol
    client_protocol = optional(string, "HTTP")
    # WAF-to-origin protocol
    server_protocol = optional(string, "HTTP")
    # Origin IP or hostname
    origin_address = string
    origin_port    = optional(number, 80)
    # Note: Required for HTTPS clients.
    certificate_id = optional(string, "")
  }))
  default     = []
  description = "Domains protected by the dedicated WAF instance; origins typically point at the hub ingress ELB private VIP."
}
