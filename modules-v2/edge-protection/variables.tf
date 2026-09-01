# Module 13 - edge protection: Basic Anti-DDoS thresholds on EIPs + a dedicated
# WAF instance/policy/domains.
#
# Deploys into the account that owns the protected EIPs and the WAF VPC - the
# network hub account (the env passes a hub provider alias). Both APIs work in
# agency-token cross-account mode (no OBS / v5-IAM here).
#
# Anti-DDoS Basic is pay-per-use tuning of the free per-EIP protection: destroy
# resets the EIP to the default cleaning threshold rather than deleting anything.
# The dedicated WAF instance is postPaid (fully Terraform-provisionable); CNAD
# Advanced / AAD need pre-purchased instances and are out of scope.

variable "enterprise_project_id" {
  type        = string
  default     = "0"
  description = "Enterprise project ID for the WAF resources. '0' = default project."
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ---- Anti-DDoS Basic ----

variable "eip_ids" {
  type        = map(string)
  default     = {}
  description = "EIP NAME -> ID (05-network eip_ids output). antiddos rows reference these by name."
}

variable "antiddos" {
  type = list(object({
    name           = string
    eip            = string                # FK -> eip_ids key (05-network EIP name)
    threshold_mbps = optional(number, 100) # traffic-cleaning threshold
    alarm_topic    = optional(string, "")  # SMN topic NAME in this account (resolved to a URN); blank = no alarm notification
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

# ---- Dedicated WAF ----

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
    domain          = string                   # protected domain (or IP), e.g. app.example.com
    client_protocol = optional(string, "HTTP") # browser -> WAF: HTTP | HTTPS
    server_protocol = optional(string, "HTTP") # WAF -> origin:  HTTP | HTTPS
    origin_address  = string                   # origin server IP/hostname (e.g. the ELB VIP)
    origin_port     = optional(number, 80)
    certificate_id  = optional(string, "") # required when client_protocol = HTTPS
  }))
  default     = []
  description = "Domains protected by the dedicated WAF instance; origins typically point at the hub ingress ELB private VIP."
}
